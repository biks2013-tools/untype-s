# Plan 024: Configurable Prompts

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-configurable-prompts.md`
- Investigation: skipped — the project already has a prescribed configuration folder and resolver pattern.
- Technical research:
  - `~/aiwork/coding-platform/untype-s/docs/research/stt-prompt-context-fields.md`
- Codebase scan:
  - `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-configurable-prompts.md`

## Objective
Load every application prompt from the application configuration folder at startup while preserving current behavior for users who have not customized prompts.

## Design
- Add a `PromptConfig` value to `ResolvedConfig`.
- Provision and read user-editable prompt files under `~/.tool-agents/untype/prompts/`.
- Keep default prompt templates in root-level `prompts/` for project-level traceability.
- Treat refinement, translation system, and translation user-template prompts as required.
- Treat STT context/keyterm prompt files as optional and behavior-preserving when empty.
- Pass loaded prompts through the runtime factory to LLM refiners, protocol translation, and STT provider adapters.

## Files to Modify
- `Sources/UntypeCore/ResolvedConfig.swift`
- `Sources/UntypeCore/ConfigResolver.swift`
- `Sources/UntypeCore/LLMRefiners.swift`
- `Sources/UntypeCore/VoiceAgentProtocolController.swift`
- `Sources/UntypeCore/SonioxTranscriber.swift`
- `Sources/UntypeCore/ElevenLabsTranscriber.swift`
- `Sources/UntypeCore/UntypeRuntimeFactory.swift`
- `Sources/UntypeCore/UntypeCommand.swift`
- `Tests/UntypeCoreTests/UntypeCommandTests.swift`
- `Tests/UntypeCoreTests/LLMRefinersTests.swift`
- `Tests/UntypeCoreTests/SonioxTranscriberTests.swift`
- `Tests/UntypeCoreTests/ElevenLabsTranscriberTests.swift`
- `docs/design/configuration-guide.md`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Checks
- `swift test`
- Config tests prove prompt file provisioning, custom prompt loading, and invalid prompt rejection.
- LLM tests prove Azure OpenAI and Google receive configured prompt text.
- STT tests prove Soniox and ElevenLabs receive configured provider context only through supported provider fields.
