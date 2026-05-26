# Refined Request: Configurable Application Prompts

## Category
Development, Configuration

## Objective
Make every prompt used by the Swift `untype` application configurable from the application configuration folder at application startup, so users can tune prompt wording for better output quality or performance without rebuilding the application.

## Scope
In scope:
- Load prompt text from the application configuration folder, currently `~/.tool-agents/untype/`, during configuration resolution / application startup.
- Include all prompt surfaces currently used by the application:
  - LLM transcript refinement system prompt.
  - LLM translation system prompt.
  - Translation user prompt/template used when invoking the translator.
  - Realtime transcription provider context/prompt text where supported by provider integrations.
- Provide default prompt files or default prompt content for first-run / missing prompt-file behavior in a way that preserves existing behavior.
- Keep CLI and native UI startup paths using the same loaded prompt configuration.
- Add automated coverage for prompt loading, validation, default behavior, provider/refiner propagation, and request/payload construction.
- Update project design, functional requirements, configuration guide, and issue tracking as needed.

Out of scope:
- Adding new LLM providers.
- Adding a prompt editor UI unless already required by the existing configuration surface.
- Persisting transcript text, processed text, secrets, provider payloads, or user prompt contents in diagnostics/logging.
- Changing the semantic behavior of protocol operators beyond replacing hardcoded prompt strings with startup-loaded configurable values.

## Requirements
- The application MUST read prompt configuration at startup from `~/.tool-agents/untype/` or a dedicated prompt subdirectory under that folder.
- Prompt files MUST be user-editable plain-text files.
- Missing required prompt configuration MUST NOT silently use an undocumented fallback; any built-in default behavior must be explicit and documented as default prompt provisioning or default prompt content.
- Startup loading MUST preserve the current built-in behavior when users have not customized prompts.
- Invalid prompt files, such as empty files where prompt text is required, MUST raise a typed configuration error with the affected prompt path/name.
- Loaded prompts MUST flow through `ResolvedConfig` into:
  - `LLMRefinerFactory.makeRefiner`.
  - `LLMRefinerFactory.makeTranslator`.
  - `VoiceAgentProtocolController` translation prompt construction.
  - Soniox / ElevenLabs transcription adapters if provider prompt/context support is implemented.
- Verbose diagnostics and release-latency logs MUST NOT include prompt contents.
- Tests MUST verify that Azure OpenAI and Google requests use configured refinement/translation prompt text.
- Tests MUST verify that transcription provider payloads include configured transcription prompt/context only when supported and configured.

## Constraints
- Use Swift and the existing SwiftPM structure.
- Do not add runtime dependencies unless absolutely necessary and vetted first.
- Preserve existing configuration precedence and no-secret-persistence rules.
- Do not perform version-control operations.
- Preserve existing user changes in the dirty worktree.
- New prompt files created as project artifacts must live under a root-level `prompts/` folder with sequential prefixes.
- User-editable runtime prompt files must live under the application configuration folder.

## Acceptance Criteria
- `swift test` passes.
- A fresh startup with no customized prompt files preserves the current refinement and translation behavior.
- A startup with edited prompt files under `~/.tool-agents/untype/` uses those exact prompt values for subsequent runtime sessions.
- Both CLI and `untype ui` sessions consume the same prompt configuration.
- Empty or unreadable required prompt files fail with `invalid_configuration` or another typed configuration error before a runtime session starts.
- The configuration guide documents every prompt file name, purpose, default content/provisioning behavior, location, and safe editing guidance.
- `docs/design/project-design.md` and `docs/design/project-functions.md` record the new configurable-prompt behavior.

## Assumptions
- The active project root is `~/aiwork/coding-platform/untype-s`.
- The application configuration folder remains `~/.tool-agents/untype/`.
- “Refinement prompts” refers to the LLM cleanup prompt used by Azure OpenAI / Google refinement.
- “Transcription prompts” refers to provider-side prompt/context text intended to bias realtime STT recognition where supported by Soniox and/or ElevenLabs.
- “All prompts used by the application” includes the translation system prompt and translation user prompt/template because they are LLM prompts even though the user named refinement and transcription specifically.

## Open Questions
- Should prompt files be auto-created in `~/.tool-agents/untype/` on first startup, or should the app ship documented default prompt templates and fail only when a user-created override file is empty/invalid?
- Should provider-specific transcription prompt files be separate (`soniox-transcription-context`, `elevenlabs-transcription-context`) or should there be one shared transcription prompt with provider adapters deciding whether/how to use it?

## Original Request
> Can you make the prompts used for refinement and transcription configurable and have them read from the application's configuration folder at application startup?
> The goal is for the user to be able to modify the prompts in order to improve the result or the performance of the application.
> For this reason, we want all the prompts used by the application to be included.
