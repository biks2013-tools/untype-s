---
language: swift
framework: SwiftUI / AppKit (macOS native)
package_manager: swift-package-manager
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/untype-input-helper/main.swift
last_scanned_commit: e70d4fb37cd9222b8bb1db2f6680d66e4e4c4320
scanned_for_request: llm-streaming-toggle
scanned_at: "2026-06-20T10:00:00Z"
---

# Codebase Scan — untype-s

## 1. Project Overview

Swift Package Manager project targeting macOS 14+, producing two executables (`untype`, `untype-input-helper`) and one library (`UntypeCore`). The library contains all business logic: STT transcription (Soniox, ElevenLabs), LLM refinement/translation (Azure OpenAI, Google Gemini), a voice-command protocol state machine, a native SwiftUI/AppKit overlay UI, focused-input delivery, and release-latency logging. The single test target `UntypeCoreTests` uses the Swift Testing framework (`import Testing`, `@Test`, `#expect`). No SwiftLint or SwiftFormat config is present.

---

## 2. Module Map

| Path | Purpose | Representative Symbols |
|---|---|---|
| `Sources/UntypeCore/LLMRefiners.swift` | LLM HTTP layer and refiner implementations | `LLMHTTPClient`, `AzureOpenAIRefiner`, `GoogleRefiner`, `LLMCompositeRefineTranslator`, `LLMRefinerFactory` |
| `Sources/UntypeCore/VoiceAgentProtocolController.swift` | Orchestrates operators (refine/translate/clipboard/input) per submitted section | `VoiceAgentProtocolController`, `TextRefining`, `processSection` |
| `Sources/UntypeCore/ConfigResolver.swift` | Resolves all config from CLI flags → local `.env` → `~/.tool-agents/untype/.env` → shell env | `ConfigResolver.resolve(argv:)`, `ParsedArguments`, `resolveString`, `configuredSource`, `parseBoolean` |
| `Sources/UntypeCore/ResolvedConfig.swift` | Value types for all resolved config including `LLMConfig` | `LLMConfig`, `ResolvedConfig`, `ProviderConfig`, `ProtocolSettingSources` |
| `Sources/UntypeCore/UntypeCommand.swift` | CLI entry point; routes `ui` vs runtime; owns help text | `UntypeCommand`, `helpText` |
| `Sources/UntypeCore/UntypeUISettings.swift` | UI settings model, patch type, and `sessionArguments()` translation to CLI flags | `UntypeUISettings`, `UntypeUISettingsPatch`, `sessionArguments()`, `.default` |
| `Sources/UntypeCore/UntypeRuntimeFactory.swift` | Wires all components into `TranscriptionSessionRuntime`; two factory paths: CLI (`make`) and UI (`makeForUI`) | `UntypeRuntimeFactory.make`, `makeForUI`, `UITranscriptRenderer` |
| `Sources/UntypeCore/NativeUntypeUILauncher.swift` | 146 KB native SwiftUI/AppKit UI; push-to-talk model, overlay controller, transcript event handling | `UntypeUIModel`, `UntypeOverlayController`, `stopHotkeySession`, `handleTranscript` |
| `Sources/UntypeCore/TranscriptRenderer.swift` | CLI transcript output; implements `TranscriptRendering` | `TranscriptRenderer`, `TranscriptRendering`, `refined(_:)` |
| `Sources/UntypeCore/ProtocolJsonlWriter.swift` | Writes `ProtocolEvent` values as JSONL to any `TextOutput` | `JsonlProtocolWriter`, `ProtocolEvent` |
| `Sources/UntypeCore/ProtocolStateMachine.swift` | Voice-command state machine; produces `ProtocolAction` | `VoiceCommandStateMachine`, `ProtocolAction`, `OperatorKey` |
| `Sources/UntypeCore/ProtocolSettingsStore.swift` | Persists/loads operator settings between sessions | `ProtocolSettingsStore`, `ProtocolSettingsSnapshot` |
| `Sources/UntypeCore/TranscriptionSessionRuntime.swift` | Core runtime: audio source → STT transcriber → protocol controller lifecycle | `TranscriptionSessionRuntime`, `RuntimeTranscriber` |
| `Sources/UntypeCore/FocusedInputDelivery.swift` | Delivers text atomically to the focused macOS input control | `FocusedInputDelivery`, `FocusedInputDeliveryResult` |
| `Sources/UntypeCore/EnvChain.swift` | Builds the four-tier env-var chain | `EnvChain`, `EnvValue`, `EnvSource` |
| `Sources/UntypeCore/UntypeUITimeline.swift` | In-memory transcript timeline for the UI history pane | `UntypeUITimeline`, `commitProcessed`, `updatePartial` |
| `Sources/untype/main.swift` | Thin executable entry — instantiates `UntypeCommand` and calls `run` | — |
| `Sources/untype-input-helper/main.swift` | Separate privileged helper for in-process focused-input delivery | — |
| `Tests/UntypeCoreTests/` | 15 test files; Swift Testing framework (`@Test`, `#expect`) | `LLMRefinersTests`, `UntypeCommandTests`, `ProtocolControllerTests` |

