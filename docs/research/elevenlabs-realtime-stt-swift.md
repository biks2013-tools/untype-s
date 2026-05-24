# ElevenLabs Realtime STT in Swift

## Overview

This document maps the current `untype` ElevenLabs realtime speech-to-text behavior to a Swift implementation using `URLSessionWebSocketTask`.

The source adapter is a direct WebSocket client, not an SDK wrapper. It builds the ElevenLabs realtime URL, injects the API key as `xi-api-key`, sends PCM audio as JSON `input_audio_chunk` frames with base64 payloads, supports both VAD and manual commit strategies, and maps partial/final/error/close events into the project’s provider-neutral transcriber contract. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L54), [Source tests](~/aiwork/coding-platform/untype/tests/elevenlabs-client.test.ts#L103)

## Provenance

- `REFINED_REQUEST_FILE`: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-swift-drop-in-replacement.md`
- `INVESTIGATION_FILE`: `~/aiwork/coding-platform/untype-s/docs/reference/investigation-swift-drop-in-replacement.md`
- Source behavior candidates:
  - `~/aiwork/coding-platform/untype/src/elevenlabs/client.ts`
  - `~/aiwork/coding-platform/untype/tests/elevenlabs-client.test.ts`

## Contract Summary

The current source behavior and the current official docs line up on the core transport model:

- The API is WebSocket-based and streams audio input while returning transcription events.
- Audio chunks are sent as `input_audio_chunk` messages.
- The service emits partial and committed transcript variants.
- Commit behavior can be manual or VAD-driven.
- Committed transcripts can optionally include timestamps when the timestamp option is enabled.

Official docs consulted for this summary:

- ElevenLabs realtime API reference: `wss://api.elevenlabs.io/v1/speech-to-text/realtime`, with `input_audio_chunk` audio messages and transcript events.
- ElevenLabs client-side streaming guide: realtime STT uses Scribe Realtime v2 and supports partial transcripts plus committed transcripts.
- ElevenLabs transcripts/commit guide: committed transcripts can include word-level timestamps when `include_timestamps=true`.
- Apple WebSocket docs: `URLSessionWebSocketTask` supports async send/receive, handshake lifecycle hooks, and delegate close notifications.

## Connection Contract

### URL and query parameters

The source adapter constructs the realtime URL from the configured endpoint and adds these query items:

- `model_id=scribe_v2_realtime`
- `audio_format=pcm_<sampleRate>`
- `sample_rate=<sampleRate>`
- `commit_strategy=vad` when endpoint detection is enabled
- `commit_strategy=manual` when endpoint detection is disabled
- `include_timestamps=false`
- `language_code=<first language>` unless the language list is exactly `["auto"]`

This is implemented in `buildRealtimeUrl()` and covered by tests that assert the generated URL for both VAD and manual commit modes. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L332), [Source tests](~/aiwork/coding-platform/untype/tests/elevenlabs-client.test.ts#L103)

### Authentication

The current source uses an `xi-api-key` header on the WebSocket handshake. The official ElevenLabs docs require API key authentication for API requests, and the Swift adapter should preserve the same header-based handshake pattern. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L95), [ElevenLabs auth docs](https://elevenlabs.io/docs/api-reference/authentication)

### Swift implementation note

Use `URLRequest` for the connection so the API key header is explicit and testable, then create the task with `URLSession.webSocketTask(with:)`. Apple’s WebSocket task supports handshake authentication, async `send`, async `receive`, and delegate close/open lifecycle hooks.

## Audio Framing

### Normal audio chunk

The source sends JSON text frames, not binary frames:

```json
{
  "message_type": "input_audio_chunk",
  "audio_base_64": "<base64-PCM>",
  "sample_rate": 16000
}
```

The PCM bytes are base64-encoded before transmission. The source test suite verifies that a 3-byte buffer becomes `"AQID"` and that the `sample_rate` field matches the configured value. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L138), [Source tests](~/aiwork/coding-platform/untype/tests/elevenlabs-client.test.ts#L138)

### Commit message

Manual finalization uses the same message type with an empty audio payload and `commit: true`:

```json
{
  "message_type": "input_audio_chunk",
  "audio_base_64": "",
  "sample_rate": 16000,
  "commit": true
}
```

The source sends this commit frame both for explicit commit and as a best-effort final flush before shutdown. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L162), [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L184)

### Swift implementation note

In Swift, encode the payload as JSON and send it as a `.string` message. Apple documents that string WebSocket messages are UTF-8 encoded, which fits the ElevenLabs JSON contract.

## Commit and VAD Behavior

The source treats `enableEndpointDetection` as the switch between the two commit strategies:

- `true` -> `commit_strategy=vad`
- `false` -> `commit_strategy=manual`

On stop, the adapter:

- attempts a final `commit()`
- waits `COMMIT_DRAIN_MS = 250`
- closes with code `1000` and reason `"untype shutdown"`
- terminates the socket if close does not finish in time

