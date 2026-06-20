---
status: complete
design_number: 034
slug: llm-streaming-toggle
request_file: ~/aiwork/coding-platform/untype-s/docs/reference/refined-request-llm-streaming-toggle.md
plan_file: ~/aiwork/coding-platform/untype-s/docs/design/plan-034-llm-streaming-toggle.md
investigation_file: null
research_files:
  - ~/aiwork/coding-platform/untype-s/docs/research/swift-urlsession-sse-azure-openai-streaming.md
  - ~/aiwork/coding-platform/untype-s/docs/research/gemini-streaming-and-partial-json.md
codebase_scan_file: ~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-llm-streaming-toggle.md
based_on_commit: e70d4fb37cd9222b8bb1db2f6680d66e4e4c4320
units_changed_from_plan: false
implementation_units:
  - name: "Unit A — Config plumbing (flag -> LLMConfig + UI toggle)"
    plan_steps: [1, 2, 3, 4, 5]
    files:
      - Sources/UntypeCore/ResolvedConfig.swift
      - Sources/UntypeCore/ConfigResolver.swift
      - Sources/UntypeCore/UntypeCommand.swift
      - Sources/UntypeCore/UntypeUISettings.swift
      - Tests/UntypeCoreTests/UntypeCommandTests.swift
      - Tests/UntypeCoreTests/UntypeUISettingsTests.swift
    exposes:
      - "LLMConfig.streamingEnabled: Bool (stored property, default false)"
      - "CLI flags --llm-streaming / --no-llm-streaming"
      - "env var UNTYPE_LLM_STREAMING"
      - "UntypeUISettings.llmStreaming + UntypeUISettingsPatch.llmStreaming + sessionArguments() emission"
    consumes: []
  - name: "Unit B — Streaming transport + provider refiners + partial-JSON extractor"
    plan_steps: [6, 7, 8, 9, 10, 11]
    files:
      - Sources/UntypeCore/LLMRefiners.swift
      - Tests/UntypeCoreTests/LLMRefinersTests.swift
    exposes:
      - "LLMHTTPClient.stream(_:timeoutMs:) -> AsyncThrowingStream<String, Error>"
      - "TextRefining.refine(_:onProgress:) async throws -> String (additive, default-param overload)"
      - "CompositeRefineTranslating.refineAndTranslate(_:onProgress:) async throws -> CompositeRefineTranslateResult (additive)"
    consumes:
      - "LLMConfig.streamingEnabled: Bool"
  - name: "Unit C — Protocol controller wiring + ProtocolEvent + JSONL/diagnostics"
    plan_steps: [12, 13]
    files:
      - Sources/UntypeCore/VoiceAgentProtocolController.swift
      - Sources/UntypeCore/ProtocolJsonlWriter.swift
    exposes:
      - "ProtocolEvent.streamingProgress(sectionId: String, accumulatedText: String)"
      - "VoiceAgentProtocolController.init(... streamingProgress: (@Sendable (String) -> Void)? = nil)"
    consumes:
      - "TextRefining.refine(_:onProgress:)"
      - "CompositeRefineTranslating.refineAndTranslate(_:onProgress:)"
  - name: "Unit D — Runtime factory + native overlay progressive rendering"
    plan_steps: [14, 15]
    files:
      - Sources/UntypeCore/UntypeRuntimeFactory.swift
      - Sources/UntypeCore/NativeUntypeUILauncher.swift
    exposes:
      - "UntypeRuntimeFactory.makeForUI(... streamingProgress: (@Sendable (String) -> Void)? = nil)"
    consumes:
      - "VoiceAgentProtocolController.init(... streamingProgress:)"
      - "LLMConfig.streamingEnabled: Bool"
  - name: "Unit E — Docs"
    plan_steps: [16]
    files:
      - docs/design/project-functions.md
      - docs/design/project-design.md
    exposes: []
    consumes: []