---

## 3. Conventions

- **Import style and access control** (`LLMRefiners.swift:1`, `VoiceAgentProtocolController.swift:1`): named imports only (`import Foundation`); all public API is explicitly annotated `public`; private helpers live at file scope (free functions) rather than in extension namespaces. No `@_exported` or module-aliasing patterns.

- **Boolean flag resolution pattern** (`ConfigResolver.swift:169-178`, `ConfigResolver.swift:936-961`): switch pairs (`--quick-close` / `--no-quick-close`, `--endpoint-detection` / `--no-endpoint-detection`, `--release-latency-log` / `--no-release-latency-log`) are parsed in `ParsedArguments.init` as entries in a `switches: [String: Bool]` dict and retrieved via `switchValue(for:)`. The standalone `--refine` / `--no-refine` pair is special-cased into a dedicated `refineOverride: Bool?` property. Env-var booleans use `parseBoolean(_:flagName:envName:)` which accepts `true/false/yes/no/on/off/1/0` and returns `Bool?` (nil = not set). The `??` nil-coalescing then supplies the documented default. The new `--llm-streaming` / `--no-llm-streaming` pair should follow the `switches` dict pattern (or its own typed property analogous to `refineOverride`).

- **`configuredSource` / `ProtocolSettingSources` reporting** (`ConfigResolver.swift:337-342`): operator defaults report whether they were explicitly supplied via `configuredSource(flagValue:chain:envKey:)` which returns `.configured` if either the flag or env key was set, otherwise `.default`. The new streaming flag should follow this pattern for its own source reporting if surfaced in `ProtocolSettingSources`.

- **`LLMConfig` as the injection point for refiner options** (`ResolvedConfig.swift:41-77`, `LLMRefiners.swift:162-176`): every per-refiner option (`verbose`, `maxOutputTokens`, `reasoningEffort`, `requestTimeoutMs`, `systemPrompt`, `providerConfig`) is stored on `LLMConfig` and read by refiner constructors. `LLMRefinerFactory.makeTranslator` and `makeCompositeRefineTranslator` clone `LLMConfig` with a substituted `systemPrompt` — so a new `streamingEnabled: Bool` field on `LLMConfig` will automatically propagate to all three factory paths without additional plumbing.

- **`sessionArguments()` bridges UI settings to CLI flags** (`UntypeUISettings.swift:195-217`): `UntypeUISettings.sessionArguments()` produces the CLI argv used to start the CLI runtime from the UI. Every UI boolean toggle that also has a CLI counterpart must be emitted here (e.g. `normalized.llmEnabled ? "--refine" : "--no-refine"`). The new streaming toggle's UI field must be emitted as `"--llm-streaming"` / `"--no-llm-streaming"` in this function.

- **Test style** (`LLMRefinersTests.swift:1-30`, `UntypeCommandTests.swift:1-20`): Swift Testing macros (`@Test`, `#expect`, `#require`, `async throws`); fakes injected via `MockLLMHTTPClient` conforming to `LLMHTTPClient`; no XCTestCase classes. Tests are free functions decorated with `@Test`.

---

## 4. Integration Points

### In-Scope (files and symbols directly touched by this feature)

