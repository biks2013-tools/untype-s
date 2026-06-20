# Code Review — Optional Configurable LLM Response Streaming (plan/design-034)

- Date: 2026-06-20
- Reviewer: senior code-review phase
- Request: "implement this streaming approach as a configurable feature to allow user to choose it optionally"
- Provenance: refined-request-llm-streaming-toggle.md → design-034 → plan-034 → codebase-scan-llm-streaming-toggle.md
- Verdict: **approved**

## Files Reviewed

Source (all conform to git-status scope; no unexpected discrepancies):
- `Sources/UntypeCore/ResolvedConfig.swift` — `LLMConfig.streamingEnabled` (C1)
- `Sources/UntypeCore/ConfigResolver.swift` — flag resolution + `switches` registration
- `Sources/UntypeCore/UntypeCommand.swift` — help text
- `Sources/UntypeCore/UntypeUISettings.swift` — UI toggle + patch + `sessionArguments()` emission
- `Sources/UntypeCore/LLMRefiners.swift` — streaming transport, provider refiners, partial-JSON extractor, `StreamingTextRefining`
- `Sources/UntypeCore/VoiceAgentProtocolController.swift` — controller wiring + progress handler
- `Sources/UntypeCore/ProtocolJsonlWriter.swift` — `ProtocolEvent.streamingProgress`
- `Sources/UntypeCore/UntypeRuntimeFactory.swift` — `makeForUI(... streamingProgress:)`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift` — overlay sink
- Tests: `LLMRefinersTests.swift`, `UntypeCommandTests.swift`, `UntypeUISettingsTests.swift`

`git status --porcelain` matched the expected set. Non-source changes (`docs/...`, `.serena/`, `Issues - Pending Items.md`, `workflow-checkpoint.json`) are workflow-owned/expected. `docs/design/configuration-guide.md` was also updated (doc-only, consistent with Unit E scope). No unexplained discrepancy found.

## Semantic Verification

- `mcp__cclsp__get_diagnostics`: cclsp has no Swift LSP configured (errored on every file); fell back to Serena's LSP-backed diagnostics.
- `mcp__serena__get_diagnostics_for_file` (min_severity=2, Error+Warning) on ALL nine modified source files: **clean ({} — zero errors/warnings) for every file.**
- `mcp__serena__get_symbols_overview` / file reads confirmed structure matches the design contracts (C1–C7).
- Call-chain integrity: `swift build` (exit 0) and the full `swift test` (203 tests) both compile, which proves every existing caller of `LLMConfig.init`, `VoiceAgentProtocolController.init`, `UntypeRuntimeFactory.makeForUI`, `ProtocolEvent`, `LLMHTTPClient`, `TextRefining`, and `CompositeRefineTranslating` stayed valid — the additive trailing-default params and protocol defaults kept all callers source-compatible. (Serena initializer-reference lookups returned empty, a known Swift-LSP limitation for `init` call sites; the compiler is authoritative here.)

## Quality Verification — Acceptance Criteria & Guardrails

All BINDING acceptance criteria (refined request + resolved open questions) verified:

- **Off-by-default toggle** — CLI `--llm-streaming`/`--no-llm-streaming` (ConfigResolver `switches` dict, mirroring `--quick-close`), env `UNTYPE_LLM_STREAMING` via the four-tier chain, UI toggle emitted by `sessionArguments()` (line 215). Precedence CLI > env > default-false confirmed in code (ConfigResolver:376-382) and by tests `llmStreamingFlagOverridesEnvironment`, `llmStreamingEnvOffIsHonored`, `llmStreamingDefaultsToOffWhenUnset`.
- **Both providers** — Azure adds `"stream": true`; Google targets `:streamGenerateContent?alt=sse` with byte-identical body. Tests `azureStreamingAccumulatesDeltasAndReportsGrowingProgress`, `googleStreamingAccumulatesPartsAndCompletesOnEOF`.
- **Composite strict-commit (Risk #1)** — `LLMCompositeRefineTranslator` drives `onProgress` from `partialStringValue(...)` (DISPLAY ONLY) but commits via the existing strict `parseResponse` over the COMPLETE response. Verified by `compositeStreamingDrivesPartialDisplayButCommitsStrictParse` (final `"Clean text."` ≠ mid-stream display `"Clean te"`). Partial JSON never reaches final fields.
- **Protocol + diagnostics progress** — `ProtocolEvent.streamingProgress` emitted from `makeStreamingProgressHandler` alongside the unchanged `sectionProcessed`; verbose diagnostic line written. (Resolved open question #4.)
- **Silently inert** — streaming overloads delegate to one-shot `refine(_:)` and never invoke `onProgress` when `streamingEnabled == false` or the refiner is not `StreamingTextRefining`. Tests `azureStreamingDelegatesToOneShotAndNeverCallsProgressWhenDisabled`, `compositeStreamingOffDelegatesToOneShotParse` (progressCalls == 0, uses non-streaming `perform`).

HARD guardrails:
- **(a) Atomic focused-input** — `processSection` inserts the strict final `current` exactly once via `focusedInputWriter(current)` (controller line 371); the streaming progress handler (lines 399-413) only forwards to the overlay sink, the protocol event, and diagnostics — it NEVER touches `focusedInputWriter`. PASS.
- **(b) Push-to-talk untouched** — `stopHotkeySession` / `stopSession` in `NativeUntypeUILauncher` retain the full hotkey/press/release/audio-gate/finalizing-show-hide wiring; the streaming sink is purely additive and hops to main via `dispatchToUI`. PASS.
- **(c) One-shot path byte-for-byte** — `perform`, `makeRequest(stream: false)`, `parseContent`, and `parseResponse` are unchanged; the non-streaming return value equals the one-shot equivalent. PASS.

Streaming correctness:
- SSE parsing strips `data:`, consumes `[DONE]` without yielding, treats Gemini EOF as completion.
- Status validated on the up-front `URLResponse` BEFORE body consumption; non-2xx drains body, `[401,403]→.auth` else `.server` (test `streamingNon2xxFromRealClientMapsAuthAndServerKinds`).
- `CancellationError` / `URLError.cancelled` finish the stream SILENTLY (test `urlSessionStreamCancellationFinishesSilently`).
- `activeStreamTasks` registry + `continuation.onTermination` + `cancelAll()` abort in-flight streams (the `dispose()→cancelAll()` teardown push-to-talk relies on is preserved).

Partial-JSON extractor (`partialStringValue`):
- Escape-aware (`\" \\ \/ \n \t \r \b \f`, complete `\uXXXX`, deferred incomplete `\uXXXX` at tail, dangling backslash). Bounds-safe: the `\uXXXX` branch guards `i + 4 < n` and slices `(i+1)...(i+4)` (no out-of-bounds read); unterminated string returns decoded-so-far. Display-only; never feeds the committed result. Tests `partialStringValueExtractsCompleteAndPartialValues`, `partialStringValueHandlesEscapesAndUnicode`.

