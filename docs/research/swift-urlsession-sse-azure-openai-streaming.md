# Streaming LLM Responses in Swift via URLSession — SSE Mechanics + Azure OpenAI Chat Completions Streaming Wire Format

> Implementation-ready technical research for extending `URLSessionLLMHTTPClient` /
> `AzureOpenAIRefiner` (in `Sources/UntypeCore/LLMRefiners.swift`) from a single
> blocking request/response to a progressively-rendered token stream, while keeping a
> non-streaming code path.
>
> Depth: deep / implementation-ready. Target platform: macOS, Swift Package Manager,
> Swift concurrency (async/await). No investigation document — direct-dispatch task.

---

## Overview

The untype-s app today issues one POST to Azure OpenAI Chat Completions and waits for
the full JSON body before it can show anything (`URLSessionLLMHTTPClient.perform`
wraps `session.dataTask(with:completionHandler:)` in
`withCheckedThrowingContinuation`). To render tokens progressively we must:

1. Send the same request with `"stream": true`.
2. Read the HTTP response body **incrementally** as Server-Sent Events (SSE) instead
   of buffering it all.
3. Parse each `data: {…}` line into a chat-completion *chunk*, extract
   `choices[0].delta.content`, and accumulate it.
4. Surface accumulated/delta text to the UI as an `AsyncThrowingStream<String>`.
5. Stop at the `data: [DONE]` sentinel, and handle cancellation/timeouts/HTTP errors
   that no longer arrive as a single response.

There are two viable URLSession mechanisms for (2): the **pull-based**
`URLSession.bytes(for:)` → `URLSession.AsyncBytes` (recommended, native async/await),
and the **push-based** `URLSessionDataDelegate` `urlSession(_:dataTask:didReceive:)`.
Both are covered; the pull model is recommended for this codebase.

Key fact that drives the whole design: **Azure/OpenAI streams use the SSE framing
(`text/event-stream`, `data: ` prefix, blank-line separators, `data: [DONE]`
terminator).** Each `data:` payload is a *complete, self-contained JSON object* (one
chunk), so per-chunk JSON parsing is trivial — `JSONDecoder` on each line. The
*composite* path is the hard case: it streams a single `{refined_text, translated_text}`
JSON **object** spread across many chunks' `delta.content`, so the *concatenated*
content is a partial JSON document that cannot be parsed until complete. Focus area 5
covers extracting best-effort live text from that in-progress object.

---

## Key Concepts & Terminology

| Term | Meaning in this context |
|---|---|
| **SSE (Server-Sent Events)** | A one-way text streaming protocol over HTTP. `Content-Type: text/event-stream`. Events are newline-delimited; fields are `name: value`; an event ends at a blank line. OpenAI/Azure use only the `data:` field. |
| **Chunk** | One streamed `chat.completion.chunk` JSON object delivered in a single `data:` line. |
| **Delta** | The incremental payload inside a chunk: `choices[0].delta`. First chunk carries `role`; subsequent chunks carry `content` fragments; last carries `finish_reason`. |
| **`[DONE]` sentinel** | The literal line `data: [DONE]` that terminates an OpenAI/Azure stream. It is **not** JSON — must be special-cased before decoding. |
| **`AsyncBytes`** | `URLSession.AsyncBytes` — an `AsyncSequence<UInt8>` of the response body delivered as bytes arrive. Exposes `.lines` (an `AsyncSequence<String>` split on newlines) and `.characters`. |
| **`AsyncThrowingStream`** | A bridge to expose producer-driven values (here: accumulated text) to consumers via `for try await`, with a `continuation` you `yield()`/`finish()`/`finish(throwing:)`. |

---

## Focus Area 1 — Consuming a Streaming HTTP Response with URLSession

### 1A. The recommended approach: `URLSession.bytes(for:)` + `.lines`

`URLSession.bytes(for:delegate:)` (macOS 12+/iOS 15+) returns a tuple of
`(URLSession.AsyncBytes, URLResponse)`. The `URLResponse` is available **immediately
after the response headers arrive** — i.e. before the body streams — which is exactly
what we need to validate the HTTP status code *before* iterating the body. The bytes
are then consumed lazily with `for try await`.

```swift
let (bytes, response) = try await session.bytes(for: request)

guard let http = response as? HTTPURLResponse else {
    throw LLMRefinementError("LLM response was not an HTTP response", kind: .shape)
}
// Validate BEFORE consuming the body — see Focus Area 4.
guard (200..<300).contains(http.statusCode) else {
    // For non-2xx, Azure returns a normal JSON error body (not SSE). Drain it
    // for the message, then throw.
    var errorBody = Data()
    for try await byte in bytes { errorBody.append(byte) }
    throw mapHTTPError(status: http.statusCode, body: errorBody)
}

for try await line in bytes.lines {
    // each `line` is one SSE field line, e.g. "data: {…}" or "data: [DONE]"
    ...
}
```

