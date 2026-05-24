# Soniox Live Smoke Test

## Purpose
Verify the concrete Swift `URLSessionWebSocketTask` receive loop and Soniox frame adapter against the live Soniox realtime endpoint through the CLI runtime path.

## Prerequisites
- macOS host with network access to the configured Soniox WebSocket endpoint.
- Valid `SONIOX_API_KEY`.
- Built Swift executable: `swift build`.
- Microphone permission can be granted to the built executable or hosting terminal.

## Command
```sh
SONIOX_API_KEY='<redacted>' \
.build/debug/untype --no-refine --stt-provider soniox --language en --output-mode append --verbose
```

## Expected Result
- The command starts without configuration errors.
- Stderr shows runtime startup diagnostics only when `--verbose` is enabled.
- Spoken words appear on stdout as partial/final transcript lines.
- No API key, prompt text, or transcript content is persisted to protocol settings.
- `Control-C` finalizes pending provider output, closes the WebSocket cleanly, and exits deterministically.

## Failure Signals
- `soniox_auth`: credential rejected or expired.
- `soniox_network`: DNS, TLS, WebSocket connection, send, or receive failure.
- `soniox_protocol`: unexpected server message or invalid adapter state.
- Missing microphone permission or capture failure should surface as a typed microphone error once AVFoundation capture is wired.