files_to_create: []
files_to_modify:
  - Sources/UntypeCore/ResolvedConfig.swift
  - Sources/UntypeCore/ConfigResolver.swift
  - Sources/UntypeCore/UntypeCommand.swift
  - Sources/UntypeCore/UntypeUISettings.swift
  - Sources/UntypeCore/LLMRefiners.swift
  - Sources/UntypeCore/VoiceAgentProtocolController.swift
  - Sources/UntypeCore/ProtocolJsonlWriter.swift
  - Sources/UntypeCore/UntypeRuntimeFactory.swift
  - Sources/UntypeCore/NativeUntypeUILauncher.swift
  - Tests/UntypeCoreTests/UntypeCommandTests.swift
  - Tests/UntypeCoreTests/UntypeUISettingsTests.swift
  - Tests/UntypeCoreTests/LLMRefinersTests.swift
  - docs/design/project-functions.md
  - docs/design/project-design.md
decisions: 7
created_at: 2026-06-20T00:00:00Z
---

# Design 034 — Optional Configurable LLM Response Streaming

## Objective
Realize Plan 034 / the refined request `refined-request-llm-streaming-toggle.md` as five
file-disjoint implementation units that add an off-by-default, user-toggleable LLM
response-token streaming feature for the `azure-openai` and `google` providers. The design is the
contract between parallel coders: it fixes the exact streaming transport signature, the additive
streaming-capable refiner/composite surfaces, the new `ProtocolEvent.streamingProgress` payload, the
`LLMConfig.streamingEnabled` field, the controller/factory progress-sink threading, and the overlay
progress callback — so that the units integrate on first build. Atomic focused-input delivery and
push-to-talk wiring are explicit non-regressable guardrails in every unit's contract.

## Architecture

The feature is a set of NEW integration points wired into the existing surface (per the integration
directive); it never forks a parallel pipeline and never replaces the one-shot `perform` path. The
single switch is `LLMConfig.streamingEnabled`, threaded from config resolution into the refiners; a
progress callback flows the opposite direction from the refiners back out to the overlay and the
protocol/diagnostics streams.

```
                 CONFIG IN (Unit A)                          STREAM TRANSPORT (Unit B)
 CLI --llm-streaming / env UNTYPE_LLM_STREAMING /        LLMHTTPClient.stream(_:timeoutMs:)
 UI toggle (sessionArguments)                            -> URLSession.bytes(for:) + .lines
        |                                                   (status validated BEFORE body;
        v                                                    activeStreamTasks registry feeds
 ConfigResolver.resolve -> LLMConfig.streamingEnabled        cancelAll())
        |                                                         ^                |
        |  (cloned unchanged by makeTranslator /                  | yields         | accumulated
        |   makeCompositeRefineTranslator)                        | SSE payloads   | text via onProgress
        v                                                         |                v
 LLMRefinerFactory.makeRefiner/Translator/Composite ----> AzureOpenAIRefiner / GoogleRefiner /
                                                          LLMCompositeRefineTranslator
                                                          .refine(_:onProgress:) /
                                                          .refineAndTranslate(_:onProgress:)
                                                                          |
                                  onProgress(accumulatedText: String)    | (DISPLAY ONLY)
                                                                          v
        Unit D: NativeUntypeUILauncher ----injects sink----> Unit C: VoiceAgentProtocolController
        overlay?.show(phase:"finalizing",  via makeForUI       .processSection(onProgress:)
        text: accumulated)                 streamingProgress     |--> streamingProgress sink (overlay)
                                                                 |--> writeProtocol(.streamingProgress)
                                                                 |--> verbose diagnostic line
                                                                 '--> (UNCHANGED) sectionProcessed + timing

   FINAL COMMIT PATH (unchanged):  strict parse / accumulated string -> current -> focusedInputWriter
                                   (ATOMIC, exactly once, on completion — never partial text)
```

