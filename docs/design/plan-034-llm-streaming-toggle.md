---
status: complete
plan_number: 034
slug: llm-streaming-toggle
request_file: ~/aiwork/coding-platform/untype-s/docs/reference/refined-request-llm-streaming-toggle.md
investigation_file: null
research_files:
  - ~/aiwork/coding-platform/untype-s/docs/research/swift-urlsession-sse-azure-openai-streaming.md
  - ~/aiwork/coding-platform/untype-s/docs/research/gemini-streaming-and-partial-json.md
codebase_scan_file: ~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-llm-streaming-toggle.md
based_on_commit: e70d4fb37cd9222b8bb1db2f6680d66e4e4c4320
scan_commit_match: true
steps: 16
open_questions: 0
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
implementation_units:
  - name: "Unit A — Config plumbing (flag → LLMConfig)"
    steps: [1, 2, 3, 4, 5]
    files:
      - Sources/UntypeCore/ResolvedConfig.swift
      - Sources/UntypeCore/ConfigResolver.swift
      - Sources/UntypeCore/UntypeCommand.swift
      - Sources/UntypeCore/UntypeUISettings.swift
      - Tests/UntypeCoreTests/UntypeCommandTests.swift
      - Tests/UntypeCoreTests/UntypeUISettingsTests.swift
  - name: "Unit B — Streaming transport, provider refiners, partial-JSON extractor"
    steps: [6, 7, 8, 9, 10, 11]
    files:
      - Sources/UntypeCore/LLMRefiners.swift
      - Tests/UntypeCoreTests/LLMRefinersTests.swift
  - name: "Unit C — Protocol controller wiring + ProtocolEvent + JSONL/diagnostics"
    steps: [12, 13]
    files:
      - Sources/UntypeCore/VoiceAgentProtocolController.swift
      - Sources/UntypeCore/ProtocolJsonlWriter.swift
  - name: "Unit D — Runtime factory + native overlay progressive rendering"
    steps: [14, 15]
    files:
      - Sources/UntypeCore/UntypeRuntimeFactory.swift
      - Sources/UntypeCore/NativeUntypeUILauncher.swift
  - name: "Unit E — Docs"
    steps: [16]
    files:
      - docs/design/project-functions.md
      - docs/design/project-design.md
build_command: swift build
test_command: swift test
created_at: 2026-06-20T00:00:00Z
---

# Plan 034 — Optional Configurable LLM Response Streaming

## Objective
Add an off-by-default, user-toggleable feature that streams LLM **response tokens** for the
`azure-openai` and `google` providers (Azure SSE `"stream": true`; Gemini
`:streamGenerateContent?alt=sse`), renders the refined/translated text progressively in the
overlay `finalizing` phase, and emits incremental progress to the agent-protocol JSONL output and
verbose diagnostics — while keeping the existing one-shot path, atomic focused-input delivery, and
push-to-talk wiring fully intact. Serves
`docs/reference/refined-request-llm-streaming-toggle.md`.

## Context
Inputs: refined request @`docs/reference/refined-request-llm-streaming-toggle.md`;
codebase scan @`docs/reference/codebase-scan-llm-streaming-toggle.md`
(scan commit `e70d4fb…` == current `HEAD`, fresh); research
@`docs/research/swift-urlsession-sse-azure-openai-streaming.md` and
@`docs/research/gemini-streaming-and-partial-json.md`; existing design
@`docs/design/project-design.md`.