**Why `.lines` is convenient and where it bites you.** `AsyncBytes.lines`
internally buffers raw bytes until it sees a newline, then yields the line **without
the trailing newline and without the blank separator lines** — `.lines` *skips empty
lines*. For OpenAI/Azure this is acceptable because each event is a single `data:`
line and the blank-line separator carries no information we need. But it means
**you cannot use `.lines` to detect SSE event boundaries** in the general case
(multi-line `data:` events, `event:`/`id:` fields). For OpenAI/Azure chat
completions, single-line `data:` events, `.lines` is the simplest correct choice.

> Pitfall: because `.lines` strips blank lines, do not rely on a blank line to flush a
> multi-line `data:` event. Azure chat-completion chunks are always one line, so this
> is fine here — but if you ever switch to an endpoint that sends multi-line `data:`
> payloads (e.g. the Responses API event stream with `event:` + `data:` pairs), switch
> to manual byte buffering (1C).

### 1B. The push alternative: `URLSessionDataDelegate`

The classic delegate route uses `urlSession(_:dataTask:didReceive:)`, which is called
repeatedly with `Data` slices as they arrive, plus
`urlSession(_:dataTask:didReceive:completionHandler:)` (response/headers) and
`urlSession(_:task:didCompleteWithError:)` (terminal). You accumulate bytes in a
buffer, split on `\n`, and emit completed lines yourself.

```swift
final class SSEDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    let onLine: (String) -> Void
    let onComplete: (Error?) -> Void
    let onResponse: (HTTPURLResponse) -> URLSession.ResponseDisposition

    func urlSession(_ s: URLSession, dataTask t: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            completionHandler(onResponse(http)) // .allow or .cancel on non-2xx
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ s: URLSession, dataTask t: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) { // '\n'
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                onLine(line.hasSuffix("\r") ? String(line.dropLast()) : line)
            }
        }
    }

    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete(error)
    }
}
```

### 1C. Trade-offs: pull (`AsyncBytes`) vs push (delegate)

| Aspect | `bytes(for:)` + `.lines` (pull) | `URLSessionDataDelegate` (push) |
|---|---|---|
| Concurrency model | Native async/await; lives inside one `Task` | Callback-based; you bridge to async yourself |
| Backpressure | Natural — you only pull the next line when ready | None; delegate pushes regardless; you must buffer |
| HTTP status before body | Yes — `URLResponse` returned up-front | Yes — via `didReceive response:` (must return disposition) |
| Cancellation | `task.cancel()` *or* cancelling the enclosing Swift `Task` (cooperative); iteration throws `URLError.cancelled` | `task.cancel()` only; no Task-cancellation link |
| Line splitting | Free via `.lines` (but skips blank lines) | Manual byte buffering, manual `\r\n` handling |
| Per-request config (timeout) | Set on `URLRequest.timeoutInterval` (caveat below) | Same |
| Fit with current codebase | Replaces the `withCheckedThrowingContinuation` wrapper with a streaming method | Requires a delegate object + a session created with a delegate |
| Sendable / isolation | Cleaner; no shared mutable buffer | Delegate holds mutable buffer — needs `@unchecked Sendable` + locking |

**Recommendation for untype-s: use `bytes(for:)` + `.lines`.** It maps cleanly onto the
existing async API surface (`perform` is already `async throws`), gives free
status-before-body validation, and ties cancellation to Swift structured concurrency.
The delegate approach is only preferable if you must support pre-macOS-12 (the project
targets modern macOS, so this is moot) or you need multi-line SSE events.

> One subtlety: `bytes(for:)` uses the session's **delegate** under the hood. If you
> create the session with a custom `URLSessionDataDelegate`, you cannot also use the
> `bytes(for:)` convenience with a *per-call* delegate that conflicts. The project's
> shared session is created with **no delegate**, so `bytes(for:)` works out of the
> box. Keep it that way.

### 1D. Wrapping the stream as `AsyncThrowingStream<String>`

The cleanest contract for the refiner/UI boundary is an
`AsyncThrowingStream<String>` that yields the **accumulated** text after each delta
(so the UI can replace its display verbatim), or the **delta** (so the UI appends).
Yielding accumulated text is simpler for the UI and avoids ordering bugs; yielding
deltas is cheaper. Recommendation: **yield accumulated text** for the simple refine
path, and yield accumulated *extracted field* text for the composite path (Focus
Area 5).

The current `LLMHTTPClient` protocol should gain a streaming sibling rather than
replacing `perform`, so the non-streaming path stays intact:

```swift
public protocol LLMHTTPClient: AnyObject {
    func perform(_ request: URLRequest, timeoutMs: Int) async throws -> LLMHTTPResponse
    // NEW — emits raw SSE `data:` payloads (already stripped of the "data: " prefix,
    // excluding the [DONE] sentinel which simply ends the stream).
    func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error>
    func cancelAll()
}
```

