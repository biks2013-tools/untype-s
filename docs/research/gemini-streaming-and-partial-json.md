# Google Gemini Streaming (`streamGenerateContent`) — SSE Wire Format and Incremental Parsing in Swift

> Research topic: Google Gemini (`generativelanguage` `v1beta`) streaming responses — `streamGenerateContent` SSE wire format and incremental parsing in Swift.
> Depth: deep / implementation-ready.
> Output of a direct-dispatch technical-research task (no investigation document).
> Companion doc: a separate research file covers the **generic** `URLSession` SSE plumbing and the **Azure OpenAI** streaming format. This document keeps the generic SSE explanation brief and focuses on the **Gemini-specific** wire format, then provides a self-contained Gemini consumption example.

## Why this research is needed

The untype-s macOS app calls Gemini's `:generateContent` endpoint as a single blocking request and parses `candidates[0].content.parts[].text` from the full body. The implementation lives in `GoogleRefiner` in `Sources/UntypeCore/LLMRefiners.swift` (lines 287–424). We need to extend it to consume the streaming endpoint and render tokens progressively, while keeping the existing non-streaming path intact.

This document gives implementation-ready guidance for:

1. The `streamGenerateContent` method, default array mode vs. `?alt=sse` mode, and which to use.
2. The per-chunk JSON shape (text deltas, `finishReason`, `usageMetadata`, `promptFeedback`/safety blocks).
3. Consuming the stream from Swift via `URLSession.bytes(for:).lines`, producing an `AsyncThrowingStream<String>` of accumulated text.
4. Error handling and mapping to the app's `LLMRefinementFailureKind` (`auth`/`network`/`timeout`/`server`/`shape`).
5. Incremental ("best-effort") JSON extraction of `refined_text`/`translated_text` from an in-progress JSON object as Gemini streams deltas.

---

## 1. The `streamGenerateContent` method

### Endpoint, method, headers, query params

```
POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse&key={API_KEY}
Content-Type: application/json
```

- **Path:** identical to the non-streaming endpoint except the method name changes from `generateContent` to `streamGenerateContent`. In the current code (`GoogleRefiner.makeRequest`, line 338) the only change is `:generateContent` → `:streamGenerateContent`.
- **HTTP method:** `POST`.
- **Auth:** the same `key={API_KEY}` query parameter the non-streaming path already uses. (Gemini also accepts the `x-goog-api-key` header; the existing code uses the query param, keep that for consistency.)
- **Request body:** **byte-for-byte identical** to `generateContent` — `systemInstruction`, `contents`, `generationConfig`, optional `safetySettings`, `tools`, etc. No streaming-specific body fields exist. The current `makeRequest` body (lines 345–360) is reused unchanged.
- **Response content type:** `text/event-stream` when `alt=sse` is set; `application/json` (a streamed JSON array) when it is not.

> Note: `curl` should pass `--no-buffer` to see chunks live; that flag has no Swift analogue — `URLSession.bytes` is already unbuffered at the API level.

### Two streaming modes — and which to use

`streamGenerateContent` has two wire formats selected by the `alt` query parameter:

#### Mode A — default (no `alt`): a streamed JSON **array**

Without `alt=sse`, the response is a single JSON **array** of `GenerateContentResponse` objects that is *flushed incrementally* as the array is built:

```
[{
  "candidates": [ { "content": { "parts": [ { "text": "Recursion " } ], "role": "model" } } ]
}
,
{
  "candidates": [ { "content": { "parts": [ { "text": "is a technique" } ], "role": "model" } } ]
}
]
```

The bytes arrive progressively, but the framing is "one big JSON array": the first byte is `[`, objects are separated by `,`, and the stream ends with `]`. To consume it incrementally you must run a **streaming JSON parser** that tracks brace/bracket depth and emits each top-level array element as it completes. This is brittle to hand-roll (you must count braces while respecting strings and escapes) and offers no advantage for our use case.

#### Mode B — `?alt=sse`: Server-Sent Events

With `alt=sse`, each chunk is delivered as a standard SSE event:

```
data: {"candidates":[{"content":{"parts":[{"text":"Recursion "}],"role":"model"}}],"usageMetadata":{...},"modelVersion":"gemini-2.5-flash"}

data: {"candidates":[{"content":{"parts":[{"text":"is a programming technique where a function calls itself."}],"role":"model"}}]}

data: {"candidates":[{"content":{"parts":[{"text":""}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":34,"totalTokenCount":46},"modelVersion":"gemini-2.5-flash","responseId":"abc123"}

```

Each event is a line that begins with `data: ` followed by **one complete, self-contained `GenerateContentResponse` JSON object**. Events are separated by a blank line. Gemini does **not** emit `event:`, `id:`, or `retry:` SSE fields, and does **not** send a `data: [DONE]` sentinel (unlike OpenAI/Azure). The stream simply ends (EOF) after the final chunk.

### Recommendation: use `?alt=sse`

**Use `?alt=sse`.** It is dramatically easier to consume incrementally from Swift:

- Each `data:` line contains **one fully-formed JSON object** that `JSONSerialization`/`JSONDecoder` can parse on its own — no streaming JSON parser, no brace counting.
- It maps directly onto `URLSession.bytes(for:).lines`: iterate lines, strip the `data: ` prefix, decode, accumulate.
- It is the same framing model the app's companion Azure SSE work uses, so the SSE plumbing layer can be shared.

The only Gemini-specific quirks vs. Azure are: (a) no `[DONE]` sentinel — the stream ends at EOF; (b) the JSON payload shape is `candidates[].content.parts[].text` rather than `choices[].delta.content`. Everything else (line iteration, `data: ` stripping, blank-line separation) is identical.

---

## 2. Per-chunk response JSON shape (SSE mode)

Each `data:` payload is a `GenerateContentResponse`. The fields relevant to text rendering:

```jsonc
{
  "candidates": [
    {
      "content": {
        "parts": [ { "text": "…delta text…" } ],
        "role": "model"
      },
      "finishReason": "STOP",        // present only on the final chunk (usually)
      "index": 0,
      "safetyRatings": [ { "category": "...", "probability": "NEGLIGIBLE" } ]
    }
  ],
  "promptFeedback": { ... },          // may appear (usually first chunk) if prompt was filtered
  "usageMetadata": { ... },           // token counts; appears on the final chunk (sometimes also first)
  "modelVersion": "gemini-2.5-flash",
  "responseId": "..."
}
```

### How text is split across chunks

- The full reply = **concatenation of `candidates[0].content.parts[].text` across all chunks, in order**. Joining with empty string (`""`) — exactly what the current non-streaming `parseContent` does at line 414 — is the correct accumulation rule; the only difference is you now do it across chunks instead of within one body.
- Splits are arbitrary token/segment boundaries. A chunk may contain a single token, several words, or (rarely) an empty string. Do **not** insert spaces or newlines between chunks — text already carries its own whitespace.
- A single chunk can contain **multiple parts** (e.g., when thinking/`thought` parts or multiple text parts are present). For plain text refinement, joining all `parts[].text` per chunk and then across chunks is safe. If "thinking" models are ever used, a `part` may carry `"thought": true` — filter those out if you want only the answer text. (Not a concern for the current refiner models, but worth a guard.)
- The **final chunk frequently has an empty `parts[].text`** (or no `content` at all) and carries `finishReason` + `usageMetadata`. Treat empty text as normal, not an error.

### `finishReason`

Present on the terminal chunk for each candidate. Possible values (from the `v1beta` enum):

| Value | Meaning | App handling |
|---|---|---|
| `STOP` | Natural completion. | Success. |
| `MAX_TOKENS` | Hit `maxOutputTokens`. | Output may be truncated. For the composite JSON path this can yield invalid/partial JSON — treat as `shape` if the accumulated JSON cannot be parsed, otherwise accept truncated text. |
| `SAFETY` | Blocked by safety filter; check `safetyRatings`. | `server`/`shape` — usually empty/partial text. Surface a clear message. |
| `RECITATION` | Too close to training data. | Same as `SAFETY`. |
| `LANGUAGE` | Unsupported language attempted. | Same as `SAFETY`. |
| `BLOCKLIST`, `PROHIBITED_CONTENT`, `SPII` | Content-policy blocks. | Same as `SAFETY`. |
| `MALFORMED_FUNCTION_CALL` | Function-call format error. | Not applicable (no tools used). |
| `OTHER` | Unspecified stop. | Treat as a soft failure if no text was produced. |
| `FINISH_REASON_UNSPECIFIED` | Default/unset. | Ignore. |