Chosen approach (binding, per the orchestrator's post-scan duplication directive): this feature
does NOT exist yet — implement it as **new integration points wired into the existing surface**,
never a parallel implementation and never a replacement of the one-shot path. Add
`streamingEnabled: Bool` to `LLMConfig`, forward it through BOTH factory clones, add a NEW
streaming method to `LLMHTTPClient` (`URLSession.bytes(for:)` + `.lines`, status checked before
the body) alongside the unchanged buffered `perform`, add a NEW `ProtocolEvent` case for
incremental progress (leaving `sectionProcessed` unchanged), and drive overlay/protocol/diagnostics
from an accumulated-text progress callback. The streaming flag is **silently inert** for any
provider other than `azure-openai`/`google`. The composite path uses best-effort live extraction of
`refined_text`/`translated_text` from the in-progress JSON **for display only**; the committed
result always comes from the existing strict `parseResponse` over the fully-assembled response.

## Open Questions
none. (All four Phase-1 open questions were resolved at the orchestrator gate and are recorded in
the refined request's "Open Questions — Resolutions" section; they are treated as binding
requirements throughout this plan.)

## Steps

### Step 1 — Add `streamingEnabled` to `LLMConfig`
- depends_on: []
- files: `Sources/UntypeCore/ResolvedConfig.swift` (modify)
- action: Add a `public let streamingEnabled: Bool` stored property to the `LLMConfig` struct
  (struct at lines 40–76) and a corresponding `streamingEnabled: Bool = false` parameter to its
  `init` (lines 55–75), assigning it. The default `false` keeps every existing construction
  source-compatible. This is an optional toggle default, not a config fallback (no missing-required
  substitution), so it does not violate the no-fallback rule.
- verify: `swift build`
- done: `LLMConfig` exposes `streamingEnabled` with default `false`; build succeeds.

### Step 2 — Resolve the streaming flag in `ConfigResolver`
- depends_on: [1]
- files: `Sources/UntypeCore/ConfigResolver.swift` (modify)
- action: In `ParsedArguments.init` (lines 925–995), add `--llm-streaming` / `--no-llm-streaming`
  to the strict allow-list `switch` block as entries in the existing `switches` dict under key
  `"--llm-streaming"` (mirroring the `--quick-close` / `--no-quick-close` precedent) BEFORE the
  default "Unknown option" throw at the end. In `resolve(argv:)`, immediately after the `refine`
  resolution block (~lines 368–374), compute the value as
  `parsed.switchValue(for: "--llm-streaming") ?? parseBoolean(chain.get("UNTYPE_LLM_STREAMING")?.value, flagName: "--llm-streaming", envName: "UNTYPE_LLM_STREAMING") ?? false`
  (CLI flag highest, then env via the four-tier chain, default `false`), and pass it into the
  `LLMConfig(... streamingEnabled:)` construction (LLM block ~lines 406–416). Use the existing
  `parseBoolean` token set (`true/false/yes/no/on/off/1/0`).
- verify: `swift build`
- done: `--llm-streaming` / `--no-llm-streaming` are recognized (no "Unknown option" throw) and
  `UNTYPE_LLM_STREAMING` resolves at the correct precedence into `LLMConfig.streamingEnabled`.

### Step 3 — Add the flags to help text
- depends_on: []
- files: `Sources/UntypeCore/UntypeCommand.swift` (modify)
- action: Add `--llm-streaming` / `--no-llm-streaming` entries to the `helpText` block (~line 94),
  following the exact format of the `--quick-close` / `--no-quick-close` lines, noting default =
  off and that it applies only to `azure-openai`/`google`.
- verify: `swift build`
- done: Help text lists the new flag pair with the default documented.

### Step 4 — Add the UI toggle to `UntypeUISettings`
- depends_on: []
- files: `Sources/UntypeCore/UntypeUISettings.swift` (modify)
- action: Add `var llmStreaming: Bool` to both the `UntypeUISettings` struct (after `llmModel`,
  ~line 17) and `UntypeUISettingsPatch` (~line 253). Default `false` in `UntypeUISettings.default`
  (lines 36–69). Thread it through `merged(_:)` using the existing nil-coalescing pattern
  (lines 114–192). Emit it in `sessionArguments()` (lines 194–216) as
  `normalized.llmStreaming ? "--llm-streaming" : "--no-llm-streaming"` — without this emission the
  UI toggle has no runtime effect (CLI-to-UI bridge requirement from the scan). Do NOT touch
  `hotkeyMonitorConfigurationChanged` (streaming does not affect hotkey config).
- verify: `swift build`
- done: `llmStreaming` exists on both types, defaults off, is merged, and is emitted by
  `sessionArguments()`.

### Step 5 — Tests for config resolution and UI bridging
- depends_on: [2, 4]
- files: `Tests/UntypeCoreTests/UntypeCommandTests.swift` (modify),
  `Tests/UntypeCoreTests/UntypeUISettingsTests.swift` (modify)
- action: Using Swift Testing (`@Test`, `#expect`), add: (a) tests asserting `--llm-streaming`
  resolves `true` and `--no-llm-streaming` resolves `false` via the CLI flag, that
  `UNTYPE_LLM_STREAMING` is honored at the env layer, that CLI flag overrides env, and that the
  default with nothing set is `false`; (b) a test asserting `UntypeUISettings.default.llmStreaming
  == false`, that `merged` applies the patch, and that `sessionArguments()` emits
  `--llm-streaming` when on and `--no-llm-streaming` when off.
- verify: `swift test`
- done: New config/UI tests pass; existing tests remain green.

### Step 6 — Add a streaming method to the `LLMHTTPClient` protocol
- depends_on: [1]
- files: `Sources/UntypeCore/LLMRefiners.swift` (modify)
- action: Add an additive streaming method to the `LLMHTTPClient` protocol (lines 63–66) —
  `func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error>` —
  yielding each SSE `data:` payload (prefix stripped, `[DONE]` excluded, sentinel ends the stream).
  Provide a default implementation in the protocol extension (lines 68–70) that throws
  `LLMRefinementError("streaming not supported", kind: .shape)` so existing conformers (and test
  mocks) compile unchanged. Keep `perform` and `cancelAll` exactly as-is.
- verify: `swift build`
- done: Protocol exposes `stream`; non-streaming `perform` path and existing conformers still
  compile.

### Step 7 — Implement `stream` on `URLSessionLLMHTTPClient` with cancellation registry
- depends_on: [6]
- files: `Sources/UntypeCore/LLMRefiners.swift` (modify)
- action: Implement `stream` on `URLSessionLLMHTTPClient` per the research §1D reference: set
  `request.timeoutInterval`, build an `AsyncThrowingStream`, call `sharedSession.bytes(for:)`,
  validate `HTTPURLResponse.statusCode` BEFORE consuming the body (on non-2xx drain bytes and throw
  `LLMRefinementError` with `[401,403] → .auth` else `.server`), iterate `bytes.lines`, strip
  `data:`, break on `[DONE]`, `continuation.yield(payload)`. Add a parallel
  `activeStreamTasks: [UUID: Task<Void, …>]` registry (since `bytes(for:)` does not expose a
  `URLSessionDataTask`): register the work task, deregister in `continuation.onTermination` which
  also calls `work.cancel()`, and extend `cancelAll()` to cancel every entry. Map
  `CancellationError`/`URLError.cancelled` to a silent finish (not a timeout); route other transport
  errors through `mapTransportError`. Do not set a session-wide resource timeout.
- verify: `swift build`
- done: `URLSessionLLMHTTPClient.stream` exists, validates status before body, and `cancelAll()`
  aborts in-flight streams via the new registry.

### Step 8 — Add the partial-JSON live extractor
- depends_on: [6]
- files: `Sources/UntypeCore/LLMRefiners.swift` (modify)
- action: Add a private free function `partialStringValue(forKey:in:)` alongside the existing
  `extractJSONObjectText`, implementing the escape-aware tolerant scanner from research §5 (handles
  `\" \\ \/ \n \t \r \b \f`, complete `\uXXXX`, defers incomplete `\uXXXX` at the buffer tail,
  returns the decoded-so-far value for an unterminated string). This is **display-only**; it must
  never feed the final committed result.
- verify: `swift build`
- done: `partialStringValue(forKey:in:)` compiles and is available for the composite consumer.

### Step 9 — Streaming path for `AzureOpenAIRefiner`
- depends_on: [7]
- files: `Sources/UntypeCore/LLMRefiners.swift` (modify)
- action: Give `AzureOpenAIRefiner` an `onProgress: ((String) -> Void)?` aware streaming refine.
  When `LLMConfig.streamingEnabled` is true, build the request with `"stream": true` added to the
  existing body (reuse current URL/auth and the temperature-vs-reasoning gating unchanged; do NOT
  add `stream_options`/usage telemetry in v1), consume `httpClient.stream(...)`, decode each chunk
  as `chat.completion.chunk`, accumulate `choices[0].delta.content`, invoke `onProgress` with the
  **accumulated** text after each delta, and return the same fully-accumulated, trimmed `String` the
  one-shot path returns. Tolerate empty `choices` and `delta == {}`. Preserve
  `auth/shape/server/timeout` classification and HTTP-status validation. When streaming is off,
  keep using the existing `perform` one-shot path unchanged.
- verify: `swift build`
- done: Azure refiner streams when enabled, returns the one-shot-equivalent final string, and falls
  back to `perform` when disabled.

### Step 10 — Streaming path for `GoogleRefiner` and composite streaming
- depends_on: [7, 8]
- files: `Sources/UntypeCore/LLMRefiners.swift` (modify)
- action: For `GoogleRefiner`: when streaming is enabled, target `:streamGenerateContent?alt=sse`
  (body byte-for-byte identical to `:generateContent`), consume `httpClient.stream(...)`, decode
  each chunk's `candidates[0].content.parts[].text` (filter `thought == true`), accumulate with
  empty-string join, invoke `onProgress(accumulated)`, treat EOF as completion (no `[DONE]`), and
  classify prompt/candidate safety blocks and empty output per research §4. For
  `LLMCompositeRefineTranslator.refineAndTranslate` (line ~441 area): when streaming is enabled,
  accumulate the raw concatenated model content, call `partialStringValue(forKey: "refined_text"/
  "translated_text", in: raw)` to drive `onProgress` with best-effort **display-only** text, and on
  completion run the EXISTING strict `parseResponse` over the fully-assembled response to produce
  the committed `CompositeRefineTranslateResult`. Partial JSON must never be parsed into final
  fields. On mid-stream failure, discard partial display text and throw so the caller's
  `logOperatorFailure` handling runs (same as one-shot). Wire `onProgress` plumbing so refine,
  translate, and composite all accept the optional callback while keeping existing non-streaming
  signatures valid (additive overload or optional parameter on `TextRefining.refine` /
  `CompositeRefineTranslating.refineAndTranslate`).
- verify: `swift build`
- done: Google refiner and composite path stream when enabled; composite final result comes only
  from the strict parse of the complete response.

### Step 11 — Refiner/transport streaming tests
- depends_on: [9, 10]
- files: `Tests/UntypeCoreTests/LLMRefinersTests.swift` (modify)
- action: With Swift Testing and a mock `LLMHTTPClient` that yields scripted SSE `data:` payloads
  via the new `stream` method, add tests: (a) Azure streaming refine accumulates deltas and returns
  the one-shot-equivalent final string, invoking `onProgress` with monotonically growing accumulated
  text; (b) Google streaming refine accumulates `parts[].text` and completes on EOF; (c) composite
  path fed a partial-then-complete SSE sequence yields best-effort display text mid-stream but parses
  `refinedText`/`translatedText` only from the complete response (assert a deliberately
  partial-JSON prefix is never parsed into the final fields); (d) error/shape/auth classification on
  a non-2xx streamed response and on a mid-stream transport error; (e) `cancelAll()` aborts an
  in-flight stream. Keep all existing `LLMRefinersTests` passing unchanged.
- verify: `swift test`
- done: New streaming tests pass; existing refiner tests remain green.

### Step 12 — New `ProtocolEvent` case for streaming progress
- depends_on: []
- files: `Sources/UntypeCore/ProtocolJsonlWriter.swift` (modify)
- action: Add a new case to the `ProtocolEvent` enum (lines 7–26), e.g.
  `case streamingProgress(sectionId: String, accumulatedText: String)`, and add its serialization to
  the `jsonObject` computed property (lines 59–144) following the style of the existing cases. Leave
  `sectionProcessed` (lines 13–21) and every other case unchanged for backward compatibility.
- verify: `swift build`
- done: `ProtocolEvent.streamingProgress` exists and serializes to JSONL; existing events
  unchanged.

### Step 13 — Wire the progress callback through `VoiceAgentProtocolController.processSection`
- depends_on: [10, 12]
- files: `Sources/UntypeCore/VoiceAgentProtocolController.swift` (modify)
- action: Add an optional streaming-progress sink to the controller (constructor-injected closure,
  e.g. `streamingProgress: ((String) -> Void)?`, default nil — keeps existing call sites valid). In
  `processSection` (lines 249–385), pass an `onProgress` closure to the composite (line 268),
  refine (line 294), and translate (line 321) streaming call sites that: (a) calls the injected
  streaming-progress sink (drives the overlay in UI mode), and (b) emits
  `writeProtocol(.streamingProgress(sectionId:accumulatedText:))` to the agent-protocol JSONL output
  and a verbose diagnostic line (per resolved open-question #4). The existing completion-time
  `writeProtocol(.sectionProcessed(...))` at line 334 stays intact and unchanged. Existing
  `operatorDiagnostic(.refine/.translate)` and `summary.refineMs/translateMs` timing (measured to
  stream completion) must continue exactly as today. The final inserted/committed text remains
  `current` after the strict result — never the partial progress text.
- verify: `swift build`
- done: `processSection` forwards an `onProgress` callback that emits `streamingProgress` events and
  feeds the injected sink, while `sectionProcessed`, diagnostics, and timing are preserved.

### Step 14 — Inject the overlay-update callback through `UntypeRuntimeFactory.makeForUI`
- depends_on: [13]
- files: `Sources/UntypeCore/UntypeRuntimeFactory.swift` (modify)
- action: In `makeForUI` (lines 104+), accept an optional
  `streamingProgress: (@Sendable (String) -> Void)? = nil` parameter and pass it into the
  `VoiceAgentProtocolController` initializer (the controller is built ~line 138). The `make` (CLI)
  path needs no overlay sink — leave it nil there (CLI streaming progress still flows to
  protocol/diagnostics via Step 13). `LLMConfig.streamingEnabled` already flows through the existing
  `LLMRefinerFactory.make*` calls (lines 126–133) — no structural change to refiner construction.
- verify: `swift build`
- done: `makeForUI` threads an optional streaming-progress sink into the controller; CLI path
  unaffected.

### Step 15 — Progressive overlay rendering in `NativeUntypeUILauncher`
- depends_on: [14]
- files: `Sources/UntypeCore/NativeUntypeUILauncher.swift` (modify)
- action: Provide the `streamingProgress` sink to `makeForUI` from the UI launcher so each
  accumulated-text update calls `overlay?.show(phase: "finalizing", text: accumulatedText)`
  (`UntypeOverlayController.show` is already safe to call repeatedly). In `stopHotkeySession`
  (lines 442–455), keep the initial `overlay?.show(phase: "finalizing", text: latestTranscript)`
  for the streaming-off / no-tokens-yet case, but ensure `overlay?.hideAfterDelay()` only fires
  after processing completes so progressive updates are visible until the stream settles. When
  streaming is off, behavior is identical to today (the sink is simply never invoked). MUST NOT
  change push-to-talk wiring (hotkey listening, press/release routing, audio gate, recording/
  finalizing show/hide) or focused-input delivery — insertion stays atomic on completion of the
  strictly-parsed final text.
- verify: `swift build`; then a manual push-to-talk smoke check with streaming ON into a focused
  text field, confirming the overlay updates progressively AND the newest
  `~/.tool-agents/untype/release-latency.jsonl` record shows `focused_input.ok=true`; and a second
  smoke check with streaming OFF confirming unchanged behavior.
- done: Overlay updates progressively during streamed releases and settles on the final text; with
  streaming off the overlay behaves as today; push-to-talk and atomic focused-input delivery are
  unregressed (`focused_input.ok=true`).

### Step 16 — Documentation updates
- depends_on: [2, 4, 10, 13, 15]
- files: `docs/design/project-functions.md` (modify), `docs/design/project-design.md` (modify)
- action: Append a new functional-requirement entry (FR-28) to `project-functions.md` describing the
  optional LLM response-streaming toggle: the `--llm-streaming` / `--no-llm-streaming` flags,
  `UNTYPE_LLM_STREAMING` env var, UI toggle, default = off, the silently-inert behavior for
  non-`azure-openai`/`google` providers, progressive overlay rendering, the new
  `streamingProgress` protocol/diagnostics events, and the preserved atomic focused-input delivery.
  Add a dated design-decision note to `project-design.md` referencing the provenance chain
  (refined-request → research → scan → this plan). If `docs/design/configuration-guide.md` exists,
  add the flag's purpose/options/precedence/default there; if it does not exist, skip it (state the
  skip in the executor report) — do not create it as part of this plan.
- verify: `grep -n "FR-28" docs/design/project-functions.md` returns a match; `swift build`
  (unaffected, sanity).
- done: `project-functions.md` documents FR-28 and `project-design.md` has a dated streaming design
  note.

## Implementation Units

### Unit A — Config plumbing (flag → LLMConfig)
- Steps: 1, 2, 3, 4, 5.
- Files: `ResolvedConfig.swift`, `ConfigResolver.swift`, `UntypeCommand.swift`,
  `UntypeUISettings.swift`, `UntypeCommandTests.swift`, `UntypeUISettingsTests.swift`.
- Interface contract consumed by other units: `LLMConfig.streamingEnabled: Bool` (default `false`)
  is the single switch every refiner reads. Unit B depends on this field existing (Step 1) but not
  on the rest of Unit A.

### Unit B — Streaming transport, provider refiners, partial-JSON extractor
- Steps: 6, 7, 8, 9, 10, 11.
- Files: `LLMRefiners.swift`, `LLMRefinersTests.swift`.
- Interface contracts exposed: `LLMHTTPClient.stream(_:timeoutMs:)`; the optional `onProgress`
  callback on `TextRefining.refine` / `CompositeRefineTranslating.refineAndTranslate` that yields
  **accumulated** display text. Unit C consumes that `onProgress` surface.

### Unit C — Protocol controller wiring + ProtocolEvent + JSONL/diagnostics
- Steps: 12, 13.
- Files: `VoiceAgentProtocolController.swift`, `ProtocolJsonlWriter.swift`.
- Interface contracts: a constructor-injected `streamingProgress: ((String) -> Void)?` on
  `VoiceAgentProtocolController`; the new `ProtocolEvent.streamingProgress(sectionId:
  accumulatedText:)`. Unit D injects the sink via the factory.

### Unit D — Runtime factory + native overlay progressive rendering
- Steps: 14, 15.
- Files: `UntypeRuntimeFactory.swift`, `NativeUntypeUILauncher.swift`.
- Interface contract consumed: the controller's `streamingProgress` sink (from Unit C) and
  `LLMConfig.streamingEnabled` (from Unit A).

### Unit E — Docs
- Step: 16.
- Files: `docs/design/project-functions.md`, `docs/design/project-design.md`.

**Serialization notes (units are NOT fully file-disjoint at the dependency level):** the file sets
of A/B/C/D are pairwise disjoint, so the four code units can be coded in parallel. However there are
hard build-order dependencies across units: B Step 1 lives in Unit A's `ResolvedConfig.swift` (the
`streamingEnabled` field) — schedule Step 1 first. Unit C Step 13 depends on Unit B's `onProgress`
surface (Step 10) and Unit C Step 12; Unit D depends on Unit C. Recommended ordering for an
orchestrator: A(Step 1) → then B and the rest of A in parallel → C → D → E. Unit E touches only docs
and can run last.