A reference implementation that builds the AsyncThrowingStream from `bytes(for:)`,
preserves the existing per-task cancellation tracking, and validates status before the
body:

```swift
public func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error> {
    var request = request
    request.timeoutInterval = TimeInterval(timeoutMs) / 1000.0

    return AsyncThrowingStream { continuation in
        let work = Task { [weak self] in
            guard let self else { return }
            do {
                let (bytes, response) = try await self.session.bytes(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw LLMRefinementError("LLM response was not an HTTP response", kind: .shape)
                }
                guard (200..<300).contains(http.statusCode) else {
                    var body = Data()
                    for try await b in bytes { body.append(b) }
                    let kind: LLMRefinementFailureKind =
                        [401, 403].contains(http.statusCode) ? .auth : .server
                    throw LLMRefinementError(
                        "LLM HTTP \(http.statusCode): \(truncate(body.utf8Text, max: 200))",
                        kind: kind
                    )
                }

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("data:") else { continue } // ignore comments/keepalives
                    let payload = trimmed.dropFirst("data:".count)
                        .trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    continuation.yield(payload) // one chat.completion.chunk JSON string
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        // Bridge AsyncThrowingStream termination -> URLSession task cancellation.
        continuation.onTermination = { @Sendable _ in
            work.cancel()
        }
    }
}
```

> Note: `bytes(for:)` returns a `URLSessionDataTask` internally that you don't get a
> handle to directly. Cancellation is therefore driven by **cancelling the enclosing
> Swift `Task`** (`work.cancel()`), which cooperatively cancels the underlying request
> and makes the `for try await` throw `URLError.cancelled`. See Focus Area 4 for how
> this interacts with the existing `cancelAll()` / `activeTasks` tracking.

---

## Focus Area 2 — Server-Sent Events Framing

The SSE wire format (per the WHATWG/MDN event-stream spec, which Azure references in
its API docs) on the bytes that arrive over the socket:

```
Content-Type: text/event-stream; charset=utf-8

data: {"id":"chatcmpl-…","choices":[{"delta":{"role":"assistant"},"index":0,"finish_reason":null}]}

data: {"id":"chatcmpl-…","choices":[{"delta":{"content":"Hel"},"index":0,"finish_reason":null}]}

data: {"id":"chatcmpl-…","choices":[{"delta":{"content":"lo"},"index":0,"finish_reason":null}]}

data: {"id":"chatcmpl-…","choices":[{"delta":{},"index":0,"finish_reason":"stop"}]}

data: [DONE]

```

Framing rules that matter:

1. **Field lines** look like `name: value`. OpenAI/Azure only ever send the `data`
   field for chat completions. A line beginning with `:` is a comment/keepalive and
   must be ignored.
2. **The `data: ` prefix** — there is conventionally a single space after the colon.
   Strip `data:` then trim leading whitespace; don't hard-code exactly one space.
3. **Blank line = event boundary.** A `\n\n` (or `\r\n\r\n`) separates events. With
   `.lines` these blank lines are skipped for you. With manual buffering, a blank line
   is the signal to dispatch the accumulated event.
4. **Multi-line data.** The spec allows multiple `data:` lines in one event, joined by
   `\n`. **OpenAI/Azure chat completions do not use this** — every chunk is a single
   `data:` line — so we can treat one `data:` line as one chunk. (If you ever migrate
   to the Responses API streaming events, that uses `event:` + `data:` pairs and you
   must handle multi-line/`event:` framing.)
5. **`data: [DONE]`** is the terminal sentinel and is **not JSON**. You must check for
   it *before* attempting `JSONDecoder.decode`, otherwise decoding throws on the last
   line. After `[DONE]`, finish the stream.
6. **Line endings.** Servers may send `\r\n`. Trim a trailing `\r`. `.lines` handles
   this; manual buffering must strip it.

---

## Focus Area 3 — Azure OpenAI Chat Completions Streaming, Specifically

### 3A. Request shape

Identical URL/auth to the current non-streaming call — only the body changes:

```
POST https://{endpoint}/openai/deployments/{deployment}/chat/completions?api-version={apiVersion}
api-key: {apiKey}
Content-Type: application/json
```

Body (additions over the current `makeRequest` in bold conceptually):

```json
{
  "messages": [
    {"role": "system", "content": "…systemPrompt…"},
    {"role": "user",   "content": "…text…"}
  ],
  "stream": true,
  "stream_options": {"include_usage": true},
  "max_completion_tokens": 4096,
  "reasoning_effort": "low",
  "temperature": 0.2
}
```

- **`"stream": true`** — required to switch the response to SSE. This is the only
  mandatory change to enable streaming.
