---
language: swift
framework: none
package_manager: swiftpm
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/untype-input-helper/main.swift
last_scanned_commit: 55cb82bbfdaf34dee8e9307f867361146c287ea6
scanned_for_request: refined-request-composite-refine-translate-prompt.md
scanned_at: 2026-05-26T21:39:43Z
---

# Codebase Scan — untype-s

## 1. Project Overview
This is a single Swift Package Manager project targeting macOS 14 with one shared library target (`UntypeCore`) and two executables (`untype` and `untype-input-helper`). The core package already covers configuration resolution, prompt provisioning, LLM-backed refinement/translation, protocol routing, runtime wiring, UI launch, and focused-input delivery.

The composite refine-plus-translate request lands inside an already-established prompt/config/runtime pipeline, but the current implementation still performs separate refinement and translation passes. There is no composite prompt asset or composite request path yet.

## 2. Module Map
| Path | Purpose | Representative symbols |
| --- | --- | --- |
| `Sources/UntypeCore` | Main library module for config loading, prompt provisioning, LLM clients, protocol state/routing, runtime factory wiring, transcript rendering, UI helpers, and persistence. | `PromptConfig`, `ConfigResolver`, `LLMRefinerFactory`, `VoiceAgentProtocolController`, `UntypeRuntimeFactory` |
| `Sources/untype` | CLI entry point that boots `UntypeCommand` or the native UI launcher when invoked with `ui`. | `UntypeExecutable`, `UntypeCommand`, `NativeUntypeUILauncher` |
| `Sources/untype-input-helper` | Small helper executable for focused-input delivery diagnostics and text injection. | `FocusedInputHelperMain`, `FocusedInputHelperCommand`, `FocusedInputHelperRunResult` |
| `Tests/UntypeCoreTests` | Existing unit/integration coverage for config resolution, prompt provisioning, provider request construction, protocol routing, runtime lifecycle, and UI settings. | `LLMRefinersTests`, `ProtocolControllerTests`, `UntypeCommandTests`, `TranscriptionSessionRuntimeTests` |

Entry points:
- `Sources/untype/main.swift` launches the CLI, dispatching `ui` to `NativeUntypeUILauncher` and all other invocations to `UntypeCommand`.
- `Sources/untype-input-helper/main.swift` reads stdin, forwards to `FocusedInputHelperMain`, prints the helper JSON result, and exits with the helper exit code.

## 3. Conventions
- Configuration precedence is already fixed as CLI flag -> `<cwd>/.env` -> `~/.tool-agents/untype/.env` -> shell environment, and the prompt folder is provisioned under `~/.tool-agents/untype/prompts/` at startup. Required prompt files fail startup if unreadable or empty. (`Sources/UntypeCore/EnvChain.swift:15-41`, `Sources/UntypeCore/ConfigResolver.swift:435-559`, `Sources/UntypeCore/UntypeCommand.swift:140-148`)
- The current prompt model is narrow: `PromptConfig` carries one refinement system prompt, one translation system prompt, one translation user template, plus STT-specific context fields. `UntypePromptDefaults.promptFiles` currently enumerates six numbered files (`001`-`006`). (`Sources/UntypeCore/PromptConfig.swift:3-51`)
- LLM requests are built in provider-specific refiners over a shared mockable `LLMHTTPClient` boundary. Azure OpenAI uses chat completions, Google Gemini uses `generateContent`, and unimplemented providers throw explicit startup configuration errors. (`Sources/UntypeCore/LLMRefiners.swift:35-395`)
- The protocol controller currently processes sections sequentially: refine first, then translate, then clipboard and focused-input delivery, and it writes a `section.processed` JSONL event with raw text, optional refined text, source/target language metadata, and final output text. (`Sources/UntypeCore/VoiceAgentProtocolController.swift:246-347`, `Sources/UntypeCore/ProtocolJsonlWriter.swift:13-121`)
- CLI and native UI share the same resolved config and runtime factory path. `UntypeCommand` defaults to `UntypeRuntimeFactory.make`, while the UI launcher calls `UntypeRuntimeFactory.makeForUI`, so any new composite prompt config must flow through both. (`Sources/UntypeCore/UntypeRuntimeFactory.swift:14-172`, `Sources/UntypeCore/NativeUntypeUILauncher.swift:504-526`, `Sources/UntypeCore/UntypeCommand.swift:19-41`)
- The current test style is small, deterministic, and mock-heavy: `Testing` assertions, in-memory outputs, and fake HTTP/runtime helpers. Prompt provisioning, provider request construction, controller routing, and command wiring already have focused coverage that can be extended rather than replaced. (`Tests/UntypeCoreTests/LLMRefinersTests.swift:5-182`, `Tests/UntypeCoreTests/ProtocolControllerTests.swift:20-218`, `Tests/UntypeCoreTests/UntypeCommandTests.swift:5-239`)