| File | Relevant Symbol(s) / Lines | Interaction with Streaming Feature |
|---|---|---|
| `Sources/UntypeCore/LLMRefiners.swift` | `LLMHTTPClient.perform(_:timeoutMs:)` (line 65); `URLSessionLLMHTTPClient` (line 73); `AzureOpenAIRefiner.makeRequest` (line 201), `refine` (line 178); `GoogleRefiner.makeRequest` (line 335), `refine` (line 312); `LLMCompositeRefineTranslator.refineAndTranslate` (line 441); `LLMRefinerFactory.make` (line 578) | Core change site. `LLMHTTPClient` needs a streaming-capable variant (e.g. `performStreaming(_:timeoutMs:onToken:)` using `URLSession.bytes(for:)`). `AzureOpenAIRefiner` gains `"stream": true` body flag + SSE parser; `GoogleRefiner` switches URL to `:streamGenerateContent?alt=sse` + SSE parser. Both must accumulate deltas, invoke a progress callback, and return the same final `String`. `LLMCompositeRefineTranslator` must define its streaming behavior (best-effort partial-JSON display; final result from complete response only). `LLMRefinerFactory.make` reads `LLMConfig.streamingEnabled` to construct streaming vs. non-streaming path. |
| `Sources/UntypeCore/ResolvedConfig.swift` | `LLMConfig` struct (line 41); `LLMConfig.init` (line 56) | Add `streamingEnabled: Bool` field with default `false`. Update all call sites in `LLMRefinerFactory` that clone `LLMConfig` (`makeTranslator`, `makeCompositeRefineTranslator`) to pass the field through. |
| `Sources/UntypeCore/ConfigResolver.swift` | `ParsedArguments.init` switch (line 926); `resolve(argv:)` — LLM block (line 368-416); `LLMConfig` construction (line 406-416) | Add `--llm-streaming` / `--no-llm-streaming` case to `ParsedArguments` switch (analogous to `refineOverride`, or as a `switches` entry). Resolve `UNTYPE_LLM_STREAMING` env var via `parseBoolean`. Default = `false`. Pass resolved value into `LLMConfig(streamingEnabled:)`. |
| `Sources/UntypeCore/UntypeCommand.swift` | `helpText` (line 94) | Add `--llm-streaming` / `--no-llm-streaming` to the help text block, following the `--quick-close` / `--no-quick-close` format. |
| `Sources/UntypeCore/UntypeUISettings.swift` | `UntypeUISettings` struct (line 3); `UntypeUISettings.default` (line 37); `UntypeUISettingsPatch` (line 253); `merged(_:)` (line 115); `sessionArguments()` (line 195) | Add `llmStreaming: Bool` property to both `UntypeUISettings` and `UntypeUISettingsPatch`. Default = `false` in `.default`. Wire through `merged(_:)` nil-coalescing pattern. Emit `"--llm-streaming"` / `"--no-llm-streaming"` in `sessionArguments()`. |
| `Sources/UntypeCore/UntypeRuntimeFactory.swift` | `make(config:stdout:stderr:stdoutIsTTY:)` (line 15); `makeForUI(config:audioGate:transcript:protocolOutput:diagnosticsOutput:eventSink:focusedInputPreparation:)` (line 104) | No structural change needed — `LLMConfig` (with `streamingEnabled`) flows through `LLMRefinerFactory.make*` calls at lines 34-42 and 126-133. If a streaming progress callback must be passed to `VoiceAgentProtocolController`, this factory is where it is wired (e.g. an overlay-update closure injected alongside `focusedInputWriter`). |
| `Sources/UntypeCore/VoiceAgentProtocolController.swift` | `processSection` (line 250); `compositeRefineTranslator!.refineAndTranslate` (line 268); `refiner!.refine` (line 293); `translator!.refine` (line 321); `writeProtocol(.sectionProcessed…)` (line 334) | If streaming progress callbacks are accepted by `TextRefining` / `CompositeRefineTranslating`, `processSection` must pass an overlay-update closure to the streaming call site. The `writeProtocol(.sectionProcessed…)` call at line 334 is the existing completion-time event — must remain intact. A new `ProtocolEvent` case (e.g. `.streamingProgress`) or inline diagnostic calls handle in-flight protocol/diagnostics events per the resolved open question 4. |
| `Sources/UntypeCore/NativeUntypeUILauncher.swift` | `stopHotkeySession` (line 442); `overlay?.show(phase: "finalizing", text: latestTranscript)` (line 453); `UntypeOverlayController.show(phase:text:)` (line 2334); `handleTranscript(_:)` (line 830) | During `finalizing`, the overlay currently shows the raw transcript once via `overlay?.show(phase: "finalizing", text: latestTranscript)` at line 453. With streaming on, the overlay must be updated repeatedly as tokens arrive. A callback injected through `UntypeRuntimeFactory.makeForUI` can call `overlay?.show(phase: "finalizing", text: accumulatedTokens)` on each delta — `UntypeOverlayController.show` is already safe to call repeatedly (line 2334). The `hideAfterDelay()` call at line 454 must only fire after the stream completes. |
| `Sources/UntypeCore/ProtocolJsonlWriter.swift` | `ProtocolEvent` enum (line 8); `JsonlProtocolWriter.write(_:)` (line 38) | If streaming progress is emitted to the agent-protocol stream (resolved open question 4), a new `ProtocolEvent` case (e.g. `.streamingToken(sectionId: String, accumulatedText: String)`) is needed here, with its `jsonObject` computed property. The existing `sectionProcessed` case at line 14 is unchanged. |
| `Sources/UntypeCore/TranscriptRenderer.swift` | `TranscriptRendering.refined(_:)` (line 5); `TranscriptRenderer.refined(_:)` (line 85) | The streaming progress callback can call `renderer.refined(accumulatedText)` repeatedly for CLI mode. This already works — `TranscriptRenderer.refined` overwrites in-place in TTY/overwrite mode and appends otherwise. No structural change needed; the call pattern is additive. |
| `Tests/UntypeCoreTests/LLMRefinersTests.swift` | Full file | Must gain: (a) mock SSE streaming client tests for `AzureOpenAIRefiner` streaming path; (b) same for `GoogleRefiner`; (c) composite path partial-JSON display vs. final-parse tests; (d) error/shape/auth classification for streamed responses. |
| `Tests/UntypeCoreTests/UntypeCommandTests.swift` | Full file | Must gain: tests asserting `--llm-streaming` / `--no-llm-streaming` CLI flag resolves correctly at each config layer, and that `UNTYPE_LLM_STREAMING` env var is honoured at the correct priority. |
| `Tests/UntypeCoreTests/UntypeUISettingsTests.swift` | Full file | Must gain: tests for the new `llmStreaming` field in `UntypeUISettings`, `UntypeUISettingsPatch.merged`, and that `sessionArguments()` emits the correct flag. |

