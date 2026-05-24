# Microphone Live Smoke Test

## Purpose
Verify AVFoundation microphone permission handling and mono PCM16 capture through the CLI runtime path.

## Prerequisites
- macOS host with a working default microphone.
- Built Swift executable: `swift build`.
- Valid `SONIOX_API_KEY` for an end-to-end smoke, or adapt the command to another implemented STT provider.

## Command
```sh
SONIOX_API_KEY='<redacted>' \
.build/debug/untype --no-refine --stt-provider soniox --language en --output-mode append --verbose
```

## Expected Result
- If microphone permission has not been requested before, macOS prompts for access.
- Denying access exits with `microphone_permission` and exit code `3`.
- Granting access starts capture and streams mono PCM16 chunks into the active transcriber.
- `Control-C` stops `AVAudioEngine`, removes the input tap, finalizes pending provider output, and exits deterministically.

## Failure Signals
- `microphone_permission`: macOS denied, restricted, or did not expose microphone permission.
- `microphone_capture`: input format, converter, tap, or `AVAudioEngine` startup failure.
- Provider failures should remain provider-typed and must not be reported as microphone failures.