Config compliance:
- No fallback for genuinely-missing required config. `streamingEnabled` is an OPTIONAL toggle with documented default `false` (sanctioned). `streamingEnabled` forwarded in BOTH `LLMRefinerFactory.makeTranslator` and `makeCompositeRefineTranslator` clones (verified — the known scan anomaly is correctly handled).

Concurrency / Sendable:
- New progress closures are `@Sendable`; the controller's handler captures `self` weakly; the overlay sink hops to main via `dispatchToUI`. The streaming Task registry is mutated under `NSLock`. No diagnostics flagged data races.

## Build & Test

- `swift build`: **exit 0** (clean).
- `swift test`: **203 tests, 1 failure** — only `sessionRuntimeSuppressesLatePartialsAfterFallbackSubmission()` (TranscriptionSessionRuntimeTests:511), the documented pre-existing flaky runtime-race. Re-ran in isolation: **passed (exit 0)**, confirming it is the known flake, NOT a regression. All streaming/config/UI tests pass.

## Issues Fixed

No code defects found; no code changes were required.

## Design Changes Made (sanctioned, Step 8b)

- **design-034 Contract C3** rewritten to document the as-implemented `StreamingTextRefining` cast mechanism: `TextRefining` is left UNCHANGED; `AzureOpenAIRefiner`/`GoogleRefiner` conform to a new narrow `public protocol StreamingTextRefining` in `LLMRefiners.swift`; the controller and composite dispatch via `as? StreamingTextRefining` with one-shot fallback. `CompositeRefineTranslating` retains its additive default-nil `onProgress` overload.
- **design-034 Decision 2** rewritten (marked CHANGED 2026-06-20) explaining WHY the original `TextRefining.refine(_:onProgress:)` protocol requirement was abandoned (source-fragile for existing/future conformers like `MockRefiner`; a default that routes streaming to one-shot gives a misleading streaming contract) and confirming net behavior matches C3's intent.
- **project-design.md** Design 034 section: dated 2026-06-20 code-review note mirroring the above; updated the refine-surface bullet and the unit-partition bullet to the `StreamingTextRefining` mechanism.
- **Issues - Pending Items.md**: refined the P2 deviation bullet to RESOLVED (design now documents the implemented mechanism). No duplicate items added.

Verified net behavior matches C3's intent: accumulated display text via `onProgress`, silently inert when off or non-conforming, strict final result committed.

## Remaining Concerns

- **Minor / non-blocking:** In `NativeUntypeUILauncher.stopHotkeySession` the synchronous `overlay?.hideAfterDelay()` (line 454) starts a 1.2s hide timer at release time; if a stream produces no progress within 1.2s the overlay could momentarily hide before the later `hideAfterDelay()` reschedule in `stopSession` (line 713). Each streaming `show()` re-displays and the final reschedule settles it, so the design intent (visible progressive updates settling on final text) holds in practice. Display-only; does not affect delivery or correctness. Not worth a code change.
- **Deferred (already tracked in P2):** the on-device manual smoke check (Plan Step 15) requires macOS Accessibility/Input-Monitoring permissions + overlay rendering and cannot run headless — confirm `focused_input.ok=true` in the newest `release-latency.jsonl` after a streamed release into a focused field. Reminder per the project guardrail: an unsigned `untype.app` redeploy silently revokes the Accessibility TCC grant.

## Verdict

**approved** — implementation faithfully realizes design-034/plan-034 and every binding acceptance criterion; all guardrails (atomic focused-input, push-to-talk, one-shot parity) preserved; build + full test suite green (sole failure is the known pre-existing flake); design docs reconciled with the sanctioned `StreamingTextRefining` deviation. The only outstanding item is the user-side on-device smoke check, already tracked in `Issues - Pending Items.md`.