### Out-of-Scope (not touched by this feature)

| File / Module | Reason |
|---|---|
| `Sources/UntypeCore/TranscriptionSessionRuntime.swift` | STT streaming path; audio gate / push-to-talk lifecycle. No change needed. |
| `Sources/UntypeCore/FocusedInputDelivery.swift` | Atomic delivery must remain unchanged (project guardrail). No modification allowed. |
| `Sources/UntypeCore/SonioxTranscriber.swift` | STT provider; out of feature scope. |
| `Sources/UntypeCore/ElevenLabsTranscriber.swift` | STT provider; out of feature scope. |
| `Sources/UntypeCore/ProtocolStateMachine.swift` | Operator state machine unchanged; streaming does not affect section submission/cancel logic. |
| `Sources/UntypeCore/ProtocolSettingsStore.swift` | Persisted operator snapshots unchanged; streaming toggle is not a per-section operator. |
| `Sources/UntypeCore/ReleaseLatencyLogger.swift` | Latency logging unchanged (timing to stream completion already captured in `processSection`). |
| `Sources/UntypeCore/MacOSClipboardWriter.swift` | Clipboard delivery unchanged and atomic. |
| `Sources/UntypeCore/AVFoundationAudioSource.swift` | Audio capture; unchanged. |
| `Sources/UntypeCore/UntypeUITimeline.swift` | UI history timeline; `commitProcessed` is called once after section completion, unchanged. |
| `Sources/UntypeCore/UntypeOverlayLayout.swift` | Overlay sizing/positioning; unchanged. |
| `Sources/UntypeCore/PromptConfig.swift` | Prompt file loading; unchanged. |
| `Sources/UntypeCore/EnvChain.swift` | Four-tier env chain; unchanged (consumed, not modified). |
| `Sources/UntypeCore/Dotenv.swift` | `.env` file parser; unchanged. |
| `Tests/UntypeCoreTests/ProtocolControllerTests.swift` | Existing tests must pass unchanged; no new protocol-controller tests required for streaming unless progress events are verified here. |
| `Tests/UntypeCoreTests/FocusedInputDeliveryTests.swift` | Unchanged — atomic delivery must not regress. |

### New Integration Points