> Known quirk: some Gemini 2.5 models have historically **omitted** `finishReason` when hitting the token limit, or returned `MAX_TOKENS` with empty text. Do not *require* a `finishReason` to consider the stream complete — completion is signalled by **EOF** of the byte stream. Use `finishReason` only to classify *why* it ended and to detect safety blocks.

### `usageMetadata`

Appears on (at least) the final chunk:

```jsonc
"usageMetadata": {
  "promptTokenCount": 12,
  "candidatesTokenCount": 34,
  "totalTokenCount": 46
}
```

Optional for the app; capture it only if you want token telemetry. It is not required to detect completion.

### `promptFeedback` / mid-stream safety blocks

Two distinct safety-block shapes can appear:

1. **Prompt-level block** — the *input* was rejected. The response contains `promptFeedback.blockReason` and **no usable candidate text**. This usually arrives in the **first** chunk (or as the only chunk). `blockReason` values: `BLOCK_REASON_UNSPECIFIED`, `SAFETY`, `OTHER`, `BLOCKLIST`, `PROHIBITED_CONTENT`, `IMAGE_SAFETY`.

   ```jsonc
   { "promptFeedback": { "blockReason": "SAFETY", "safetyRatings": [ ... ] } }
   ```

2. **Candidate-level block mid-stream** — generation starts, then a later chunk carries `candidates[0].finishReason = "SAFETY"` (or `RECITATION`/`BLOCKLIST`/…) with empty trailing text. Any text already streamed before the block remains valid but the answer is incomplete.

Also possible: a chunk where `candidates` is **empty or absent** entirely (e.g., a chunk carrying only `usageMetadata`/`promptFeedback`). Your per-chunk decoder must tolerate a missing `candidates` array and missing `content`/`parts` — skip such chunks rather than throwing.

**Detection rule for the app:** if, at EOF, **no text was ever accumulated**, inspect the last seen `finishReason`/`blockReason` to produce a meaningful error instead of a generic empty-output failure.

---

## 3. Consuming the stream from Swift

### SSE plumbing (brief — see companion doc for the generic mechanics)

`URLSession.bytes(for:)` returns `(URLSession.AsyncBytes, URLResponse)`. `AsyncBytes` has a `.lines` async sequence that yields one `String` per line. For Gemini SSE you:

1. `await session.bytes(for: request)` → get the `URLResponse` first (this is where you check the HTTP status **before** consuming the body — see §4).
2. `for try await line in bytes.lines { … }`.
3. Skip blank lines and any line that does not start with `data:`.
4. Strip the `data: ` prefix (note the single space; be defensive and also accept `data:` with no space).
5. Decode the remaining substring as a `GenerateContentResponse` JSON object.
6. Accumulate `candidates[0].content.parts[].text`.

`.lines` handles UTF-8 decoding and line-boundary buffering for you, so **partial UTF-8 at network-chunk boundaries is not a concern at the SSE-line level** — a line is only yielded once a full newline-terminated, validly-decoded line is available. (Partial UTF-8 *does* matter for the §5 partial-JSON extraction, which operates on accumulated text, not raw bytes.)

### Self-contained Gemini consumption example

This produces an `AsyncThrowingStream<String>` that yields the **accumulated** text after each chunk (each element is the full text so far, so the UI can simply replace its buffer). If you prefer deltas, yield `delta` instead of `accumulated`.

