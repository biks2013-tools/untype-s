# Soniox WebSocket in Swift

## Overview

This document maps the current `untype` Soniox behavior to a direct Swift implementation over `URLSessionWebSocketTask`.

Interpretation:
- The target is a drop-in real-time STT transport replacement, not a feature redesign.
- The Swift client should preserve the current wrapper semantics from `untype/src/soniox/client.ts`, including marker filtering, repeated finalized-prefix handling, and graceful shutdown ordering.
- I treated the current `@soniox/node` / Soniox JS SDK as the behavioral reference for session lifecycle and event shapes, and the Soniox docs as the contract for WebSocket and finalization behavior.

## Key Concepts

### 1) WebSocket session model

Soniox real-time STT is a persistent WebSocket session. The official docs describe the API as real-time transcription over a persistent WebSocket, with manual finalization supported as a first-class operation. The Node SDK docs describe the same flow as streaming transcription over WebSocket, with results consumable via events, async iteration, or buffering helpers. citeturn0search3turn0search5turn0search9

### 2) Transport split: JSON control frames vs audio frames

The upstream Soniox JS SDK sends a JSON config message immediately after the socket opens, then sends raw audio chunks as binary WebSocket messages. The same implementation uses JSON text frames for `finalize` and `keepalive`, and uses an empty text frame to signal end-of-audio during `finish()`. The Swift implementation should preserve that separation. `URLSessionWebSocketTask` supports both binary and UTF-8 text messages, which makes it a direct fit. citeturn0search13turn0search1

### 3) Result shape and event contract

The JS SDK parses server messages into a result object with:
- `tokens[]`
- `final_audio_proc_ms`
- `total_audio_proc_ms`
- `finished`

Each token carries:
- `text`
- `start_ms`
- `end_ms`
- `confidence`
- `is_final`
- optional `speaker`
- optional `language`
- optional `translation_status`
- optional `source_language`

The public event surface in the Soniox JS SDK includes `result`, `token`, `endpoint`, `finalized`, and `finished`, plus error and state-change events in the higher-level recording layer. citeturn0search5turn0search9

### 4) Finalization semantics

The official docs say manual finalization is done by sending a WebSocket message with `type: "finalize"`. The JS SDK implements that directly, and its `finish()` method then sends an empty text message and waits for the server to emit `finished`. citeturn0search1turn0search2

### 5) Error contract

Soniox documents stable error types at the API layer, with a machine-readable `error_type`, a human-readable message, and a request ID for support. The current `untype` wrapper maps SDK/auth/network/protocol errors into app-level error types before they cross the wrapper boundary. A Swift implementation should preserve that separation: transport failures from `URLSessionWebSocketTask` should map to network/disconnect errors, while Soniox-provided JSON error payloads should map to provider/auth/protocol errors. citeturn0search4turn0search7

## Current `untype` Behavior To Preserve