## Risks & Mitigations
- **Composite partial-JSON leaking into the committed result** → mitigation: Step 10 mandates the
  final `CompositeRefineTranslateResult` come only from the existing strict `parseResponse` over the
  complete response; Step 11(c) adds a test feeding a partial-then-complete sequence and asserts the
  partial prefix is never parsed into final fields.
- **In-flight stream not aborted on a new push-to-talk session** (push-to-talk guardrail) →
  mitigation: Step 7 adds the `activeStreamTasks` registry and extends `cancelAll()`; the existing
  `dispose()` → `cancelAll()` teardown path is preserved, and Step 15's smoke check validates a new
  press cleanly supersedes a stream.
- **Focused-input delivery regression** (fundamental guardrail) → mitigation: `FocusedInputDelivery`
  is Out-of-Scope and untouched; only the overlay *display* updates progressively. Step 15 verify
  asserts `focused_input.ok=true` in the newest `release-latency.jsonl` after a streamed release.
- **`bytes(for:)` does not expose the `URLSessionDataTask`**, so the existing `activeTasks`
  registration pattern cannot cover streams → mitigation: Step 7 tracks the Swift `Task` instead and
  ties cancellation to `continuation.onTermination`.
- **Reasoning deployments with restricted streaming (e.g. Azure o3 limited-access)** could fail a
  streamed request → mitigation: `perform` (one-shot) is kept intact; the streaming method maps
  non-2xx to `auth/server` errors via the existing classification, surfaced through the standard
  `logOperatorFailure` path.
