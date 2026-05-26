---
language: swift
framework: swiftui/appkit
package_manager: swiftpm
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/untype-input-helper/main.swift
last_scanned_commit: not_collected
request_file: docs/reference/refined-request-configurable-prompts.md
scan_scope: prompt configuration, LLM refiners, STT provider payloads, CLI/UI startup
generated_at: 2026-05-27T00:00:00+03:00
---

# Codebase Scan — Configurable Prompts

## Project Overview
`untype-s` is a SwiftPM macOS project with one shared `UntypeCore` target and two executable targets: `untype` and `untype-input-helper`. The relevant startup configuration path is centralized in `ConfigResolver`, and both CLI and native UI runtime construction flows receive `ResolvedConfig`.

## Module Map
| Path | Purpose | Representative symbols |
|---|---|---|
| `Sources/UntypeCore/ConfigResolver.swift` | Resolves CLI/env/default configuration into `ResolvedConfig`; owns config folder checks and required-setting validation. | `ConfigResolver.resolve`, `EnvChain`, `resolveString` |
| `Sources/UntypeCore/ResolvedConfig.swift` | Shared immutable configuration model passed to runtime factories, transcribers, LLM refiners, and UI settings. | `ResolvedConfig`, `LLMConfig`, `ProtocolRuntimeConfig` |
| `Sources/UntypeCore/LLMRefiners.swift` | Azure OpenAI and Google request construction plus LLM refiner/translator factory. | `AzureOpenAIRefiner`, `GoogleRefiner`, `LLMRefinerFactory.makeTranslator` |
| `Sources/UntypeCore/VoiceAgentProtocolController.swift` | Applies refine/translate operators and currently builds the translation user prompt inline. | `processSection`, `TextRefining.refine` |
| `Sources/UntypeCore/SonioxTranscriber.swift` | Soniox realtime startup config frame, binary audio send, and result parsing. | `SonioxTranscriberOptions`, `configFrame` |
| `Sources/UntypeCore/ElevenLabsTranscriber.swift` | ElevenLabs realtime URL construction, JSON audio frames, and result parsing. | `ElevenLabsTranscriberOptions`, `request(options:)`, `inputAudioChunk` |
| `Sources/UntypeCore/UntypeRuntimeFactory.swift` | Creates protocol controller, LLM refiner/translator, audio source, and selected STT transcriber for CLI/UI. | `makeRuntime`, `makeUIRuntime` |
| `Sources/UntypeCore/NativeUntypeUILauncher.swift` | Native UI startup and settings-to-session argument flow. | `ConfigResolver(requireProtocolOutputForHybrid: false).resolve` |
| `Tests/UntypeCoreTests` | Swift Testing coverage for configuration, refiners, transcribers, protocol controller, runtime, and UI settings. | `LLMRefinersTests`, `SonioxTranscriberTests`, `ElevenLabsTranscriberTests`, `UntypeCommandTests` |

## Conventions
- Configuration precedence is centralized and documented as CLI flag > local `.env` > `~/.tool-agents/untype/.env` > shell environment.
- Required configuration failures use typed `UntypeError.missingConfiguration` / `UntypeError.invalidConfiguration`.
- Runtime sessions should be built from `ResolvedConfig`; provider-specific options are derived from `ResolvedConfig` in transcriber option initializers.
- LLM request bodies are verified through mock HTTP clients and JSON request assertions.
- STT WebSocket payloads are verified through mock socket clients and decoded JSON assertions.
- Non-secret UI state is persisted separately; secrets, transcripts, processed text, provider payloads, and prompt contents should not be logged or persisted outside explicit user files.

## Integration Points
### In Scope
- `Sources/UntypeCore/ConfigResolver.swift`: add startup prompt-folder provisioning/loading, required prompt validation, and provider-specific prompt constraints.
- `Sources/UntypeCore/ResolvedConfig.swift`: add a prompt configuration value that can flow to all runtime consumers.
- `Sources/UntypeCore/LLMRefiners.swift`: replace the hardcoded translation system prompt with loaded config.
- `Sources/UntypeCore/VoiceAgentProtocolController.swift`: replace the inline translation user prompt template with loaded config.
- `Sources/UntypeCore/SonioxTranscriber.swift`: include non-empty Soniox transcription context in the startup config frame.
- `Sources/UntypeCore/ElevenLabsTranscriber.swift`: include ElevenLabs keyterms in the URL and `previous_text` in the first non-empty audio chunk.
- `Sources/UntypeCore/UntypeRuntimeFactory.swift`: pass loaded prompt config into the protocol controller, LLM factory, and STT provider options.
- `Tests/UntypeCoreTests/UntypeCommandTests.swift`: add config prompt-loading and validation coverage.
- `Tests/UntypeCoreTests/LLMRefinersTests.swift`: verify customized LLM prompt propagation into Azure and Google requests.
- `Tests/UntypeCoreTests/SonioxTranscriberTests.swift` and `Tests/UntypeCoreTests/ElevenLabsTranscriberTests.swift`: verify provider prompt/context payloads.
- `docs/design/configuration-guide.md`, `docs/design/project-design.md`, `docs/design/project-functions.md`, and `Issues - Pending Items.md`: document the new behavior and issue resolution.

### Out of Scope
- Adding new LLM providers.
- Adding a prompt editor UI.
- Persisting prompt contents in logs or release-latency records.
- Changing macOS microphone capture, focused-input delivery, or transcript renderer behavior.

### New Integration Points
- A new prompt config value type should live in `UntypeCore` and be readable from both config tests and runtime factory code.
- A runtime prompt folder under `~/.tool-agents/untype/prompts/` should hold the user-editable prompt files.
- Project prompt templates should live under root-level `prompts/` because project instructions require prompt artifacts to use that folder.

## Duplication Check
No existing configurable prompt loader exists in the Swift project. Current LLM prompts are hardcoded in `ConfigResolver.swift`, `LLMRefiners.swift`, and `VoiceAgentProtocolController.swift`; current STT provider adapters do not expose Soniox context or ElevenLabs keyterm/previous-text configuration.