This is the behavior to mirror if the Swift replacement is meant to be a drop-in behavioral match. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L162), [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L184)

## Event Shapes

### Received events handled by the source

The source recognizes these ElevenLabs message types:

- `session_started`
- `partial_transcript`
- `committed_transcript`
- `committed_transcript_with_timestamps`
- `error`

It ignores unknown events unless verbose logging is enabled. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L26), [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L273)

### Partial transcript behavior

`partial_transcript.text` is passed through unchanged when non-empty.

### Final transcript behavior

`committed_transcript.text` and `committed_transcript_with_timestamps.text` are trimmed before they are emitted as final text.

The source therefore treats timestamped and non-timestamped committed events as the same terminal transcript signal. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L294)

### Timestamped transcripts

The official docs state that committed transcripts can optionally include word-level timestamps when `include_timestamps=true`. The current source disables timestamps by default, so the Swift port should treat the timestamped event as supported but not required for the normal path.

## Error and Close Mapping

### Source-side mapping

The source maps failures into three error families:

- `ElevenLabsAuthError` for authentication failures
- `ElevenLabsNetworkError` for transport and unexpected close failures
- `ElevenLabsProtocolError` for malformed payloads and server protocol issues

Relevant source behavior:

- connection errors matching `401`, `403`, `auth`, `unauthorized`, `forbidden`, or `api key` become auth errors
- close code `1008` or auth-like close reasons become auth errors
- non-JSON inbound messages become protocol errors
- `error` events with `error_type=auth_error` become auth errors
- `quota_exceeded`, `rate_limited`, `resource_exhausted`, and `queue_overflow` become protocol errors

[Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L365), [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L378), [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L389)

### Swift implementation note

If you use `URLSessionWebSocketTask`, keep the WebSocket close code and reason available in your transport abstraction. The close callback in Apple’s delegate API exposes both, which makes it possible to preserve the source’s auth-vs-network split.

## Language and Sample-Rate Guidance

### Language handling

The source only sends `language_code` when the configured language list is not exactly `["auto"]`. In other words, `auto` is an application-level sentinel, not a WebSocket field. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L343)

The official ElevenLabs docs describe Scribe v2 Realtime as supporting 90+ languages, but the docs snippet set does not expose a strict realtime language-code allowlist. Treat the source’s `auto` convention as current behavior rather than a documented protocol guarantee.

### Sample-rate handling

