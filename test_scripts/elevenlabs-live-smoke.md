# ElevenLabs Live Smoke Test

## Purpose
Verify the concrete Swift `URLSessionWebSocketTask` request path and ElevenLabs frame adapter against the live ElevenLabs realtime endpoint through the CLI runtime path.

## Prerequisites
- macOS host with network access to the configured ElevenLabs WebSocket endpoint.
- Valid `ELEVENLABS_API_KEY`.
- Built Swift executable: `swift build`.
- Microphone permission can be granted to the built executable or hosting terminal.

## Command
```sh
ELEVENLABS_API_KEY='<redacted>' \
.build/debug/untype --no-refine --stt-provider elevenlabs --language auto --output-mode append --verbose
```

## Expected Result
- The command starts without configuration errors.
- Stderr shows runtime startup diagnostics only when `--verbose` is enabled.
- Spoken words appear on stdout as partial/final transcript lines.
- The WebSocket request uses the `xi-api-key` header and realtime query parameters for model, audio format, sample rate, commit strategy, and timestamps.
- No API key, prompt text, or transcript content is persisted to protocol settings.
- `Control-C` sends a best-effort final commit, closes the WebSocket cleanly, and exits deterministically.

## Failure Signals
- `elevenlabs_auth`: credential rejected, expired, missing permissions, or policy rejection.
- `elevenlabs_network`: DNS, TLS, WebSocket connection, send, or receive failure.
- `elevenlabs_protocol`: unexpected server message, malformed JSON, or server-side protocol error.
- Missing microphone permission or capture failure should surface as a typed microphone error once AVFoundation capture is wired.