| New element | Recommended landing location | Notes |
|---|---|---|
| `URLSession.bytes(for:)` streaming reader | `Sources/UntypeCore/LLMRefiners.swift` — new private method on `URLSessionLLMHTTPClient` or a new concrete type conforming to an extended `LLMHTTPClient` | Use the existing `sharedSession`; `AsyncBytes` iteration; must respect `timeoutInterval` and honour `cancelAll` cancellation via `Task.cancel()`. |
| SSE frame parser (both Azure and Google) | `Sources/UntypeCore/LLMRefiners.swift` — private free functions `parseAzureSSELine(_:)` and `parseGoogleSSELine(_:)` | No external dependency; parse `data: {...}` lines, ignore `[DONE]`, accumulate `choices[].delta.content` / `candidates[].content.parts[].text`. |
| Partial-JSON extractor for composite streaming display | `Sources/UntypeCore/LLMRefiners.swift` — private free function alongside existing `extractJSONObjectText` | Incrementally scan accumulated JSON string for `"refined_text"` / `"translated_text"` values using string scanning (not `JSONSerialization` on partial input). |
| `streamingEnabled: Bool` on `LLMConfig` | `Sources/UntypeCore/ResolvedConfig.swift` line 41 | Add as last field with default `false` in `init`. |
| `--llm-streaming` / `--no-llm-streaming` in `ParsedArguments` | `Sources/UntypeCore/ConfigResolver.swift` line 926 — add two `case` entries in the `switch arg` block, storing into a new `llmStreamingOverride: Bool?` or via the `switches` dict using key `"--llm-streaming"` | Mirror `--quick-close` / `--no-quick-close` switches-dict pattern. |
| `UNTYPE_LLM_STREAMING` env var resolution | `Sources/UntypeCore/ConfigResolver.swift` — immediately after the `refine` block (line 368-374) | Use `parsed.switchValue(for: "--llm-streaming") ?? parseBoolean(chain.get("UNTYPE_LLM_STREAMING")?.value, ...) ?? false`. |
| `llmStreaming: Bool` on `UntypeUISettings` / `UntypeUISettingsPatch` | `Sources/UntypeCore/UntypeUISettings.swift` — add after `llmModel` field in both structs | Default `false` in `.default`; emit in `sessionArguments()` as `normalized.llmStreaming ? "--llm-streaming" : "--no-llm-streaming"`. |
| Streaming progress callback parameter | `Sources/UntypeCore/VoiceAgentProtocolController.swift` — `processSection` call sites and/or `TextRefining.refine` / `CompositeRefineTranslating.refineAndTranslate` signatures | Either add an optional `onProgress: ((String) -> Void)?` parameter to `refine` / `refineAndTranslate`, or introduce parallel streaming-specific methods. Keep existing non-streaming signatures valid. |
| New `ProtocolEvent` case for streaming progress | `Sources/UntypeCore/ProtocolJsonlWriter.swift` | Add `.streamingToken(sectionId: String, accumulatedText: String)` (or similar) and its `jsonObject` serialization, alongside existing events. Emit from `processSection` inside the streaming progress callback per resolved open question 4. |

---

## 5. Notes

- **`ParsedArguments` uses a strict allow-list**: unrecognized `--` flags throw `UntypeError.invalidConfiguration("Unknown option: …")` (line 982-984). The new `--llm-streaming` / `--no-llm-streaming` flags MUST be added to the `switch` block before the default; omitting them will cause a config error at runtime rather than a silent ignore.

- **`UntypeUISettings.sessionArguments()` is the CLI-to-UI bridge**: the UI launcher starts a CLI runtime subprocess using the argv produced by this method. The `llmStreaming` field must be emitted here or the UI toggle will have no effect on the running runtime. Also note that `UntypeUISettings.hotkeyMonitorConfigurationChanged` guards against spurious hotkey-monitor resets on settings changes — the streaming field does not affect hotkey config, so no changes are needed there.

- **`LLMConfig` is cloned in `makeTranslator` and `makeCompositeRefineTranslator`**: both methods construct a fresh `LLMConfig` with a substituted `systemPrompt` (lines 536-547, 557-567). When `streamingEnabled` is added to `LLMConfig`, both cloning sites must forward the field, or it will silently be dropped for translator and composite paths.

- **No external streaming library is needed**: `URLSession.bytes(for:)` / `AsyncBytes` is available on macOS 12+ (project targets macOS 14+) and provides the SSE line-by-line iteration primitive. No new dependency must be added.
