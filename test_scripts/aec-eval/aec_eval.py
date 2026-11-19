"""Offline check: WebRTC AEC3 on a meeting's microphone with the saved system
audio as the reference. Usage: aec_eval.py <base> [mic_delay_ms]
(<base>.mic.wav and <base>.system.wav, 16 kHz mono PCM16)."""
import sys
import numpy as np
import soundfile as sf
from scipy.signal import correlate
from aec_audio_processing import AudioProcessor

SR = 16000
FRAME = 160  # 10 ms


def db(x):
    return 10 * np.log10(np.mean(x.astype(np.float64) ** 2) + 1e-12)


def lag_ms(mic, ref, start_s, dur_s=20, max_ms=600):
    a = mic[int(start_s * SR):int((start_s + dur_s) * SR)].astype(np.float64)
    b = ref[int(start_s * SR):int((start_s + dur_s) * SR)].astype(np.float64)
    if len(a) < SR or np.std(b) < 1e-4:
        return None, 0
    c = correlate(a - a.mean(), b - b.mean(), mode="full")
    mid = len(b) - 1
    m = int(max_ms * SR / 1000)
    win = c[mid - m:mid + m + 1]
    k = int(np.argmax(np.abs(win)))
    peak = abs(win[k]) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12)
    return (k - m) * 1000.0 / SR, peak


def run_aec(mic, ref, extra_mic_delay_ms=0):
    ap = AudioProcessor(enable_aec=True, enable_ns=False, enable_agc=False, enable_vad=False)
    ap.set_stream_format(SR, 1, SR, 1)
    ap.set_reverse_stream_format(SR, 1)
    ap.set_stream_delay(0)
    d = int(extra_mic_delay_ms * SR / 1000)
    if d > 0:
        mic = np.concatenate([np.zeros(d, dtype=mic.dtype), mic])[:len(mic)]
    n = (min(len(mic), len(ref)) // FRAME) * FRAME
    mic16 = (np.clip(mic[:n], -1, 1) * 32767).astype(np.int16)
    ref16 = (np.clip(ref[:n], -1, 1) * 32767).astype(np.int16)
    out = np.zeros(n, dtype=np.int16)
    for i in range(0, n, FRAME):
        ap.process_reverse_stream(ref16[i:i + FRAME].tobytes())
        o = ap.process_stream(mic16[i:i + FRAME].tobytes())
        out[i:i + FRAME] = np.frombuffer(o, dtype=np.int16)[:FRAME]
    return mic16.astype(np.float32) / 32768, ref16.astype(np.float32) / 32768, out.astype(np.float32) / 32768


def main():
    base = sys.argv[1]
    extra = float(sys.argv[2]) if len(sys.argv) > 2 else 0
    mic, sr1 = sf.read(base + ".mic.wav", dtype="float32")
    ref, sr2 = sf.read(base + ".system.wav", dtype="float32")
    assert sr1 == SR and sr2 == SR
    n = min(len(mic), len(ref))
    mic, ref = mic[:n], ref[:n]
    print(f"{base.split('/')[-1]}: {n / SR:.0f} s  mic {db(mic):.1f} dB  system {db(ref):.1f} dB")

    # Where is the call's echo in the microphone? (positive = mic later than system)
    lags = []
    for start in range(0, int(n / SR) - 20, 30):
        l, p = lag_ms(mic, ref, start)
        if l is not None and p > 0.05:
            lags.append((start, l, p))
    print("lag of mic behind system (ms) per 20 s window [start s, lag, corr]:")
    print("  " + "  ".join(f"[{s},{l:+.0f},{p:.2f}]" for s, l, p in lags))

    mic_d, ref_d, out = run_aec(mic, ref, extra)
    sf.write(base + ".aec.wav", out, SR)

    # Frame classes by a 100 ms energy envelope
    hop = SR // 10
    k = len(out) // hop
    e_mic = np.array([db(mic_d[i * hop:(i + 1) * hop]) for i in range(k)])
    e_ref = np.array([db(ref_d[i * hop:(i + 1) * hop]) for i in range(k)])
    e_out = np.array([db(out[i * hop:(i + 1) * hop]) for i in range(k)])
    call_on = e_ref > -45
    call_off = e_ref < -65
    skip = 50  # first 5 s: convergence
    idx = np.arange(k) >= skip

    def lvl(e, mask):
        m = mask & idx
        return 10 * np.log10(np.mean(10 ** (e[m] / 10))) if m.any() else float("nan")

    print(f"call talking  ({(call_on & idx).sum() / 10:.0f} s): mic {lvl(e_mic, call_on):.1f} dB -> after AEC {lvl(e_out, call_on):.1f} dB")
    print(f"call silent   ({(call_off & idx).sum() / 10:.0f} s): mic {lvl(e_mic, call_off):.1f} dB -> after AEC {lvl(e_out, call_off):.1f} dB")
    # Echo-only frames: call talking and the mic not clearly louder than the echo level
    red = e_mic - e_out
    m = call_on & idx
    print("reduction while the call talks, percentiles 10/50/90 (dB): " + " / ".join(f"{np.percentile(red[m], q):.1f}" for q in (10, 50, 90)))
    m2 = call_off & idx & (e_mic > -45)
    if m2.any():
        print(f"reduction of the user's own speech (call silent, mic > -45 dB, {m2.sum() / 10:.0f} s), median: {np.median(red[m2]):.1f} dB")


main()