Source references:
- [Current Soniox wrapper](~/aiwork/coding-platform/untype/src/soniox/client.ts#L108)
- [Current Soniox tests](~/aiwork/coding-platform/untype/tests/soniox-client.test.ts#L297)

Observed behavior:
- Connects with `realtime.ws_base_url` and a single-model STT config.
- Uses `audio_format: "pcm_s16le"`, `sample_rate`, `num_channels: 1`, and endpoint detection by default.
- Uses `language_hints` for explicit languages, or language identification when `["auto"]` is requested.
- Guards `sendAudio()` so audio is only forwarded when the session state is `connected`.
- Filters `<end>` and `<fin>` marker tokens before they reach callbacks.
- Treats repeated finalized prefixes defensively instead of appending them blindly.
- Uses `finalize() -> short drain -> finish() -> fallback close()` for shutdown.

## Swift Implementation Guidance

### 1) Use `URLSessionWebSocketTask` as the transport

Create the socket with `URLSession.webSocketTask(with:)`, then `resume()` it. Apple’s API supports both text and binary messages, and `receive()` returns complete WebSocket messages rather than low-level frames. That is sufficient for Soniox because the protocol is message-oriented: JSON config/control messages and binary PCM chunks. citeturn5search0turn5search2turn5search3

Recommended structure:

```swift
final class SonioxRealtimeSession {
    private let task: URLSessionWebSocketTask
    private var committedFinals = ""
    private var pendingResultText = ""

    init(url: URL, session: URLSession = .shared) {
        self.task = session.webSocketTask(with: url)
    }

    func connect(config: SonioxConfig) async throws {
        task.resume()
        try await task.send(.string(config.jsonString))
        startReceiveLoop()
    }

    func sendAudio(_ pcm: Data) async throws {
        try await task.send(.data(pcm))
    }

    func finalize() async throws {
        try await task.send(.string(#"{"type":"finalize"}"#))
    }

    func finish() async throws {
        try await finalize()
        try await task.send(.string(""))
        // Then wait for a server "finished" result before closing.
    }
}
```

### 2) Model config as a single JSON frame

Use one initial text frame that carries the session config. The upstream JS SDK sends:
- `api_key`
- `model`
- `audio_format`
- `sample_rate`
- `num_channels`
- `language_hints`
- `language_hints_strict`
- `enable_speaker_diarization`
- `enable_language_identification`
- `enable_endpoint_detection`
- `client_reference_id`
- `max_endpoint_delay_ms`
- `context`
- `translation`

For the current `untype` replacement, the minimum parity set is:
- `api_key`
- `model`
- `audio_format: pcm_s16le`
- `sample_rate`
- `num_channels: 1`
- `enable_endpoint_detection`
- either `language_hints` or `enable_language_identification`

### 3) Treat incoming JSON as the source of truth

Parse every string message as JSON and map it into a typed result struct. Handle:
- token arrays
- `finished`
- `final_audio_proc_ms`
- `total_audio_proc_ms`
- optional server error fields

Do not infer finality solely from socket close events. The provider’s semantic events are part of the protocol.

### 4) Preserve semantic events in your Swift API

The simplest parity layer is:

- `onResult(RealtimeResult)`
- `onToken(RealtimeToken)` optional, if you want Node/JS parity
- `onEndpoint()`
- `onFinalized()`
- `onFinished()`
- `onError(Error)`

If you prefer a Swift concurrency surface, expose both:
- a callback-based API for parity with the current wrapper
- an `AsyncSequence` for ergonomic consumption

### 5) Keep the current prefix-merge strategy

The current wrapper assumes Soniox may resend a finalized prefix across result frames. The safe merge rule is:
- if the incoming finals start with the already-committed text, replace the committed text with the longer snapshot
- if the committed text ends with the incoming finals, treat it as a duplicate delta and do not append
- otherwise merge using longest suffix/prefix overlap

This is the right default for direct WebSocket Swift because it tolerates both snapshot-style and delta-style final token streams.

### 6) Filter marker tokens at the boundary

Drop `<end>` and `<fin>` before they reach UI text or downstream callbacks. The current `untype` wrapper and tests treat these as protocol markers, not transcript content. If you also expose `onToken`, decide whether the raw token stream or the filtered token stream is the public contract; the existing wrapper filters them out.

### 7) Mirror the current shutdown contract

The current wrapper wants:
1. `finalize()`
2. short drain window
3. `finish()`
4. fallback to `close()` if the provider never finishes

In Swift, the cleanest equivalent is:
- send `finalize`
- wait a short grace period for trailing final tokens
- send the empty finish sentinel used by the JS SDK
- wait for a `finished` result
- force-close if the server does not complete in time

That keeps the user-visible behavior aligned with the existing CLI wrapper.

## Gaps Versus `@soniox/node`

The direct Swift implementation will likely be thinner than the JS SDK unless you intentionally recreate these layers:

- No built-in `pause()` / `resume()` keepalive behavior unless you add it.
- No automatic state machine or state-change events unless you model them.
- No async iterator / buffered result helpers unless you wrap them.
- No automatic result-to-utterance accumulation unless you implement it.
- No built-in recovery / reconnect logic unless you add it.
- No built-in token-grouping helpers for speaker/language/translation.

The upstream JS SDK also exposes richer eventing in its higher-level layer:
- `token`
- `endpoint`
- `finalized`
- `finished`
- `state_change`
- `connected`
- reconnect-related events
- source mute/unmute events

If the Swift replacement is meant to stay “drop-in” at the app boundary, you probably want at least `result`, `endpoint`, `finalized`, `finished`, and `error`, plus a small state enum.

## Best Practices

- Keep the WebSocket message types explicit. Binary is audio; string is protocol.
- Make the receive loop a single serialization point for all incoming server messages.
- Decode errors before treating a string as transcript data.
- Keep `committedFinals` and per-result partial text separate.
- Reset transcript state on endpoint and finish.
- Treat disconnects differently from protocol errors.

## Common Pitfalls

- Sending PCM as a string frame instead of binary data.
- Treating `finish()` as identical to `finalize()`.
- Appending repeated final text blindly, which produces duplicated prefixes.
- Surfacing `<end>` and `<fin>` markers as literal transcript content.
- Closing the socket immediately after `finalize()` and losing trailing finals.
- Assuming every server error will arrive as a WebSocket close event instead of JSON payload data.

## Advanced Topics

### AsyncSequence wrapper

If you want a Swift-native consumption model, expose the receive loop as `AsyncThrowingStream<SonioxEvent, Error>`. That gives you a clean bridge between:
- raw WebSocket transport
- parsed Soniox events
- UI or CLI consumers

### Error normalization

Map errors in two layers:
- transport layer: `URLError`, socket close, timeout, malformed JSON
- provider layer: Soniox `error_type` / error payloads

This matches the spirit of the current Node wrapper, which normalizes SDK exceptions before exposing them to the rest of the app.

## Assumptions & Scope

### Assumptions Made

| Assumption | Confidence | Impact if Wrong |
|---|---:|---|
| “Direct WebSocket implementation” means bypassing `@soniox/node` and talking to the Soniox STT WebSocket API from Swift. | HIGH | The transport guidance would need a different abstraction if a Node bridge is still in play. |
| The Swift client should preserve current `untype` semantics rather than adopt the richer JS SDK UI model. | HIGH | The event surface could expand to include more SDK-specific callbacks. |
| `pcm_s16le` mono audio is the target audio format for parity with the current wrapper. | HIGH | Audio encoding and sample-rate handling would change. |
| The replacement should continue filtering `<end>` and `<fin>` markers. | HIGH | UI text and downstream transcript logic would need adjustments. |
| `finish()` should remain a graceful, wait-for-final-results operation rather than an immediate close. | HIGH | Shutdown behavior and user-visible transcript completeness would change. |

### Uncertainties & Gaps

- The public Soniox docs page rendered in this environment does not expose a detailed frame-by-frame schema in the HTML output, so the exact server-side JSON field names were validated primarily from the official JS SDK source and types.
- The official docs clearly document `finalize`, but they do not explicitly spell out the JS SDK’s `finish()` empty-string sentinel. That behavior is an upstream SDK implementation detail, not a documented protocol guarantee.
- I did not find a Soniox-published Swift SDK to compare against, so this research uses the current JS SDK and Node docs as the parity reference.

### Clarifying Questions for Follow-up

1. Do you want the Swift replacement to expose a callback API, an `AsyncSequence`, or both?
2. Should the Swift layer preserve the current `endpoint` / `finalized` distinction, or collapse both into one “utterance committed” callback?
3. Do you want the implementation to include pause/resume keepalive behavior, or only the minimum `connect` / `sendAudio` / `finalize` / `finish` path?
4. Should transport and provider errors be preserved as separate enum families, or normalized into one app-level error type?

## References

### Source Behavior Files

1. [Current Soniox wrapper](~/aiwork/coding-platform/untype/src/soniox/client.ts)
2. [Current Soniox tests](~/aiwork/coding-platform/untype/tests/soniox-client.test.ts)

### Official Soniox Docs

3. Soniox API reference - WebSocket API: https://soniox.com/docs/api-reference/stt/websocket-api
4. Soniox real-time transcription: https://soniox.com/docs/stt/rt/real-time-transcription
5. Soniox manual finalization: https://soniox.com/docs/stt/rt/manual-finalization
6. Soniox API errors: https://soniox.com/docs/api-reference/errors
7. Soniox Node SDK real-time transcription: https://soniox.com/docs/sdk/node-SDK/stt/realtime-transcription
8. Soniox Node SDK package README: https://github.com/soniox/soniox-js/tree/main/packages/node

### Apple Docs

9. URLSessionWebSocketTask: https://developer.apple.com/documentation/foundation/urlsessionwebsockettask
10. URLSessionWebSocketTask.Message: https://developer.apple.com/documentation/foundation/urlsessionwebsockettask/message

### Upstream Soniox SDK Source

11. `soniox-js/packages/core/src/realtime/stt.ts`
12. `soniox-js/packages/core/src/types/realtime.ts`
13. `soniox-js/packages/react/src/store.ts`
14. `soniox-js/packages/react/src/use-recording.ts`

### Recommended for Deep Reading

- Soniox WebSocket API: best source for protocol-level expectations around the real-time socket.
- `packages/core/src/realtime/stt.ts`: best source for the actual current SDK wire behavior, including config, finalize, finish, and event parsing.
- Apple `URLSessionWebSocketTask`: best source for the Swift transport mechanics.