## 4. Integration Points
### In-Scope
- `Sources/UntypeCore/PromptConfig.swift:3-51` and `Sources/UntypeCore/ConfigResolver.swift:435-504` are the prompt provisioning seam. This is already partially implemented infrastructure: add a composite prompt asset, load it from `~/.tool-agents/untype/prompts/`, and validate it at startup alongside the existing numbered prompt files.
- `Sources/UntypeCore/LLMRefiners.swift:86-375` is the provider HTTP seam. Add a composite request builder/parser here, or in a sibling helper, so Azure OpenAI and Google Gemini continue to use the same mockable HTTP boundary while returning enough structure for both refined and translated output.
- `Sources/UntypeCore/VoiceAgentProtocolController.swift:246-347` is the operator routing seam. Add the `refine && translate` branch here so the controller can issue one composite LLM call, preserve raw/refined/output/language fields, and keep single-operator behavior unchanged.
- `Sources/UntypeCore/UntypeRuntimeFactory.swift:14-172`, `Sources/UntypeCore/NativeUntypeUILauncher.swift:504-526`, and `Sources/UntypeCore/UntypeCommand.swift:19-41` are the shared runtime wiring seams. Thread the composite prompt config through both CLI and UI launch paths so they stay behaviorally aligned.
- `Tests/UntypeCoreTests/LLMRefinersTests.swift`, `Tests/UntypeCoreTests/ProtocolControllerTests.swift`, `Tests/UntypeCoreTests/UntypeCommandTests.swift`, and `Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift` are the main test landing spots. Add request-count, routing, startup-validation, and CLI/UI parity coverage here.
- `docs/design/project-design.md`, `docs/design/project-functions.md`, and `docs/design/configuration-guide.md` are the required documentation touchpoints for the new composite prompt behavior and prompt-file surface.

### Out-of-Scope
- `Sources/UntypeCore/SonioxTranscriber.swift`, `Sources/UntypeCore/ElevenLabsTranscriber.swift`, and `Sources/UntypeCore/AVFoundationAudioSource.swift` are not part of the composite prompt feature; they remain STT/audio plumbing unless a regression forces a revisit.
- `Sources/UntypeCore/FocusedInputDelivery.swift` and `Sources/UntypeCore/MacOSClipboardWriter.swift` are not part of the prompt or LLM request path; they only matter if downstream tests reveal an unrelated operator regression.
- `Sources/UntypeCore/ProtocolSettingsStore.swift` and `Sources/UntypeCore/ReleaseLatencyLogger.swift` already enforce privacy-safe persistence boundaries and should stay unchanged unless a test proves the composite feature leaks data into those stores.
- `Sources/UntypeCore/ProtocolStateMachine.swift` is not the composite prompt implementation site; it already decides when `refine` and `translate` are active and should stay focused on marker parsing and operator state.

### New Integration Points
- `prompts/007-composite-refine-translate*.txt` and the corresponding `~/.tool-agents/untype/prompts/007-composite-refine-translate*.txt` file(s) are a new prompt asset surface. The repository currently has only the numbered prompt files `001`-`006`, so the composite prompt is additive.
- A composite request/response helper in `Sources/UntypeCore/LLMRefiners.swift` is a new integration point because the current refiner API only accepts a single input string and returns a single cleaned string.
- A composite prompt field or sibling config type in `Sources/UntypeCore/PromptConfig.swift` is a new integration point because the current config shape has no slot for a combined refine-plus-translate prompt contract.

## 5. Notes
- The feature itself is not implemented yet: the request path is still separate refine-then-translate, and no composite prompt asset exists in `prompts/`.
- The existing infrastructure is strong enough to extend: prompt provisioning, config precedence, mockable HTTP clients, and shared CLI/UI runtime wiring are already in place.
- The UI already labels a turn with both operators enabled as `refined + translated`, so the visible runtime vocabulary is ahead of the backend implementation.
