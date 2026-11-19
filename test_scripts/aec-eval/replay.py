"""Replays a saved meeting recording through untype's own echo cancellation
(plan-072) and says how much of the call is left on the user's side.

    python test_scripts/aec-eval/replay.py <recording folder> [--out DIR]
        [--call-late SECONDS] [--no-transcribe] [--speed N]

Steps (all output in DIR, default .build/aec-replay/<recording>):
1. The recording's .mic.m4a and .system.m4a are decoded to 16 kHz mono WAV.
2. How late the system audio is in the saved files is measured (recordings
   made before plan-072 step 2 placed it by arrival; see lagscan.py), unless
   --call-late is given.
3. The microphone goes through the app's MeetingEchoAligner and WebRTC's
   canceller (`swift test --filter meetingEchoReplay`, run in the repository),
   as the two streams would have arrived: <stem>.untype-aec.wav.
4. Levels before and after while the call talks and while it is silent.
5. Unless --no-transcribe: the original and the cleaned microphone audio are
   transcribed with test_scripts/voice-filter/probe.ts (Soniox, needs
   SONIOX_API_KEY or ~/.tool-agents/untype/.env) and every word is checked
   against the call's side of the recording's transcript (<stem>.segments.jsonl):
   a microphone word that the call said within 6 s counts as the call's.

Needs ffmpeg, node 22 or later, Python with numpy, scipy and soundfile.
"""
import argparse
import csv
import json
import os
import re
import subprocess
import sys
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import correlate

SR = 16000
REPO = Path(__file__).resolve().parents[2]


def decode(source, target):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-ac", "1", "-ar", str(SR), "-c:a", "pcm_s16le", str(target)], check=True)


def db(x):
    return 10 * np.log10(np.mean(x.astype(np.float64) ** 2) + 1e-12)


def call_late(mic, ref):
    """Seconds the system audio is late against the microphone's echo in the
    saved files (0 when it is not late), from 20 s windows."""
    n = min(len(mic), len(ref))
    lags = []
    for start in range(0, n // SR - 20, 20):
        a = mic[start * SR:(start + 20) * SR].astype(np.float64)
        b = ref[start * SR:(start + 20) * SR].astype(np.float64)
        if np.std(b) < 1e-4 or np.std(a) < 1e-4:
            continue
        c = correlate(a - a.mean(), b - b.mean(), mode="full", method="fft")
        mid = len(b) - 1
        m = 3 * SR
        w = c[mid - m:mid + m + 1]
        k = int(np.argmax(np.abs(w)))
        corr = abs(w[k]) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12)
        if corr > 0.2:
            lags.append((k - m) / SR)
    if not lags:
        return 0.0, 0
    lag = float(np.median(lags))
    # A positive lag is the loudspeakers' delay to the microphone; a negative
    # one means the system audio was placed late.
    return max(0.0, -lag), len(lags)


def levels(mic, ref, out):
    n = min(len(mic), len(ref), len(out))
    hop = SR // 10
    k = n // hop
    e = lambda x: np.array([db(x[i * hop:(i + 1) * hop]) for i in range(k)])
    e_mic, e_ref, e_out = e(mic[:n]), e(ref[:n]), e(out[:n])
    idx = np.arange(k) >= 50
    on, off = (e_ref > -45) & idx, (e_ref < -65) & idx

    def lvl(v, m):
        return 10 * np.log10(np.mean(10 ** (v[m] / 10))) if m.any() else float("nan")

    red = e_mic - e_out
    lines = [
        f"call talking ({on.sum() / 10:.0f} s): microphone {lvl(e_mic, on):.1f} dB -> {lvl(e_out, on):.1f} dB; "
        + "reduction 10/50/90 %: " + " / ".join(f"{np.percentile(red[on], q):.1f}" for q in (10, 50, 90)) if on.any() else "call talking: never",
        f"call silent ({off.sum() / 10:.0f} s): microphone {lvl(e_mic, off):.1f} dB -> {lvl(e_out, off):.1f} dB",
    ]
    own = off & (e_mic > -45)
    if own.any():
        lines.append(f"the user alone ({own.sum() / 10:.0f} s): median change {np.median(red[own]):.1f} dB")
    return lines


def norm(text):
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    return re.sub(r"[^\w]", "", text)