Landing locations (justified by the scan's Conventions and Integration Points sections):

- Streaming transport, SSE parsers, and the partial-JSON extractor all land in
  `Sources/UntypeCore/LLMRefiners.swift` as additive members/free functions — the scan's "New
  Integration Points" table names this file for all three, and Conventions
  (`LLMRefiners.swift:1`) prescribe file-scope private free functions over extension namespaces.
- `streamingEnabled` lands on `LLMConfig` in `ResolvedConfig.swift:40-76`, the scan-documented
  injection point (`ResolvedConfig.swift:41-77`, `LLMRefiners.swift:162-176`); the two factory
  clones forward it automatically (scan Note: `makeTranslator` / `makeCompositeRefineTranslator`).
- The flag pair lands in `ConfigResolver.ParsedArguments` per the boolean-flag `switches` dict
  convention (`ConfigResolver.swift:169-178`, `:936-961`), resolved via `parseBoolean` (token set
  `true/false/yes/no/on/off/1/0`).
- The UI toggle lands on `UntypeUISettings` + `UntypeUISettingsPatch` and is emitted by
  `sessionArguments()` — the CLI-to-UI bridge (`UntypeUISettings.swift:195-217`).
- `ProtocolEvent.streamingProgress` lands in `ProtocolJsonlWriter.swift` alongside the unchanged
  `sectionProcessed`.
- The overlay progress sink is injected through `UntypeRuntimeFactory.makeForUI` into the
  controller, then to `NativeUntypeUILauncher` which calls the already-repeat-safe
  `UntypeOverlayController.show(phase:text:)`.

## Data Models

No database tables (this is a macOS app with no datastore). New in-memory/value-type shapes:

- `LLMConfig.streamingEnabled: Bool` — new stored property, default `false`. Optional-toggle
  default, NOT a config fallback (both flag and provider are always present/valid; absence means the
  documented "off"), so it does not violate the no-silent-fallback rule.
- `ChatCompletionChunk` (Azure) and `GeminiStreamChunk` (Google) — private `Decodable` chunk models
  local to `LLMRefiners.swift`, decoding one SSE `data:` payload each (research §3B / Gemini §2).
- `ProtocolEvent.streamingProgress(sectionId: String, accumulatedText: String)` — new enum case;
  serializes to JSONL object `{"type":"streaming.progress","section_id":<id>,"accumulated_text":<text>}`.

## API & Interface Contracts

This section is the SINGLE SOURCE OF TRUTH for every between-unit signature. Units MUST reference
these verbatim; do not restate them divergently elsewhere.

### C1 — `LLMConfig.streamingEnabled` (Unit A exposes -> Unit B, D consume)
```swift
// ResolvedConfig.swift — added as the last stored property and trailing init param.
public let streamingEnabled: Bool
// init(...) gains, as the LAST parameter (keeps all existing call sites source-compatible):
//   streamingEnabled: Bool = false
```

### C2 — Streaming transport on `LLMHTTPClient` (Unit B exposes; internal to Unit B's consumers)
```swift
public protocol LLMHTTPClient: AnyObject {
    func perform(_ request: URLRequest, timeoutMs: Int) async throws -> LLMHTTPResponse   // UNCHANGED
    func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error> // NEW
    func cancelAll()
}
public extension LLMHTTPClient {
    // Default so existing conformers / test mocks compile unchanged:
    func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing:
            LLMRefinementError("streaming not supported", kind: .shape)) }
    }
    func cancelAll() {}
}
```
Element contract: each yielded `String` is ONE SSE `data:` payload with the `data:` prefix stripped
and trimmed; the `[DONE]` sentinel is consumed internally and simply ends the stream (never yielded);
Gemini's EOF (no sentinel) also ends the stream. Status is validated on the up-front `URLResponse`
BEFORE the body is consumed; non-2xx drains the body and finishes-throwing `LLMRefinementError`
(`[401,403] -> .auth`, else `.server`). `CancellationError` / `URLError.cancelled` finish the stream
SILENTLY (not a timeout). Cancellation registry: `private var activeStreamTasks: [UUID: Task<Void, Never>]`
on `URLSessionLLMHTTPClient`; register the work task, deregister + `work.cancel()` in
`continuation.onTermination`, and have `cancelAll()` cancel every entry (research §4D).

### C3 — Streaming-capable refiner surfaces (Unit B exposes -> Unit C consumes)
**AS-IMPLEMENTED (supersedes the original `TextRefining.refine(_:onProgress:)` requirement plan —
see Decision 2 for rationale):** Rather than adding a streaming overload as a REQUIREMENT on the
existing `TextRefining` protocol (which would have forced every existing conformer — e.g. test
`MockRefiner` — to implement the new method or rely on a default that silently breaks the streaming
contract), Unit B introduces a SEPARATE narrow protocol `StreamingTextRefining` in
`LLMRefiners.swift`. `TextRefining` is left UNCHANGED (only `refine(_:)` + `dispose()`). The concrete
`AzureOpenAIRefiner` / `GoogleRefiner` conform to BOTH `TextRefining` and `StreamingTextRefining`;
the controller and the composite translator dispatch streaming via a runtime `as? StreamingTextRefining`
cast, falling back to the one-shot `refine(_:)` when the cast fails. This keeps all existing
`TextRefining` conformers and call sites compiling unchanged WITHOUT adding a protocol-level overload.
`CompositeRefineTranslating` still gains the additive default-nil `onProgress` overload (it has few
conformers, all updated). Existing zero-arg signatures stay valid.
```swift
// VoiceAgentProtocolController.swift (TextRefining — UNCHANGED):
public protocol TextRefining: AnyObject {
    func refine(_ text: String) async throws -> String                                   // UNCHANGED
    func dispose()
}
public extension TextRefining {
    func dispose() {}
}
// LLMRefiners.swift (NEW narrow streaming protocol; concrete refiners conform to BOTH):
public protocol StreamingTextRefining: AnyObject {
    func refine(_ text: String, onProgress: ((String) -> Void)?) async throws -> String  // NEW
}
// public final class AzureOpenAIRefiner: TextRefining, StreamingTextRefining { ... }
// public final class GoogleRefiner: TextRefining, StreamingTextRefining { ... }
// Dispatch (controller + composite): `if let s = refiner as? StreamingTextRefining { s.refine(text, onProgress:) }
//                                      else { refiner.refine(text) }`

// LLMRefiners.swift (CompositeRefineTranslating — additive overload retained as planned):
public protocol CompositeRefineTranslating: AnyObject {
    func refineAndTranslate(_ request: CompositeRefineTranslateRequest)
        async throws -> CompositeRefineTranslateResult                                    // UNCHANGED
    func refineAndTranslate(_ request: CompositeRefineTranslateRequest,
        onProgress: ((String) -> Void)?)
        async throws -> CompositeRefineTranslateResult                                    // NEW
    func dispose()
}
public extension CompositeRefineTranslating {
    func refineAndTranslate(_ r: CompositeRefineTranslateRequest)
        async throws -> CompositeRefineTranslateResult { try await refineAndTranslate(r, onProgress: nil) }
    // Default routes the streaming overload to the base one-shot method, keeping a conformer that
    // implements ONLY the base method (e.g. existing test mocks) valid:
    func refineAndTranslate(_ r: CompositeRefineTranslateRequest, onProgress: ((String) -> Void)?)
        async throws -> CompositeRefineTranslateResult { try await refineAndTranslate(r) }
    func dispose() {}
}
```
`onProgress` semantics (BINDING): invoked on the calling task with the **accumulated** display text
(NOT deltas) after each SSE chunk. For refine/translate that is the accumulated answer string. For
the composite path it is the best-effort `partialStringValue(forKey:in:)` extraction of
`refined_text`/`translated_text` from the in-progress JSON — DISPLAY ONLY. When `streamingEnabled`
is false, OR the provider is neither `azure-openai` nor `google`, the implementation uses the
existing one-shot `perform` path and NEVER invokes `onProgress` (silently inert). The returned value
is ALWAYS the same fully-accumulated, trimmed string / strictly-parsed `CompositeRefineTranslateResult`
the one-shot path returns — for composite, parsed only from the COMPLETE assembled response via the
existing strict `parseResponse` (partial JSON must never reach final fields).

### C4 — `ProtocolEvent.streamingProgress` (Unit C exposes; protocol/diagnostics surface)
```swift
case streamingProgress(sectionId: String, accumulatedText: String)
// jsonObject:
// ["type": "streaming.progress", "section_id": sectionId, "accumulated_text": accumulatedText]
```
`sectionProcessed` and every other existing `ProtocolEvent` case remain byte-for-byte unchanged.

### C5 — Controller progress sink (Unit C exposes -> Unit D consumes)
```swift
// VoiceAgentProtocolController.init gains, as the LAST parameter (default nil keeps call sites valid):
//   streamingProgress: (@Sendable (String) -> Void)? = nil
```
Inside `processSection`, the controller passes an `onProgress` closure to the composite / refine /
translate streaming call sites that (a) invokes the injected `streamingProgress` sink, (b) emits
`writeProtocol(.streamingProgress(sectionId:accumulatedText:))`, and (c) writes one verbose
diagnostic line. The completion-time `writeProtocol(.sectionProcessed(...))`,
`operatorDiagnostic(.refine/.translate)`, and `summary.refineMs/translateMs` (measured to stream
completion) are preserved exactly. The committed/inserted text remains the strict final result —
never the partial progress text.

### C6 — Factory overlay-sink threading (Unit D exposes)
```swift
// UntypeRuntimeFactory.makeForUI gains, as the LAST parameter:
//   streamingProgress: (@Sendable (String) -> Void)? = nil
// passed straight into VoiceAgentProtocolController(... streamingProgress: streamingProgress).
// UntypeRuntimeFactory.make (CLI) is left nil — CLI progress still flows to protocol/diagnostics via C5.
```
Overlay callback contract: `NativeUntypeUILauncher` supplies the sink as
`{ accumulated in overlay?.show(phase: "finalizing", text: accumulated) }`. `show` is already safe to
call repeatedly (scan `NativeUntypeUILauncher.swift:2334`). `hideAfterDelay()` fires only AFTER
processing completes. When streaming is off the sink is simply never invoked -> overlay behaves
exactly as today.

### C7 — Partial-JSON live extractor (Unit B internal; composite display only)
```swift
// LLMRefiners.swift, private free function (file-scope, per Conventions):
func partialStringValue(forKey key: String, in json: String) -> String?
```
Escape-aware tolerant scanner from research §5 (handles `\" \\ \/ \n \t \r \b \f`, complete `\uXXXX`,
defers incomplete `\uXXXX` at the buffer tail, returns decoded-so-far for an unterminated string).
DISPLAY ONLY — must never feed the committed result.

