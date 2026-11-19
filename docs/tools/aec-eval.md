# aec-eval

`test_scripts/aec-eval/` measures the meeting's echo cancellation (plan-072): how much of the call, heard through the loudspeakers, is left on the user's side, and how the two audio streams are timed. The main tool is `replay.py`; the others measure one thing each.

## replay.py: a saved recording through untype's own echo cancellation

```
python test_scripts/aec-eval/replay.py "<recording folder>" [--out DIR] [--call-late SECONDS] [--no-transcribe] [--speed N]
```

| Option | Meaning |
|---|---|
| `<recording folder>` | A meeting folder with one `*.mic.m4a`, its `*.system.m4a` and `*.segments.jsonl` (both audio sides must have been saved: Settings → Meetings → Audio) |
| `--out` | Where the work files go; default `.build/aec-replay/<recording>` |
| `--call-late` | How late the system audio is in the saved files, in seconds; measured when not given |
| `--no-transcribe` | Levels only, nothing sent to Soniox |
| `--speed` | How much faster than real time the audio is sent to Soniox (default 2) |

What it does:

1. Decodes both sides to 16 kHz mono WAV (ffmpeg).
2. Measures how late the system audio is in the files, by correlating the microphone with it in 20 s windows (median). Recordings made before plan-072 step 2 placed the system audio by arrival and can be seconds late (`recording-2026-11-19-16-11`: 1.955 s); later ones are in step (0).
3. Runs the microphone through the app's `MeetingEchoAligner` with WebRTC's canceller, with both streams arriving as they would have live (the test `meetingEchoReplay` in `Tests/UntypeCoreTests/MeetingEchoReplayTests.swift`, which runs only when `UNTYPE_AEC_REPLAY` is set). Output: `<stem>.untype-aec.wav`, in step with the microphone's file. Prints what the canceller counted (frames, frames without the call's audio, hold).
4. Prints the microphone's level before and after while the call talks and while it is silent, and the change to the user alone.
5. Unless `--no-transcribe`: transcribes the original and the cleaned microphone with `test_scripts/voice-filter/probe.ts` (Soniox realtime with the user's key; the audio is sent to Soniox again) and counts the words also said by the call within 6 s (from `segments.jsonl`). Writes the cleaned microphone's words to `cleaned-words.txt` for reading.

Needs: ffmpeg; node 22 or later; Python with `numpy`, `scipy`, `soundfile`; `SONIOX_API_KEY` (shell or `~/.tool-agents/untype/.env`) for step 5; the Swift toolchain (step 3 builds and runs the test target).

Results on 2026-11-19 (build 73 recordings, echo cancellation off, no headphones):

| Recording | Call talking: microphone | Call's words on the user's side | The user alone |
|---|---|---|---|
| `recording-2026-11-19-16-11` (337 s, call 1.955 s late in the files) | -19.3 → -31.4 dB, median reduction 31.8 dB | 658 → 0 (126 own words kept) | -2.3 dB |
| `recording-2026-11-19-13-30` (478 s, almost only the call) | -20.0 → -46.2 dB, median reduction 41.3 dB | 791 → 1 (8 own words kept) | -2.7 dB |

## The other scripts

| Script | What it tells |
|---|---|
| `aec_eval.py <base> [mic delay ms]` | WebRTC AEC3 run directly from Python (package `aec-audio-processing`) on `<base>.mic.wav` / `<base>.system.wav`: the first measurement of plan-072, before the app had a canceller. |
| `lagscan.py <base>` | Per 20 s, how far the microphone's echo is behind (+) or ahead (−) of the system audio in the saved files. |
| `microphone-timing.swift [seconds]` | The microphone as the app captures it: whether buffers carry a valid host time, the host clock against `systemUptime`, delivery delay, continuity, drift against the samples counted. |
| `system-audio-timing.swift [seconds] [stall seconds]` | The same for ScreenCaptureKit's system audio; with a stall it blocks the delivery queue once to show that late buffers keep their own timestamps. |

The live checks with the real capture paths are tests that speak through the loudspeakers with `say` and run only when asked: `UNTYPE_LIVE_AUDIO=1 swift test --filter MeetingAudioLive` (no call in progress, no headphones, Screen Recording and Microphone permission for the terminal).
