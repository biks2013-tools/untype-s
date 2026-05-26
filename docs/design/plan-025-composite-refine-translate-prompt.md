# Plan 025: Composite Refine and Translate Prompt

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-composite-refine-translate-prompt.md`
- Investigation: skipped - existing prompt/LLM/runtime conventions prescribe the approach.
- Technical research: skipped - no new technology or provider API is introduced.
- Codebase scan:
  - `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-composite-refine-translate-prompt.md`

## Objective
Use one LLM request when both protocol operators, `refine` and `translate`, are active for the same submitted section, while preserving existing refinement-only and translation-only behavior.

## Design
- Add three required composite prompt files to the configurable prompt system:
  - one composite system prompt;
  - one composite refinement prompt template;
  - one composite translation prompt template.
- Build the composite user prompt from the raw section text, the rendered refinement template, the rendered translation template, and the selected target language.
- Require the composite LLM response to be a JSON object with `refined_text` and `translated_text`.
- Route `refine + translate` sections through a composite LLM processor when one is configured; do not fall back to sequential refine then translate after a composite call fails.
- Keep separate single-operator paths unchanged.
- Wire the composite processor through the shared CLI and UI runtime factories so both execution modes use the same behavior.

## Files to Modify
- `prompts/007-composite-refine-translate-system.txt`
- `prompts/008-composite-refinement-template.txt`
- `prompts/009-composite-translation-template.txt`
- `Sources/UntypeCore/PromptConfig.swift`
- `Sources/UntypeCore/ConfigResolver.swift`
- `Sources/UntypeCore/LLMRefiners.swift`
- `Sources/UntypeCore/VoiceAgentProtocolController.swift`
- `Sources/UntypeCore/UntypeRuntimeFactory.swift`
- `Tests/UntypeCoreTests/LLMRefinersTests.swift`
- `Tests/UntypeCoreTests/ProtocolControllerTests.swift`
- `Tests/UntypeCoreTests/UntypeCommandTests.swift`
- `docs/design/configuration-guide.md`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Checks
- `swift test`
- Prompt provisioning tests cover the new composite files and required placeholders.
- LLM tests cover Azure OpenAI and Google Gemini composite request construction and JSON result parsing.
- Protocol-controller tests prove combined refine-plus-translate uses one composite call and does not call separate refiner/translator instances.
- Failure tests prove composite errors remain fail-open and do not trigger a sequential fallback.