- **`stream_options: {"include_usage": true}`** — *optional*. When set, Azure emits one
  extra chunk *before* `data: [DONE]` whose `choices` array is **empty** and whose
  `usage` object carries the final token counts (`prompt_tokens`, `completion_tokens`,
  `total_tokens`). All non-final chunks then carry `"usage": null`. **Only add it if
  the app wants token-usage telemetry** (e.g. to log in `release-latency.jsonl`). If
  you do, your chunk parser must tolerate a chunk with `choices == []` (no delta) — do
  not treat empty `choices` as an error. Supported on Azure since
  `2024-08-01-preview` / `2024-09-01-preview`; the GA line `2024-10-21` documents it
  too. Verify against the deployment's configured `apiVersion` before enabling.
- **`max_completion_tokens`** — already sent by the current code. Correct for both
  standard and reasoning deployments (reasoning models reject the old `max_tokens`).
- **`reasoning_effort`** — already sent. Valid values `low` / `medium` / `high` (and
  newer models add `minimal` / `none`). Only meaningful on reasoning-capable
  deployments.
- **`temperature`** — the current code already gates this: it is sent only when
  `reasoningEffort` is nil or `"none"`, because reasoning deployments **reject**
  sampling parameters (`temperature`, `top_p`, `presence_penalty`,
  `frequency_penalty`, `logprobs`, `logit_bias`, `max_tokens`). Keep that gating
  unchanged for the streaming path.

### 3B. The SSE delta JSON shape (per chunk)

Each `data:` payload is a `chat.completion.chunk`:

```json
{
  "id": "chatcmpl-Abc123",
  "object": "chat.completion.chunk",
  "created": 1736300000,
  "model": "gpt-4o-mini",
  "system_fingerprint": "fp_…",
  "choices": [
    {
      "index": 0,
      "delta": { "role": "assistant", "content": "" },
      "logprobs": null,
      "finish_reason": null
    }
  ],
  "usage": null
}
```

Chunk-by-chunk progression:

- **First content chunk** — `delta.role == "assistant"`, `delta.content` is `""` or the
  first fragment. Treat `role` as informational; the data you accumulate is
  `delta.content`.
- **Middle chunks** — `delta` contains only `content` (a short string fragment), no
  `role`. Accumulate `content`.
- **Final content chunk** — `delta` is `{}` (empty) and `finish_reason` is set
  (`"stop"`, `"length"`, `"content_filter"`, …). No new content. Use `finish_reason`
  to know the model finished cleanly: `"length"` means it was truncated by
  `max_completion_tokens`; `"content_filter"` means Azure's content filter cut it.
- **Usage chunk** (only if `include_usage`) — `choices: []`, `usage: { … }`. Read
  usage, then expect `data: [DONE]`.
- **`data: [DONE]`** — end.

Minimal `Codable` model for decoding each chunk:

```swift
struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let role: String?
            let content: String?
        }
        let delta: Delta
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
    let choices: [Choice]
    let usage: Usage?
}
```

Consuming the per-chunk JSON the `stream()` method yields:

```swift
let decoder = JSONDecoder()
var accumulated = ""
for try await payload in httpClient.stream(request, timeoutMs: timeout) {
    guard let chunk = try? decoder.decode(ChatCompletionChunk.self, from: Data(payload.utf8)) else {
        continue // tolerate the (rare) non-chunk line defensively
    }
    if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
        accumulated += delta
        // yield `accumulated` to the UI here
    }
    if let reason = chunk.choices.first?.finishReason {
        if reason == "length" { /* truncated — surface a soft warning */ }
        if reason == "content_filter" { /* filtered */ }
    }
    if let usage = chunk.usage { /* log token usage */ }
}
```

### 3C. Reasoning deployments + streaming

- Reasoning models (o1 / o3 / o4-mini / GPT-5 series on Azure) **support streaming**,
  but for **o3 specifically streaming has been gated as limited-access** on Azure for
  some subscriptions — verify the deployment can stream before relying on it; if it
  cannot, the request will fail and the code must fall back to the non-streaming path
  (which is why keeping `perform` is mandatory).
- Reasoning happens **before** any visible token; expect a **longer time-to-first-token
  (TTFT)** on reasoning deployments, after which content streams normally. The visible
  stream contains only the answer tokens — reasoning tokens are *not* streamed as
  content (they're counted in usage's `completion_tokens_details.reasoning_tokens`).
- Continue to gate out `temperature` and other sampling params for reasoning
  deployments exactly as the current `makeRequest` does.
- `max_completion_tokens` bounds *visible output + reasoning tokens combined*; a value
  too small can be entirely consumed by reasoning, producing an empty/`"length"`
  stream. Keep the configured budget generous for reasoning deployments.

### 3D. api-version

Pass the project's configured `apiVersion` query param unchanged. Constraints:

