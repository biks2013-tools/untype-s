# aec-eval

Measurements for the meeting's echo cancellation (plan-072). Documentation: [`docs/tools/aec-eval.md`](../../docs/tools/aec-eval.md).

- `replay.py` — a saved recording through untype's own echo cancellation, with levels and the call's words left on the user's side.
- `aec_eval.py`, `lagscan.py` — offline WebRTC run and the streams' offset in saved files.
- `microphone-timing.swift`, `system-audio-timing.swift` — timing of the two capture paths.