The source passes the configured sample rate through both `audio_format=pcm_<sampleRate>` and `sample_rate=<sampleRate>`, and the existing tests cover `16000` and `24000`. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L332), [Source tests](~/aiwork/coding-platform/untype/tests/elevenlabs-client.test.ts#L103)

I did not find an official ElevenLabs realtime sample-rate allowlist in the current docs snippets. If you need strict validation, add it in the Swift layer explicitly and reject unsupported rates before opening the socket. Confidence: medium.

## Swift Implementation Guidance

### Recommended shape

Use a small transport layer plus a higher-level transcriber:

- `ElevenLabsRealtimeTranscriber`
- `WebSocketTransport` protocol
- `URLSessionWebSocketTransport` concrete implementation
- `MockWebSocketTransport` for tests

This mirrors the source design, which already isolates provider-specific transport logic behind a provider-neutral transcriber contract. [Source adapter](~/aiwork/coding-platform/untype/src/elevenlabs/client.ts#L4)

### Suggested structure

```swift
protocol WebSocketTransport: AnyObject {
    var onOpen: (() -> Void)? { get set }
    var onMessage: ((String) -> Void)? { get set }
    var onClose: ((_ code: URLSessionWebSocketTask.CloseCode, _ reason: Data?) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func connect() async throws
    func send(text: String) async throws
    func close(code: URLSessionWebSocketTask.CloseCode, reason: Data?) async
}

struct ElevenLabsInputAudioChunk: Encodable {
    let message_type = "input_audio_chunk"
    let audio_base_64: String
    let sample_rate: Int
    let commit: Bool?
}

final class ElevenLabsRealtimeTranscriber {
    private let transport: WebSocketTransport
    private let apiKey: String
    private let endpoint: URL
    private let modelID: String
    private let sampleRate: Int
    private let enableEndpointDetection: Bool
    private let languageCode: String?

    init(transport: WebSocketTransport, /* config omitted for brevity */) {
        self.transport = transport
        /* store config */
    }

    func start() async throws {
        try await transport.connect()
        // start receive loop after open
    }

    func pushAudio(_ pcm: Data) async throws {
        let payload = ElevenLabsInputAudioChunk(
            audio_base_64: pcm.base64EncodedString(),
            sample_rate: sampleRate,
            commit: nil
        )
        let data = try JSONEncoder().encode(payload)
        try await transport.send(text: String(decoding: data, as: UTF8.self))
    }

    func commit() async throws {
        let payload = ElevenLabsInputAudioChunk(
            audio_base_64: "",
            sample_rate: sampleRate,
            commit: true
        )
        let data = try JSONEncoder().encode(payload)
        try await transport.send(text: String(decoding: data, as: UTF8.self))
    }
}
```

### Implementation details worth preserving

- Build the request URL once and include all query items up front.
- Keep receive handling on a dedicated task so the socket is always drained.
- Trim final transcript text before emitting it.
- Treat a JSON parse failure as a protocol error, not a network error.
- On shutdown, attempt a final commit before closing.
- Keep auth, network, and protocol errors separate so the caller can display the correct recovery hint.

## Testability

The existing TypeScript tests show the behavioral surface that the Swift port should keep stable:

- URL and header construction
- manual versus VAD commit selection
- base64 audio chunk encoding
- partial and final transcript callbacks
- auth error mapping
- unexpected close mapping
- non-JSON payload mapping
- stop-time final commit emission

[Source tests](~/aiwork/coding-platform/untype/tests/elevenlabs-client.test.ts#L99)

### Swift test strategy

Prefer tests against the transport abstraction instead of `URLSessionWebSocketTask` directly:

- fake transport can simulate `open`, `message`, `close`, and transport failures
- transport fake can capture outgoing JSON for exact assertions
- keep one thin integration test for `URLSessionWebSocketTask` handshake construction if needed

This is the most practical way to make WebSocket behavior deterministic in XCTest or Swift Testing.

## Assumptions & Scope

- I assumed the Swift replacement should preserve the current source adapter’s behavior, not redesign the ElevenLabs contract. Confidence: high.
- I assumed the source’s `auto` language sentinel should remain an app-level convention in Swift. Confidence: high.
- I assumed `include_timestamps=false` should remain the default because that is what the current source sends. Confidence: high.
- I assumed the Swift port should use `URLSessionWebSocketTask` rather than a third-party WebSocket library because that is the native Apple transport requested by the scope. Confidence: high.
- I did not find an official realtime sample-rate allowlist in the current docs snippets. Confidence: medium.

## Uncertainties

- ElevenLabs’ current public docs snippets do not expose a strict realtime sample-rate allowlist, so exact supported PCM rates should be verified against a live session if you need to accept rates beyond the source’s tested `16000` and `24000`.
- The official docs snippets available here do not show the full error payload schema for every server error case, so the source-specific error mapping should be treated as the authoritative parity target.
- The docs snippets do not fully describe the `session_started` payload shape; the current source only logs the optional session ID and ignores the event for control flow.

## Clarifying Questions for Follow-up

1. Should the Swift replacement keep the source’s `include_timestamps=false` default, or should it expose timestamped committed transcripts as a first-class option?
2. Do you want strict validation for `sampleRate` and `languageCode`, or should Swift mirror the current source and allow the API to reject invalid combinations?
3. Should shutdown always send a final commit, even when the transport is already in a non-open state, or should that remain best effort only?

## References

### Source files

| # | Source | URL | Information gathered |
|---|---|---|---|
| 1 | `client.ts` | `~/aiwork/coding-platform/untype/src/elevenlabs/client.ts` | Exact query construction, header name, base64 audio framing, commit frame, transcript handling, and error/close mapping. |
| 2 | `elevenlabs-client.test.ts` | `~/aiwork/coding-platform/untype/tests/elevenlabs-client.test.ts` | Exact behavioral tests for URL shape, audio encoding, commit strategy, transcript events, auth mapping, network mapping, and shutdown commit. |

### Official docs

| # | Source | URL | Information gathered |
|---|---|---|---|
| 3 | ElevenLabs realtime STT API reference | https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime | Realtime STT is WebSocket-based and uses audio chunk messages and transcript events. |
| 4 | ElevenLabs transcripts and commit strategies | https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies | Committed transcripts can include word-level timestamps when `include_timestamps=true`. |
| 5 | ElevenLabs client-side streaming | https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/client-side-streaming | Realtime STT is Scribe Realtime v2 and returns partial transcripts as you speak. |
| 6 | ElevenLabs event reference | https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference | Event reference for messages sent to and received from the realtime API. |
| 7 | ElevenLabs authentication | https://elevenlabs.io/docs/api-reference/authentication | API requests must include an API key. |
| 8 | Apple `URLSessionWebSocketTask` | https://developer.apple.com/documentation/foundation/urlsessionwebsockettask | Native WebSocket transport, handshake support, async send/receive, and delegate hooks. |
| 9 | Apple `URLSessionWebSocketDelegate` | https://developer.apple.com/documentation/foundation/urlsessionwebsocketdelegate | Delegate receives open and close lifecycle callbacks, including close code and reason. |

### Recommended for deep reading

- `client.ts`: best source for exact parity behavior.
- `elevenlabs-client.test.ts`: best source for what must not regress.
- ElevenLabs realtime STT API reference: best source for the server’s documented transport model.
- Apple `URLSessionWebSocketTask`: best source for the Swift transport layer.