- Streaming (`stream: true`) works on all current chat-completions api-versions.
- `stream_options.include_usage` requires `2024-08-01-preview` /
  `2024-09-01-preview` or later, and is in the GA line from `2024-10-21`.
- If you adopt `include_usage`, treat a too-old `apiVersion` as a configuration error
  (no silent fallback — per project config rules) **or** simply omit `stream_options`
  when unsupported. Given the project's "no fallback for config" rule, the safest
  design is: only send `stream_options` when the operator explicitly opts in via
  config, and document the minimum api-version in the configuration guide.

---

## Focus Area 4 — Cancellation, Timeouts, Error Handling for Streaming

### 4A. Timeouts when there is no single response

`URLRequest.timeoutInterval` semantics: it is the **idle timeout between data packets**,
not a wall-clock deadline for the whole transfer. For a streaming response that is
*good* — as long as tokens keep arriving within the interval, the request stays alive,
which is what we want. The current code sets `request.timeoutInterval = timeoutMs/1000`
and that meaning carries over correctly to streaming: it now means "abort if no bytes
arrive for `timeoutMs`," i.e. a **stall timeout**.

If you also want an **overall wall-clock cap** (e.g. "the whole refinement must finish
in N seconds regardless"), `timeoutInterval` will not give it to you. Add a separate
timeout task that cancels the streaming `Task`:

```swift
let streamTask = Task { try await consumeStream() }
let timeoutTask = Task {
    try await Task.sleep(nanoseconds: UInt64(overallMs) * 1_000_000)
    streamTask.cancel()
}
defer { timeoutTask.cancel() }
let result = try await streamTask.value
```

(`URLSessionConfiguration.timeoutIntervalForResource` is the built-in overall cap, but
it is **per-session**; since untype-s uses a single process-wide shared session you
should NOT set it there — it would cap every request. Use the per-stream task above
instead.)

### 4B. Detecting mid-stream / pre-body HTTP errors

The big advantage of `bytes(for:)`: the `URLResponse` (status + headers) is returned
**before the body streams**. So a non-2xx (401 auth, 429 rate-limit, 5xx) is detected
*up front*, before any SSE parsing. On non-2xx, Azure returns a **regular JSON error
body** (`{"error": {...}}`) with `Content-Type: application/json`, **not** SSE — so
drain the bytes into `Data` and surface the message (see the `stream()` reference
implementation in 1D). Map `401/403 → .auth`, otherwise `→ .server`, matching the
existing `validateHTTP`.

A genuine *mid-stream* transport failure (connection dropped after 200 OK) surfaces as
the `for try await` loop **throwing** a `URLError` (e.g. `.networkConnectionLost`,
`.timedOut`). Catch it and route through the existing `mapTransportError`. Any text
already accumulated before the failure can optionally be delivered as a partial result
(decide per UX: discard vs. keep best-effort).

### 4C. Mapping `URLError.cancelled`

When the enclosing `Task` is cancelled (user starts a new push-to-talk session, or the
refiner is disposed), the underlying request is cancelled and the iteration throws
`URLError.cancelled`. The existing `mapTransportError` already maps both `.timedOut`
and `.cancelled` to `kind: .timeout`. **Reconsider that for streaming:** a
user-initiated cancel is *not* a timeout and usually should be swallowed silently
rather than surfaced as an error. Recommended:

```swift
} catch is CancellationError {
    return // user aborted; no error to surface
} catch let urlError as URLError where urlError.code == .cancelled {
    return // request cancelled; swallow
} catch {
    throw mapTransportError(error)
}
```

### 4D. Aborting an in-flight stream on a new push-to-talk session

This is the load-bearing requirement (per project guardrails: a new session must abort
the previous one cleanly). Two layers:

1. **Structured-concurrency layer.** Hold the streaming `Task` and cancel it when a new
   session starts. `continuation.onTermination` in the `stream()` builder already wires
   `work.cancel()`, so dropping/cancelling the consuming task tears down the URLSession
   request.
2. **Existing `cancelAll()` / `activeTasks` layer.** The current
   `URLSessionLLMHTTPClient` tracks `URLSessionDataTask`s in `activeTasks` and cancels
   them in `cancelAll()` / `dispose()`. The `bytes(for:)` API does **not** hand you the
   `URLSessionDataTask`, so streaming requests cannot be registered in `activeTasks`
   the same way. **Design choice:** track the streaming `Task`s instead. Add a parallel
   registry:

```swift
private var activeStreamTasks: [UUID: Task<Void, Never>] = [:]

// in stream(), register `work` under a UUID, deregister in onTermination,
// and have cancelAll() also cancel every activeStreamTask.
```

   This keeps the "cancel only this client's requests" guarantee that the shared
   session relies on, and ensures `dispose()` (already called from
   `AzureOpenAIRefiner.dispose()`) aborts an in-flight stream. The composite/refiner
   `dispose()` path therefore continues to work unchanged for callers.

> Push-to-talk guardrail tie-in: the new-session teardown that today calls
> `httpClient.cancelAll()` will now also cancel streaming tasks — verify the
> session-recycle path in `TranscriptionSessionRuntime` still calls the refiner's
> `dispose()` (which calls `cancelAll()`), so a new press cleanly aborts a previous
> stream before starting a new one.

---

## Focus Area 5 — Incremental JSON Extraction from an In-Progress Object

### The problem

The **composite** path streams a single JSON object —
`{"refined_text": "...", "translated_text": "..."}` — whose text is spread across many
`delta.content` fragments. Concatenating the deltas yields a **partial** JSON document
most of the time (e.g. `{"refined_text": "Hello wor`), which `JSONSerialization` /
`JSONDecoder` will reject. To show live text we must extract the *current value* of a
known string field (`refined_text`) from an incomplete object **without** full parsing,
then do a strict full parse once the stream completes (the existing
`LLMCompositeRefineTranslator.parseResponse` already handles the final strict parse via
`extractJSONObjectText` + `JSONSerialization`).

### Strategy: a tiny streaming string-value scanner

Run a small character state machine over the accumulated buffer each time it grows,
targeting a specific key. It tracks:

- whether we are inside a string,
- whether the previous char was a backslash (escape),
- which key's string we are currently reading,
- and emits the *decoded* partial value of the target key.

```swift
/// Best-effort: returns the current (possibly partial) string value of `key`
/// from an in-progress JSON object. Returns nil if the key/value hasn't started.
/// Handles \" \\ \/ \n \t \r \b \f and \uXXXX escapes. Tolerates a value that is
/// not yet closed (stream still arriving).
func partialStringValue(forKey key: String, in json: String) -> String? {
    let scalars = Array(json.unicodeScalars)
    var i = 0
    let n = scalars.count

    func skipWhitespace() { while i < n, scalars[i] == " " || scalars[i] == "\n"
        || scalars[i] == "\t" || scalars[i] == "\r" { i += 1 } }

    // Read a JSON string starting at the opening quote scalars[i] == '"'.
    // `allowUnterminated` lets us return what we have if the closing quote
    // hasn't streamed yet.
    func readString(allowUnterminated: Bool) -> String? {
        guard i < n, scalars[i] == "\"" else { return nil }
        i += 1
        var out = String.UnicodeScalarView()
        while i < n {
            let c = scalars[i]
            if c == "\\" {
                i += 1
                guard i < n else { return allowUnterminated ? String(out) : nil } // dangling backslash mid-stream
                let e = scalars[i]
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/":  out.append("/")
                case "n":  out.append("\n")
                case "t":  out.append("\t")
                case "r":  out.append("\r")
                case "b":  out.append("\u{08}")
                case "f":  out.append("\u{0C}")
                case "u":
                    // need 4 hex digits; if not all arrived yet, stop best-effort
                    guard i + 4 < n else { return allowUnterminated ? String(out) : nil }
                    let hex = String(String.UnicodeScalarView(scalars[(i+1)...(i+4)]))
                    if let v = UInt32(hex, radix: 16), let s = Unicode.Scalar(v) {
                        out.append(s)
                    }
                    i += 4
                default: out.append(e) // unknown escape: keep literal
                }
                i += 1
            } else if c == "\"" {
                return String(out) // closed
            } else {
                out.append(c); i += 1
            }
        }
        return allowUnterminated ? String(out) : nil // ran out of bytes mid-value
    }

    // Walk top-level object looking for "key":
    while i < n {
        if scalars[i] == "\"" {
            let start = i
            if let k = readString(allowUnterminated: false), k == key {
                skipWhitespace()
                guard i < n, scalars[i] == ":" else { continue }
                i += 1; skipWhitespace()
                return readString(allowUnterminated: true)
            } else {
                // not our key; if value was unterminated we're at end-of-buffer
                if i <= start { i += 1 }
            }
        } else {
            i += 1
        }
    }
    return nil
}
```

Usage in the composite streaming consumer (yield best-effort live `refined_text`):

```swift
var raw = ""
for try await payload in httpClient.stream(request, timeoutMs: timeout) {
    guard let chunk = try? decoder.decode(ChatCompletionChunk.self, from: Data(payload.utf8)),
          let frag = chunk.choices.first?.delta.content, !frag.isEmpty else { continue }
    raw += frag
    if let live = partialStringValue(forKey: "refined_text", in: raw) {
        // yield `live` to the UI as best-effort progressive text
    }
}
// Stream finished — do the STRICT parse with the existing, validated logic:
let result = try LLMCompositeRefineTranslator.parseResponse(raw)
```

### Pitfalls this technique must (and does) handle

1. **Escaped quotes (`\"`).** A naive "find the next `"`" terminates the value early
   when the content contains a quote. The scanner consumes `\"` as a literal quote and
   keeps going. *Critical for any natural-language text.*
2. **Escaped backslash (`\\`).** Must not be mistaken for an escape of the following
   char. The scanner emits one backslash and advances correctly.
3. **Unicode escapes (`\uXXXX`).** Decoded to the real scalar; if fewer than 4 hex
   digits have arrived yet, the scanner stops best-effort rather than mis-decoding.
   (Surrogate pairs `😀` for emoji: the simple version above decodes each
   half independently and may briefly show a lone surrogate; if emoji fidelity in the
   *partial* view matters, buffer a pending high surrogate and combine — otherwise the
   final strict parse fixes it.)
4. **Partial UTF-8 at chunk boundaries.** This is handled *upstream* by `.lines` /
   `String(data:encoding:.utf8)` operating on **complete lines** — each SSE `data:`
   line is a complete UTF-8 JSON string, so a multi-byte character is never split
   across the `delta.content` of two chunks at the *string* level. Therefore the
   scanner always runs on valid Swift `String`/`UnicodeScalar` data and never sees a
   half-encoded code point. **Do not run the scanner on raw `Data` byte slices** — run
   it on the assembled `String`, exactly as above, to keep this guarantee. (If you ever
   switch to the manual-delegate path that appends raw `Data`, decode to `String` only
   on complete lines, never on arbitrary byte boundaries.)
5. **Whitespace/formatting variance.** The model may emit `{ "refined_text" : "…"`
   with spaces/newlines; the scanner skips JSON whitespace around `:`.
6. **Key appearing inside a value.** Because the scanner only matches a key when it is a
   *string immediately followed by `:`* at object scan position, a literal
   `"refined_text"` occurring inside another value won't be mis-detected as the key in
   the common case. For maximal robustness, restrict matching to depth-1 (top-level)
   keys by tracking `{`/`}`/`[`/`]` nesting; for the flat
   `{refined_text, translated_text}` schema this is not strictly necessary but is cheap
   insurance.

> Always treat the scanner output as **display-only**. The authoritative result must
> come from the existing strict parse (`parseResponse`) after `[DONE]`. Never deliver
> the scanner's partial value as the final inserted text.

---

## Putting It Together: Recommended Integration Shape for untype-s

1. **Keep `perform` (non-streaming) intact.** Add `stream(_:timeoutMs:)` to
   `LLMHTTPClient` with a default no-op/throwing extension so other clients/tests
   compile, and implement it in `URLSessionLLMHTTPClient` via `bytes(for:)` (Focus
   Area 1D).
2. **Track streaming `Task`s** in a parallel registry so `cancelAll()` / `dispose()`
   abort in-flight streams (Focus Area 4D), preserving the shared-session
   "cancel only my tasks" guarantee.
3. **`AzureOpenAIRefiner`:** add `makeRequest(text:stream:)` that injects
   `"stream": true` (and optionally `stream_options`) while reusing the existing
   URL/auth/param-gating logic. Keep the temperature-vs-reasoning gating unchanged.
4. **Add a streaming refine method** that yields accumulated text via an
   `AsyncThrowingStream<String>`, decoding each chunk with the `ChatCompletionChunk`
   `Codable` (Focus Area 3B), special-casing the `include_usage` empty-`choices`
   chunk, stopping at `[DONE]`.
5. **Composite path:** accumulate raw concatenated `delta.content`, feed
   `partialStringValue(forKey: "refined_text", …)` for live display, and run the
   existing strict `parseResponse` once the stream completes (Focus Area 5).
6. **Error mapping:** validate status before the body; map `URLError.cancelled` /
   `CancellationError` to silent abort (not timeout); route mid-stream transport errors
   through `mapTransportError`; map non-2xx via the existing auth/server logic.
7. **Push-to-talk / focused-input guardrails:** new-session start must call the
   refiner's `dispose()` (→ `cancelAll()`) to abort any in-flight stream; the final,
   strictly-parsed result is what gets delivered to the focused input, so the
   focused-input delivery contract is unchanged (only the *display* updates
   progressively).

---

## Best Practices Checklist

- Use `bytes(for:)` + `.lines`; validate `HTTPURLResponse.statusCode` *before*
  iterating the body.
- Check for `data: [DONE]` *before* JSON-decoding; never decode the sentinel.
- Decode each `data:` line as one complete chunk; tolerate `choices == []`
  (usage chunk) and `delta == {}` (final chunk).
- Strip `data:` then trim whitespace; ignore lines starting with `:` (comments).
- Tie cancellation to Swift `Task` cancellation + `continuation.onTermination`; track
  streaming tasks for `cancelAll()`.
- Treat `URLRequest.timeoutInterval` as a *stall* timeout; add a separate task for any
  wall-clock cap; never set a session-wide resource timeout on the shared session.
- For the composite object, extract live text with an escape-aware scanner on the
  assembled `String`, and always finish with the existing strict parse.
- Keep the non-streaming `perform` path so reasoning deployments with restricted
  streaming (notably o3 limited-access) can fall back.

## Common Pitfalls

- **Decoding `[DONE]` as JSON** → decode error on the last line. Special-case it.
- **Relying on blank lines with `.lines`** → they are skipped; fine for single-line
  chat chunks, broken for multi-line SSE events.
- **Running the partial-JSON scanner on raw `Data`** → split multi-byte UTF-8 at chunk
  boundaries; always scan the assembled `String`.
- **Naive "next quote" value extraction** → terminates early on `\"` inside content.
- **Treating empty `choices` as an error** → breaks `include_usage`.
- **Setting `timeoutIntervalForResource` on the shared session** → caps every request
  process-wide.
- **Sending `temperature` to a reasoning deployment** → 400 error; keep existing
  gating.
- **Assuming all reasoning deployments stream** → o3 streaming is limited-access on
  Azure; keep the non-streaming fallback.
- **Mapping user-cancel to a timeout error** → surfaces a spurious error on every new
  push-to-talk press; swallow `cancelled`/`CancellationError`.

---

## Assumptions & Scope

- **Target platform is macOS 12+** (Monterey or later), so `URLSession.bytes(for:)`
  (macOS 12+/iOS 15+) is available. The project targets "modern macOS" per the brief;
  if a pre-12 target is ever required, only the delegate path (1B) works. **Confidence:
  HIGH** that bytes(for:) is available on the project's target.
- **Azure chat-completions chunks are single-line `data:` events** (no multi-line
  `data:`), so `.lines` is correct. **Confidence: HIGH** — consistent across OpenAI and
  Azure chat-completions docs.
- **The composite schema stays flat** (`{refined_text, translated_text}`, string
  values only). The partial-JSON scanner targets top-level string keys; nested objects
  would need depth tracking. **Confidence: HIGH** given the current
  `parseResponse` schema.
- **`include_usage` is treated as opt-in**, gated by api-version, per the project's
  no-config-fallback rule. **Confidence: MEDIUM** — exact minimum api-version
  (`2024-08-01-preview` vs `2024-09-01-preview`) varies slightly across Azure docs;
  verify against the deployment's configured api-version before enabling.
- **Out of scope:** tool/function-call streaming (`delta.tool_calls`), the newer
  Responses API event stream, n>1 choices, and audio streaming. The app sends a single
  text completion with one choice.

---

## References / Sources

1. [Azure OpenAI Service REST API reference (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference) — `stream`, `stream_options.include_usage`, endpoint pattern, `max_completion_tokens`, api-version, `data: [DONE]`.
2. [OpenAI API Reference — Chat Completions streaming events](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events) — exact chunk JSON shape, role on first chunk, `finish_reason`, usage chunk with empty `choices`, `[DONE]` sentinel.
3. [Retrieve token usage of stream-enabled chat completions in Azure OpenAI (Akihiro Nishikawa, Microsoft Azure / Medium)](https://logicojp.medium.com/retrieve-token-usage-of-stream-enabled-chat-completions-in-azure-openai-service-73eb6ad4cb02) — api-version requirements for `stream_options`, final usage chunk behavior.
4. [Use async/await with URLSession — WWDC21 session 10095 (Apple)](https://developer.apple.com/videos/play/wwdc2021/10095/) — `bytes(for:)`, `AsyncBytes`, response-before-body, cancellation via Task.
5. [URLSession.AsyncBytes — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/urlsession/asyncbytes) — `.lines` / `.characters`, AsyncSequence semantics.
6. [Streaming messages from ChatGPT using Swift AsyncSequence (Zach Waugh)](https://zachwaugh.com/posts/streaming-messages-chatgpt-swift-asyncsequence) — concrete `bytes.lines` SSE parsing pattern, `data:` prefix stripping, `[DONE]`, empty-line skipping by `.lines`.
7. [Azure OpenAI reasoning models — GPT-5 series, o3-mini, o1 (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning) — `max_completion_tokens`, `reasoning_effort`, unsupported sampling params, o3 streaming limited-access.
8. [MDN — Using server-sent events (event-stream format)](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events) — SSE framing: `data:` field, blank-line separators, multi-line data, comments.
9. [Usage stats now available when streaming — OpenAI Developer Community](https://community.openai.com/t/usage-stats-now-available-when-using-streaming-with-the-chat-completions-api-or-completions-api/738156) — `stream_options.include_usage` behavior, null usage on non-final chunks.

*Project file referenced:* `~/aiwork/coding-platform/untype-s/Sources/UntypeCore/LLMRefiners.swift`
(current `URLSessionLLMHTTPClient.perform`, `AzureOpenAIRefiner.makeRequest`,
`LLMCompositeRefineTranslator.parseResponse` / `extractJSONObjectText`).