- **Silent-inert flag for non-streaming providers misread as a no-fallback violation** → mitigation:
  documented in Step 16 and the refined request — both flag and provider are present/valid; no
  missing-config substitution occurs.
- **Scan staleness:** none — scan commit `e70d4fb…` equals current `HEAD`.

## Acceptance Criteria Mapping
| Acceptance criterion (refined request) | Step(s) |
|---|---|
| 1. Streaming off ⇒ behavior byte-for-byte identical; existing tests pass | 1, 5, 9, 10, 11, 15 |
| 2. Flag/env/UI enable streaming; CLI > local `.env` > tool-agents `.env` > shell env | 2, 4, 5 |
| 3. Azure: `"stream": true`, incremental SSE, one-shot-equivalent final string | 7, 9, 11 |
| 4. Google: `:streamGenerateContent?alt=sse`, incremental SSE, one-shot-equivalent | 7, 10, 11 |
| 5. Composite: streamed progress, final fields only from complete response | 8, 10, 11 |
| 6. Overlay `finalizing` updates progressively; settles on final; off ⇒ as today | 14, 15 |
| 7. Focused-input insertion atomic on completion; `focused_input.ok=true` | 15 |
| 8. Push-to-talk press/release, audio gating, overlay transitions work on/off | 15 |
| 9. Error/shape/auth classification, diagnostics, failure logging, timing on stream path | 7, 9, 10, 11, 13 |
| 10. `swift build` succeeds; functions/design (and config guide if present) updated | 16 |