## Module Organization

All changes are modifications of existing files (no new files). File ownership is pairwise disjoint
across the five units (see "Implementation Units"). Per the scan's Conventions: named imports only;
explicit `public` on new API; private helpers as file-scope free functions; Swift Testing
(`@Test`/`#expect`) for new tests; new boolean flag via the `switches` dict pattern; UI toggle
emitted by `sessionArguments()`.

## Error Handling Strategy

- **No new required config; raise-on-missing unaffected.** `streamingEnabled` is an OPTIONAL toggle
  with a documented default of `false`. No missing-required-config substitution occurs, so the
  project's no-silent-fallback rule is honored. Any genuinely required setting elsewhere continues to
  raise. The "silently inert on a non-streaming provider" behavior is explicitly NOT a fallback
  violation (resolved open question #3).
- **Streaming HTTP errors** mirror the one-shot classification: status validated on the up-front
  `URLResponse` before body consumption; non-2xx -> `LLMRefinementError` (`[401,403] -> .auth`, else
  `.server`); mid-stream transport failure routes through the existing `mapTransportError`.
- **Cancellation** (`CancellationError` / `URLError.cancelled`) finishes the stream silently — never
  surfaced as an error (avoids a spurious error on every new push-to-talk press).
- **Mid-stream failure DISCARDS** accumulated display text and throws so the caller's existing
  `logOperatorFailure` handling runs identically to the one-shot path.
- **Composite partial JSON** is never parsed into final fields; the committed result comes only from
  the strict `parseResponse` over the complete response.

## Implementation Units

### Unit A — Config plumbing (flag -> LLMConfig + UI toggle)
- Plan steps: 1, 2, 3, 4, 5.
- Files: `ResolvedConfig.swift`, `ConfigResolver.swift`, `UntypeCommand.swift`,
  `UntypeUISettings.swift`, `UntypeCommandTests.swift`, `UntypeUISettingsTests.swift`.
- Exposes: **C1** `LLMConfig.streamingEnabled`; `--llm-streaming`/`--no-llm-streaming` (resolved
  `parsed.switchValue(for:"--llm-streaming") ?? parseBoolean(chain.get("UNTYPE_LLM_STREAMING")?.value, ...) ?? false`);
  `UntypeUISettings.llmStreaming` + patch field + `sessionArguments()` emission
  (`normalized.llmStreaming ? "--llm-streaming" : "--no-llm-streaming"`); help-text entries.
- Consumes: nothing.
- Guardrails: does NOT touch `hotkeyMonitorConfigurationChanged` (streaming does not affect hotkey
  config — push-to-talk unaffected). `streamingEnabled` is the LAST init param (source-compatible).

### Unit B — Streaming transport + provider refiners + partial-JSON extractor
- Plan steps: 6, 7, 8, 9, 10, 11.
- Files: `LLMRefiners.swift`, `LLMRefinersTests.swift`.
- Exposes: **C2** `LLMHTTPClient.stream`; **C3** the `onProgress` overloads on `TextRefining` and
  `CompositeRefineTranslating`; **C7** `partialStringValue(forKey:in:)`.
- Consumes: **C1** `LLMConfig.streamingEnabled`.
- Behavior: Azure adds `"stream": true` to the existing body (URL/auth + temperature-vs-reasoning
  gating unchanged; NO `stream_options`/usage telemetry in v1), decodes `chat.completion.chunk`,
  accumulates `choices[0].delta.content`. Google targets `:streamGenerateContent?alt=sse` (body
  identical to `:generateContent`), accumulates `candidates[0].content.parts[].text` filtering
  `thought == true`, treats EOF as completion. Composite drives `onProgress` from
  `partialStringValue(...)` but commits via the existing strict `parseResponse`. `cancelAll()`
  aborts in-flight streams via `activeStreamTasks`.
- Guardrails: `perform` unchanged; the non-streaming path is byte-for-byte identical; the final
  returned string equals the one-shot equivalent.

### Unit C — Protocol controller wiring + ProtocolEvent + JSONL/diagnostics
- Plan steps: 12, 13.
- Files: `VoiceAgentProtocolController.swift`, `ProtocolJsonlWriter.swift`.
- Exposes: **C4** `ProtocolEvent.streamingProgress`; **C5** the controller's `streamingProgress`
  init param + `processSection` `onProgress` forwarding.
- Consumes: **C3** the refiner `onProgress` overloads.
- Guardrails: `sectionProcessed`, operator diagnostics, and `refineMs/translateMs` timing preserved;
  committed/inserted text is the strict final result, never partial progress. Note: the
  `TextRefining` overload (C3) is added in this file's protocol declaration but its DEFAULT-IMPL and
  every concrete conformance are authored by Unit B — Unit C only adds the protocol requirement +
  consumes it. To keep files disjoint, the protocol requirement line and its extension default both
  live where the protocol is declared; `TextRefining` is declared in
  `VoiceAgentProtocolController.swift`. **Resolution:** the `TextRefining` overload (requirement +
  default extension, C3) is owned by **Unit C** (the file that declares `TextRefining`); Unit B
  authors the concrete `refine(_:onProgress:)` bodies on `AzureOpenAIRefiner`/`GoogleRefiner` in
  `LLMRefiners.swift`. `CompositeRefineTranslating` is declared in `LLMRefiners.swift`, so its
  overload stays wholly in Unit B. This keeps `VoiceAgentProtocolController.swift` (Unit C) and
  `LLMRefiners.swift` (Unit B) file-disjoint while honoring the single-source contract C3.

### Unit D — Runtime factory + native overlay progressive rendering
- Plan steps: 14, 15.
- Files: `UntypeRuntimeFactory.swift`, `NativeUntypeUILauncher.swift`.
- Exposes: **C6** `makeForUI(... streamingProgress:)`.
- Consumes: **C5** controller `streamingProgress`; **C1** `LLMConfig.streamingEnabled` (already
  flows through `LLMRefinerFactory.make*` — no structural refiner-construction change).
- Guardrails (HARD): MUST NOT change push-to-talk wiring (hotkey listening, press/release routing,
  audio gate, recording/finalizing show/hide) or focused-input delivery. Overlay updates DISPLAY
  only; insertion stays atomic on completion of the strictly-parsed final text. Step-15 verify:
  newest `~/.tool-agents/untype/release-latency.jsonl` record shows `focused_input.ok=true` after a
  streamed release into a focused field.

### Unit E — Docs
- Plan step: 16.
- Files: `docs/design/project-functions.md`, `docs/design/project-design.md`.
- Exposes/consumes: nothing (documentation only). Adds FR-28 and a dated design note. Does NOT
  create `configuration-guide.md` if absent (state the skip in the report).

## Design Decisions

1. **Keep the plan's 5-unit partition; assign `ResolvedConfig.swift` wholly to Unit A.** The
   integration directive flagged a potential A/B overlap because Plan Step 1 (the `streamingEnabled`
   field) is a build-prerequisite of Unit B. Resolution: the field is EDITED only in Unit A's
   `ResolvedConfig.swift`; Unit B merely CONSUMES it as contract C1. File sets remain pairwise
   disjoint, so `units_changed_from_plan: false`. Alternative rejected: merging A+B — unnecessary,
   since there is no shared-edit, only a build-order dependency the orchestrator already schedules
   (A Step 1 first).
2. **Streaming dispatched via a SEPARATE `StreamingTextRefining` protocol + runtime cast, NOT a
   `TextRefining.refine(_:onProgress:)` protocol requirement (CHANGED during implementation —
   2026-06-20).** The original design added the streaming overload as a REQUIREMENT on `TextRefining`
   (declared in `VoiceAgentProtocolController.swift`, Unit C) with a default extension. During
   implementation this was found to be hazardous: adding a method to a `public` protocol that other
   conformers implement (notably the test `MockRefiner` and any future `TextRefining` conformer) is a
   source-fragile change, and a default extension that "streams" by quietly calling the one-shot
   method would make the protocol's streaming contract silently wrong for non-streaming conformers.
   **As implemented:** `TextRefining` is left UNCHANGED; Unit B introduces a narrow
   `public protocol StreamingTextRefining { func refine(_:onProgress:) }` in `LLMRefiners.swift`, to
   which the concrete `AzureOpenAIRefiner`/`GoogleRefiner` conform alongside `TextRefining`. The
   controller's private `refine(_:using:onProgress:)` and the composite translator dispatch streaming
   via `as? StreamingTextRefining`, falling back to one-shot `refine(_:)` when the cast fails (i.e.
   silently inert for non-conforming refiners). This keeps Unit B (`LLMRefiners.swift`) and Unit C
   (`VoiceAgentProtocolController.swift`) file-disjoint AND avoids mutating the widely-implemented
   `TextRefining` protocol. `CompositeRefineTranslating` (declared in `LLMRefiners.swift`, Unit B,
   with few conformers) retains the additive default-nil `onProgress` overload as originally planned.
   Net behavior is identical to C3's intent: accumulated display text via `onProgress`, silently
   inert when streaming is off or the refiner does not stream, strict final result committed.
   Alternative rejected: the original `TextRefining` overload — fragile for existing/future
   conformers and gives a misleading default streaming contract.
3. **Additive default-nil overloads over a new parallel method name or a non-optional callback.**
   Preserves every existing call site and test (scan Conventions: existing one-shot signatures stay
   usable), and yields a single switch point at the call site. Alternative rejected: replacing
   `refine`'s signature — would ripple through all callers and tests.
4. **Yield ACCUMULATED text (not deltas) from `onProgress`.** The UI can `overlay.show(text:)`
   verbatim with no client-side accumulation and no ordering bugs (research §1D). Alternative
   rejected: deltas — cheaper but pushes accumulation/ordering into every consumer.
5. **`stream(...)` returns `AsyncThrowingStream<String, Error>` of raw SSE payloads; per-provider
   chunk decoding lives in the refiners.** Keeps the transport provider-agnostic and shared between
   Azure and Google (research recommendation). Alternative rejected: a typed chunk stream — would
   leak provider JSON shapes into the transport layer.
6. **Track Swift `Task`s in `activeStreamTasks`, not `URLSessionDataTask`s.** `bytes(for:)` does not
   expose the data task, so the existing `activeTasks` pattern cannot cover streams; the Task
   registry + `onTermination` preserves the shared-session "cancel only my requests" guarantee and
   the `dispose()` -> `cancelAll()` teardown that the push-to-talk new-session path relies on
   (research §4D). Alternative rejected: the delegate push model — heavier, needed only for
   pre-macOS-12 or multi-line SSE, neither of which applies.
7. **Composite display via best-effort live extraction; commit via strict parse.** Satisfies
   resolved open question #1: progressive `refined_text`/`translated_text` for display, final result
   only from the complete response. Alternative rejected: showing raw in-progress JSON — worse UX and
   still requires the strict final parse anyway.

## Decisions Requiring User Review
none. All four Phase-1 open questions were resolved at the orchestrator gate (refined request
"Open Questions — Resolutions") and are binding inputs to this design; no new user-facing trade-off
was introduced.

## Risks
- **Composite partial JSON leaking into the committed result** -> mitigation: contract C3 mandates
  the committed `CompositeRefineTranslateResult` come only from the existing strict `parseResponse`
  over the complete response; Unit B test (Plan Step 11c) feeds a partial-then-complete sequence and
  asserts the partial prefix is never parsed into final fields.
- **In-flight stream not aborted on a new push-to-talk session** (push-to-talk guardrail) ->
  mitigation: `activeStreamTasks` registry + `cancelAll()` (Decision 6); the existing `dispose()` ->
  `cancelAll()` teardown is preserved; Step-15 smoke check validates a new press supersedes a stream.
- **Focused-input delivery regression** (fundamental guardrail) -> mitigation: `FocusedInputDelivery`
  is Out-of-Scope and untouched; only overlay DISPLAY updates; Unit D verify asserts
  `focused_input.ok=true` in the newest `release-latency.jsonl`.
- **Reasoning deployments with restricted streaming (e.g. Azure o3 limited-access)** -> mitigation:
  `perform` (one-shot) kept intact; the streaming method maps non-2xx to `auth/server` via the
  existing classification, surfaced through the standard `logOperatorFailure` path.
- **Silent-inert flag misread as a no-fallback violation** -> mitigation: documented here and in FR-28
  (Unit E); both flag and provider are present/valid; no missing-config substitution occurs.
- **Scan staleness:** none — scan `last_scanned_commit` `e70d4fb…` equals plan `based_on_commit` and
  the current `HEAD`; no re-scan required before implementation.