def transcribe(wav, out_dir, speed):
    log = out_dir.with_suffix(".log")
    with open(log, "w") as handle:
        subprocess.run(["node", "--experimental-strip-types", "--no-warnings", str(REPO / "test_scripts/voice-filter/probe.ts"), str(wav),
                        "--speed", str(speed), "--out", str(out_dir)], check=True, stdout=handle, stderr=subprocess.STDOUT, cwd=REPO)
    with open(out_dir / "words.tsv", encoding="utf8") as handle:
        return [(float(r["start_s"]), r["word"]) for r in csv.DictReader(handle, delimiter="\t")]


def score(words, call_segments):
    """(words, the call's, only the microphone's, list of the microphone's)."""
    call = own = 0
    kept = []
    for start, word in words:
        w = norm(word)
        if not w:
            continue
        if any(w in said and a - 6 <= start <= b + 6 for a, b, said in call_segments):
            call += 1
        else:
            own += 1
            kept.append(word)
    return call + own, call, own, kept


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--call-late", type=float)
    parser.add_argument("--no-transcribe", action="store_true")
    parser.add_argument("--speed", type=float, default=2)
    args = parser.parse_args()

    mics = sorted(args.folder.glob("*.mic.m4a"))
    if len(mics) != 1:
        sys.exit(f"expected one .mic.m4a in {args.folder}, found {len(mics)}")
    stem = mics[0].name[: -len(".mic.m4a")]
    out = (args.out or REPO / ".build/aec-replay" / stem).resolve()
    out.mkdir(parents=True, exist_ok=True)
    base = out / stem

    decode(args.folder / f"{stem}.mic.m4a", f"{base}.mic.wav")
    decode(args.folder / f"{stem}.system.m4a", f"{base}.system.wav")
    mic, _ = sf.read(f"{base}.mic.wav", dtype="float32")
    ref, _ = sf.read(f"{base}.system.wav", dtype="float32")
    if args.call_late is None:
        late, windows = call_late(mic, ref)
        print(f"{stem}: {len(mic) / SR:.0f} s; system audio late in the files: {late:.3f} s (from {windows} windows)")
    else:
        late = args.call_late
        print(f"{stem}: {len(mic) / SR:.0f} s; system audio late in the files: {late:.3f} s (given)")

    env = dict(os.environ, UNTYPE_AEC_REPLAY=str(base), UNTYPE_AEC_CALL_LATE=str(late))
    result = subprocess.run(["swift", "test", "--filter", "meetingEchoReplay"], cwd=REPO, env=env, capture_output=True, text=True)
    replay = [line for line in result.stdout.splitlines() if line.startswith("replay:")]
    if result.returncode != 0 or not replay:
        sys.exit("the replay failed:\n" + "\n".join(result.stdout.splitlines()[-30:]))
    print("\n".join(replay))

    cleaned, _ = sf.read(f"{base}.untype-aec.wav", dtype="float32")
    shift = int(round(late * SR))
    aligned_ref = ref[shift:] if shift > 0 else ref
    print("\n".join(levels(mic, aligned_ref, cleaned)))

    if args.no_transcribe:
        return
    segments_file = args.folder / f"{stem}.segments.jsonl"
    call_segments = []
    for line in open(segments_file, encoding="utf8"):
        segment = json.loads(line)
        if segment.get("side") == "call":
            call_segments.append((segment["startMs"] / 1000, segment["endMs"] / 1000, {norm(w) for w in segment["text"].split()}))
    with ThreadPoolExecutor(2) as pool:
        original = pool.submit(transcribe, f"{base}.mic.wav", out / "words-original", args.speed)
        after = pool.submit(transcribe, f"{base}.untype-aec.wav", out / "words-cleaned", args.speed)
        results = {"original": original.result(), "cleaned": after.result()}
    for name, words in results.items():
        total, call, own, kept = score(words, call_segments)
        print(f"{name} microphone: {total} words; also said by the call within 6 s: {call}; only the microphone's: {own}")
    _, _, _, kept = score(results["cleaned"], call_segments)
    (out / "cleaned-words.txt").write_text(" ".join(kept) + "\n", encoding="utf8")
    print(f"the cleaned microphone's words: {out / 'cleaned-words.txt'}")


main()