## Deviation Rules for Executors
- **Auto-fix and document** bugs or blockers you hit mid-step (compile errors, wrong line offsets,
  pre-existing breakage); record what you changed and why in your report.
- **Add missing security/correctness essentials** (e.g. status-before-body validation, cancellation
  of in-flight streams, escape handling in the partial-JSON scanner) and document them.
- **STOP and surface** anything architectural — changing `perform`'s signature, altering
  focused-input delivery, removing the one-shot path, restructuring the config precedence chain, or
  anything touching push-to-talk wiring beyond what a step authorizes. Do not proceed past it.
- **Log nice-to-haves instead of doing them** (e.g. `stream_options`/usage telemetry, a dedicated
  rate-limit failure kind, surrogate-pair fidelity in the partial preview): when running solo, append
  them directly to `Issues - Pending Items.md`; when running as one of several parallel executors,
  put them in your final report — never edit `Issues - Pending Items.md` directly (the orchestrator
  appends parallel-executor entries after the phase).
- **Config rule:** introduce no required config; the streaming toggle is optional with a documented
  default of off and is silently inert for non-`azure-openai`/`google` providers — this is not a
  fallback substitution. Do not add a fallback for any genuinely required setting.

## Verification
- `swift build` succeeds at every step boundary.
- `swift test` passes — including the new config/UI tests (Step 5) and the new refiner/transport
  streaming tests (Step 11) — with all pre-existing `UntypeCoreTests` unchanged and green.
- Manual smoke checks (Step 15), which cannot be automated due to macOS permission/overlay behavior:
  (a) streaming ON — push-to-talk release into a focused text field shows progressive overlay text,
  settles on the final text, and the newest `~/.tool-agents/untype/release-latency.jsonl` record has
  `focused_input.ok=true`; (b) streaming OFF — overlay and delivery behave exactly as today; (c)
  push-to-talk press/release, audio gating, and recording/finalizing transitions work in both modes.
- No lint command is configured (`lint_command: null` in the scan frontmatter); none is run.