```swift
import Foundation

/// Minimal per-chunk shape. Everything is optional so safety-only / usage-only
/// chunks decode without throwing.
private struct GeminiStreamChunk: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
                let thought: Bool?
            }
            let parts: [Part]?
        }
        let content: Content?
        let finishReason: String?
    }
    struct PromptFeedback: Decodable {
        let blockReason: String?
    }
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}

enum GeminiStreamError: Error {
    case http(status: Int, body: String)
    case promptBlocked(reason: String)
    case candidateBlocked(finishReason: String)
    case emptyOutput
    case notHTTP
}

/// Streams accumulated refined text from Gemini's SSE endpoint.
/// Each yielded value is the full text accumulated so far.
func geminiStreamedText(
    request: URLRequest,
    session: URLSession
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let (bytes, response) = try await session.bytes(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw GeminiStreamError.notHTTP
                }
                // Non-2xx: the body is a JSON error object, not SSE. Drain it.
                guard (200..<300).contains(http.statusCode) else {
                    var errorBody = Data()
                    for try await byte in bytes { errorBody.append(byte) }
                    throw GeminiStreamError.http(
                        status: http.statusCode,
                        body: String(decoding: errorBody, as: UTF8.self)
                    )
                }

                var accumulated = ""
                var sawAnyText = false
                var lastFinishReason: String?
                let decoder = JSONDecoder()

                for try await line in bytes.lines {
                    try Task.checkCancellation()

                    // Gemini SSE: only `data:` lines matter; no event:/id:/[DONE].
                    guard line.hasPrefix("data:") else { continue }
                    let jsonText = line
                        .dropFirst("data:".count)
                        .drop(while: { $0 == " " })           // tolerate "data:" or "data: "
                    if jsonText.isEmpty { continue }

                    let chunk: GeminiStreamChunk
                    do {
                        chunk = try decoder.decode(
                            GeminiStreamChunk.self,
                            from: Data(jsonText.utf8)
                        )
                    } catch {
                        // A malformed/partial SSE line is unexpected (each data:
                        // line is a complete object). Skip rather than abort.
                        continue
                    }

                    if let reason = chunk.promptFeedback?.blockReason {
                        throw GeminiStreamError.promptBlocked(reason: reason)
                    }

                    guard let candidate = chunk.candidates?.first else {
                        // usage-only / metadata-only chunk — nothing to render.
                        continue
                    }

                    if let parts = candidate.content?.parts {
                        for part in parts where part.thought != true {
                            if let text = part.text, !text.isEmpty {
                                accumulated += text
                                sawAnyText = true
                                continuation.yield(accumulated)
                            }
                        }
                    }

                    if let reason = candidate.finishReason {
                        lastFinishReason = reason
                    }
                }

                // EOF reached — classify the result.
                if !sawAnyText {
                    if let reason = lastFinishReason, reason != "STOP" {
                        throw GeminiStreamError.candidateBlocked(finishReason: reason)
                    }
                    throw GeminiStreamError.emptyOutput
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                continuation.finish(throwing: error)
            }
        }
        // Cancelling the stream (e.g. new push-to-talk session) aborts the task,
        // which cancels the underlying URLSession byte stream.
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

Key points:

- **HTTP status is checked from the `URLResponse` returned by `bytes(for:)` before consuming the body**, so auth/quota errors are caught at stream start (§4).
- Each `data:` line decodes independently — no streaming JSON parser.
- Empty-text and metadata-only chunks are tolerated.
- `continuation.onTermination` → `task.cancel()` gives you clean abort-on-new-session.

---

## 4. Error handling and mapping to `LLMRefinementFailureKind`

The app's failure taxonomy (`Sources/UntypeCore/LLMRefiners.swift`, lines 3–9): `auth`, `network`, `timeout`, `server`, `shape`.

### 4.1 Non-2xx before/at stream start

For a streaming request the HTTP status is available from the `URLResponse` **before** any SSE bytes are consumed (the `(bytes, response)` tuple). When non-2xx:

- The body is **not** SSE — it is a single Gemini error JSON object. Drain `bytes` into `Data` and surface it.
- Map status → kind exactly as the existing `validateHTTP` does (lines 382–390):

  | Status | `LLMRefinementFailureKind` |
  |---|---|
  | 401, 403 | `auth` |
  | 429 | `server` (rate-limit/quota; could add a dedicated mapping later) |
  | 400 | `shape` if it's a request-shape error (`INVALID_ARGUMENT`), else `server` |
  | 5xx | `server` |

  To stay consistent with the current code, keep the simple rule: `[401,403] → auth`, everything else non-2xx → `server`. Refine later if needed.

### 4.2 Gemini error JSON shape

Standard Google API error envelope:

```jsonc
{
  "error": {
    "code": 400,
    "message": "API key not valid. Please pass a valid API key.",
    "status": "INVALID_ARGUMENT",
    "details": [ { "@type": "...", "reason": "API_KEY_INVALID" } ]
  }
}
```

Useful `status` values you may encounter: `INVALID_ARGUMENT` (400), `UNAUTHENTICATED`/`PERMISSION_DENIED` (401/403, often `API_KEY_INVALID`), `RESOURCE_EXHAUSTED` (429 quota), `INTERNAL`/`UNAVAILABLE` (5xx). Extract `error.message` for the user-facing string (truncate as the current code does at 200 chars), and optionally `error.status` for finer mapping.

### 4.3 Mid-stream safety blocks / empty candidates

- **Prompt block:** `promptFeedback.blockReason` present, no text → throw with `kind: .server` (or a dedicated message); the *request content* was rejected, not a transport problem.
- **Candidate block mid-stream:** terminal chunk `finishReason ∈ {SAFETY, RECITATION, BLOCKLIST, PROHIBITED_CONTENT, SPII, LANGUAGE}` with no usable text → `server`/`shape` depending on whether partial text exists.
- **Empty output at EOF** (no text ever accumulated, `finishReason = STOP` or absent) → `kind: .shape` ("did not contain non-empty candidates[0].content.parts[].text"), matching the existing non-streaming message (line 417).
- **Truncation (`MAX_TOKENS`)** for the composite JSON path → if the accumulated buffer does not parse as JSON, `kind: .shape`; if it does, accept it.

### 4.4 Timeouts and cancellation (abort on new push-to-talk session)

- **Timeout:** `URLRequest.timeoutInterval` covers *time to first byte/response*, not the whole stream. For a long stream also consider `URLSessionConfiguration.timeoutIntervalForResource` if a hard overall cap is desired. A `URLError.timedOut` thrown from `bytes(for:)` or during iteration maps to `kind: .timeout` (reuse `mapTransportError`, lines 612–624).
- **Cancellation:** the streaming refiner must abort the in-flight stream when a new session starts (the current `dispose()` calls `httpClient.cancelAll()`, lines 327–333). Two complementary mechanisms:
  1. **Swift-task cancellation:** hold the `Task` driving the `AsyncThrowingStream`; cancelling it (`task.cancel()`) makes `bytes.lines` iteration throw `CancellationError`, and `try Task.checkCancellation()` inside the loop short-circuits promptly.
  2. **URLSession-task cancellation:** if you keep the underlying `URLSessionTask` (as the existing `URLSessionLLMHTTPClient` does via `activeTasks`), `cancel()` aborts the connection and surfaces `URLError.cancelled`.
- **Map both** `URLError.cancelled` and `CancellationError` to `kind: .timeout` (the existing `mapTransportError` already maps `.cancelled` → `.timeout`, lines 614–616). Since a deliberate user-driven abort is expected and benign, you may also choose to swallow `CancellationError` silently rather than surfacing it as an error — decide at the call site.

> Implementation note for the app's architecture: `LLMHTTPClient.perform` returns a buffered `LLMHTTPResponse`, which cannot stream. Add a **separate** streaming method (e.g. `func stream(_ request:) -> AsyncThrowingStream<String, Error>` or a lower-level `bytes(for:)` wrapper) to the client protocol, keeping `perform` for the non-streaming path. The shared `URLSession` (lines 79–85) is fine for streaming; register the streaming task in `activeTasks` so `cancelAll()` aborts it too.

---

## 5. Incremental JSON extraction for the composite path

The composite refine-translate path asks the model to return a single JSON object `{ "refined_text": "...", "translated_text": "..." }` (`LLMCompositeRefineTranslator`, lines 426–522). With streaming, this JSON arrives **character by character**, so to render progressively you must extract the two string values from an **in-progress, possibly-unterminated** JSON object.

> The companion Azure/SSE research doc covers this generic technique; this section summarizes it and notes the Gemini-specific accumulation source (the §3 accumulated buffer).

### The problem

At any mid-stream point the accumulated text might be:

```
{ "refined_text": "Hello, wor
```

`JSONSerialization` will reject this. You need a tolerant scanner that pulls the current (partial) value of a named key.

### Technique: tolerant key-scoped string scan

For each target key (`refined_text`, `translated_text`):

1. Find the key token (`"refined_text"`) in the accumulated buffer. If absent yet, the value is "not started" → emit empty.
2. Skip whitespace and the `:` after the key.
3. Expect the opening `"` of the string value. If not present yet, value not started.
4. Scan characters until an **unescaped** closing `"` or end-of-buffer:
   - Track an `escaped` flag: when you see `\` and not already escaped, set `escaped = true` and continue.
   - When `escaped` is true, interpret the next char as an escape:
     - Simple escapes `\" \\ \/ \b \f \n \r \t` → append the literal char.
     - `\uXXXX` → you need 4 hex digits. **If fewer than 4 are present yet (chunk boundary mid-escape), stop scanning and emit what you have so far without the incomplete escape** — do not append a broken character. On the next chunk the full `\uXXXX` will be available.
   - An unescaped `"` ends the value → you have the complete string.
   - End-of-buffer before the closing `"` → the value is partial; return the decoded-so-far text (this is the live preview).

This yields a best-effort current value for each key that is safe to display and converges to the final value once the closing quote arrives.

### Edge cases (must-handle)

- **Escaped quotes** `\"` inside the value: handled by the `escaped` flag — a `\"` does not terminate the string.
- **Unicode escapes** `\uXXXX`: decode complete ones; **defer** incomplete ones at the buffer tail (do not emit a half-escape).
- **Partial UTF-8 at chunk boundaries:** *not a problem here* — the §3 consumer accumulates **`String`** (already valid UTF-8, because `bytes.lines` only yields fully-decoded lines). The partial-JSON scanner therefore operates on `Character`s, never on raw bytes, so a multi-byte codepoint is never split. (If you ever scan raw `Data` instead, you must buffer trailing bytes that don't form a complete UTF-8 scalar — but the line-based pipeline avoids this entirely.)
- **Key appears inside another string value:** a naive substring search for `"refined_text"` could match text that happens to contain that literal. For the controlled prompt (model is instructed to return exactly these top-level keys) this is low-risk; for robustness, only accept the key match when it is at object/structural position (preceded by `{` or `,` and followed by `:`). For the first cut, a plain search is acceptable given the constrained prompt.

### Final parse

When the stream completes, run the **existing** strict parser unchanged: `LLMCompositeRefineTranslator.parseResponse` (lines 453–486), which calls `extractJSONObjectText` (lines 508–521) to trim to the `{…}` span and then `JSONSerialization`. The incremental scanner is **only** for the live preview; the authoritative result still comes from the strict final parse, preserving current validation (non-empty, both keys present).

### Sketch (live-preview extraction of one key)

```swift
/// Best-effort current value of a top-level JSON string key from an in-progress
/// object. Returns the decoded-so-far value (may be partial). Safe to call on
/// every accumulated-text update.
func partialJSONStringValue(forKey key: String, in buffer: String) -> String? {
    guard let keyRange = buffer.range(of: "\"\(key)\"") else { return nil }
    var i = keyRange.upperBound
    let end = buffer.endIndex

    // skip whitespace, ':', whitespace
    func skipWS() { while i < end, buffer[i].isWhitespace { i = buffer.index(after: i) } }
    skipWS()
    guard i < end, buffer[i] == ":" else { return nil }
    i = buffer.index(after: i); skipWS()
    guard i < end, buffer[i] == "\"" else { return nil } // value not started yet
    i = buffer.index(after: i)

    var out = ""
    while i < end {
        let c = buffer[i]
        if c == "\\" {
            let next = buffer.index(after: i)
            guard next < end else { break }            // escape split across chunks -> stop
            let e = buffer[next]
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
                // need exactly 4 hex digits after \u
                let hexStart = buffer.index(after: next)
                guard let hexEnd = buffer.index(hexStart, offsetBy: 4, limitedBy: end),
                      hexEnd <= end,
                      let scalarValue = UInt32(buffer[hexStart..<hexEnd], radix: 16),
                      let scalar = Unicode.Scalar(scalarValue) else {
                    return out                          // incomplete \uXXXX -> emit so far
                }
                out.unicodeScalars.append(scalar)
                i = hexEnd                              // advance past the 4 hex digits
                continue
            default:
                out.append(e)
            }
            i = buffer.index(after: next)
            continue
        }
        if c == "\"" { return out }                     // closing quote -> complete value
        out.append(c)
        i = buffer.index(after: i)
    }
    return out                                          // buffer ended -> partial value
}
```

(Note: surrogate-pair `\uD800`-`\uDFFF` handling is omitted for brevity; the strict final parser handles those correctly, and mid-stream a lone high surrogate is simply deferred by the "incomplete \uXXXX" branch on the *second* `\u`. For the constrained refine/translate text this is rarely exercised.)

---

## Assumptions & Scope

| Assumption | Confidence | Impact if wrong |
|---|---|---|
| `?alt=sse` is the right mode for incremental Swift consumption (vs. default array mode). | HIGH | If the team prefers the array mode, the §3 consumer must be replaced by a streaming JSON-array parser; the rest (shapes, errors) is unchanged. |
| Request body for `streamGenerateContent` is identical to `generateContent`. | HIGH | If a streaming-only body field were required (none documented), `makeRequest` would need a branch. |
| Text accumulation = empty-string join of `parts[].text` across chunks (same as current non-streaming join, line 414). | HIGH | If a model emits structured/multi-part output, naive join could interleave; the `thought` filter mitigates the known case. |
| Completion is signalled by EOF, not by a `finishReason` or a `[DONE]` sentinel. | HIGH | Gemini sends no `[DONE]`; relying on `finishReason` presence would hang on the known MAX_TOKENS-without-reason quirk. |
| `bytes.lines` yields only fully-decoded UTF-8 lines, so partial UTF-8 is a non-issue at the SSE layer. | HIGH | If a future code path scans raw `Data`, byte-level UTF-8 buffering must be added. |
| Auth via `key=` query param (matching current code) is retained; header auth not required. | HIGH | If switched to `x-goog-api-key`, only `makeRequest` changes. |
| `LLMHTTPClient` will gain a separate streaming method rather than overloading `perform`. | MEDIUM | An architectural choice for the implementer; this doc only recommends it. The non-streaming path must remain (per the request). |
| Mapping 429 → `server` (not a new kind). | MEDIUM | If quota deserves its own UX, a new `LLMRefinementFailureKind` case (or sub-classification) may be wanted; out of scope here. |

### Out of scope

- The generic `URLSession` SSE mechanics and the Azure OpenAI `choices[].delta.content` format (covered by the companion research doc).
- Function calling / tools, multimodal (image/audio) parts, thinking-budget configuration.
- Vertex AI's `:streamGenerateContent` (different host/auth — OAuth, `aiplatform.googleapis.com`); this doc targets the `generativelanguage.googleapis.com` AI-Studio API the app already uses.
- The actual `GoogleRefiner` code change (this is research, not implementation).

### Uncertainties & gaps

- **Exact `usageMetadata` placement** (first chunk vs. final chunk vs. both) varies by model/version; the app should not depend on it for control flow — treat it as optional telemetry only.
- **Whether `promptFeedback` ever appears with non-empty candidate text** in the same stream: documented as prompt-level feedback that typically precedes/blocks generation; treat its `blockReason` as authoritative for a prompt block, but still accept any candidate text that does arrive.
- **`MAX_TOKENS`-without-`finishReason` quirk** is model/version-dependent and was reported against Gemini 2.5; verify against the specific model the app pins. The EOF-based completion rule is robust to it regardless.

### Clarifying questions for follow-up

1. Should the streaming path replace the blocking path for the default flow, or be opt-in (config flag) while the blocking path stays the fallback?
2. For the composite JSON path, is a live preview of `refined_text`/`translated_text` actually rendered to the user (justifying §5's partial extraction), or is streaming only used to reduce time-to-first-render with a final strict parse?
3. Does the app want token-usage telemetry from `usageMetadata`, or can it be ignored?
4. Should rate-limit (429 / `RESOURCE_EXHAUSTED`) get its own `LLMRefinementFailureKind` for distinct UX, or is `server` sufficient?
5. Is a hard overall-stream timeout cap desired (`timeoutIntervalForResource`) in addition to the time-to-first-byte timeout?

---

## References

| # | Source | URL | Information gathered |
|---|---|---|---|
| 1 | Gemini API — Generating content (official) | https://ai.google.dev/api/generate-content | `streamGenerateContent` endpoint, method, `alt=sse`, request body identity, chunk shape (`candidates`/`content`/`parts`/`text`, `finishReason`, `usageMetadata`, `promptFeedback`), text-split-across-chunks behavior. |
| 2 | Gemini API reference (Context7: `/websites/ai_google_dev_api`) | https://ai.google.dev/api | SSE framing, per-chunk `GenerateContentResponse` example, `GenerateContentResponse` field list (`candidates`, `promptFeedback`, `usageMetadata`, `modelVersion`, `responseId`). |
| 3 | Gemini cookbook — Streaming Quickstart (REST) | https://github.com/google-gemini/cookbook/blob/main/quickstarts/rest/Streaming_REST.ipynb | Exact `curl` with `?alt=sse&key=`, `--no-buffer`, confirmation that each SSE chunk is a `GenerateContentResponse` with `candidates[0].content.parts[0].text`. |
| 4 | Gemini API — `finishReason` enum (search synthesis + DeepWiki/forum) | https://deepwiki.com/google-gemini-php/client/10.5-finish-reasons | Full `finishReason` value set (STOP, MAX_TOKENS, SAFETY, RECITATION, LANGUAGE, OTHER, BLOCKLIST, PROHIBITED_CONTENT, SPII, MALFORMED_FUNCTION_CALL) and handling guidance. |
| 5 | Gemini 2.5 MAX_TOKENS / missing-finishReason quirk | https://discuss.ai.google.dev/t/gemini-2-5-api-bug-missing-finishreason-when-max-token-limit-is-reached/75837 | Known quirk: `finishReason` can be omitted or text empty on token-limit; basis for EOF-based completion rule. |
| 6 | Google API standard error model | https://github.com/googleapis/googleapis/blob/master/google/ai/generativelanguage/v1beta/generative_service.proto | Error envelope `{ error: { code, message, status, details } }`; `INVALID_ARGUMENT`/`PERMISSION_DENIED`/`RESOURCE_EXHAUSTED` status values. |
| 7 | Real-world Gemini SSE error report (`streamGenerateContent?alt=sse`) | https://github.com/cline/cline/issues/918 | Confirms the live SSE URL form and fetch-failure surface for transport errors. |
| 8 | Apigee — Streaming server-sent events | https://docs.cloud.google.com/apigee/docs/api-platform/develop/server-sent-events | `text/event-stream` content type and SSE framing context for Google streaming APIs. |

### Recommended for deep reading

- **#1 Gemini API — Generating content**: the canonical reference for the request/response schema and the only authoritative source for field semantics; consult it when pinning the exact model and verifying `usageMetadata`/`promptFeedback` placement.
- **#3 Streaming Quickstart (REST)**: the most directly applicable artifact — it shows the exact `?alt=sse&key=` URL and confirms the `candidates[0].content.parts[0].text` accumulation rule the Swift consumer relies on.
- **#4 + #5 finishReason references**: essential for correct safety/truncation classification and for understanding why completion must be EOF-driven rather than `finishReason`-driven.
