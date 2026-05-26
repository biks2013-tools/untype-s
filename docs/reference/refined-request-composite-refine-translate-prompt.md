# Refined Request: Composite Refine and Translate Prompt

## Category
Development

## Objective
Introduce a composite LLM prompt path for the Swift `untype` application so that when both the `refine` and `translate` protocol operators are enabled for the same submitted section, the application can produce both the refined text and translated output through one LLM request instead of executing separate refinement and translation requests. The feature must preserve the existing protocol behavior, configurable prompt model, fail-open runtime semantics, privacy boundaries, and CLI/UI parity while reducing operator latency for combined refine-plus-translate turns.

## Scope
- **In scope**:
  - Add a composite refine-plus-translate prompt surface to the existing configurable prompt system.
  - Ensure the composite prompt path is used only when both `refine` and `translate` are active for a submitted section and LLM processing is configured.
  - Preserve the existing separate refinement-only and translation-only behavior when only one of the two operators is active.
  - Preserve the current translation policy and target-language selection behavior.
  - Ensure the composite LLM call returns enough information for the protocol controller to keep recording raw text, refined text, detected/target language metadata, and final output text consistently with the current section-processing event model.
  - Keep CLI and native UI runtime paths behaviorally aligned.
  - Add automated tests for composite prompt loading, request construction, operator routing, protocol output, failure behavior, and no-extra-call behavior.
  - Update project design, functional requirements, configuration guide, and issue tracking as needed during implementation.
- **Out of scope**:
  - Adding new LLM providers.
  - Changing STT provider prompt/context behavior.
  - Adding a prompt editor UI.
  - Changing configuration precedence or introducing fallback configuration values.
  - Persisting prompt contents, transcript text, processed text, provider payloads, or secrets in diagnostics, logs, UI state, protocol settings, or release-latency records.
  - Replacing the existing separate refinement-only or translation-only prompt files.

## Requirements
1. The application MUST support a configurable composite prompt path for sections where both `refine` and `translate` are enabled.
2. The composite prompt configuration MUST include one system-level prompt plus user/instruction prompt content sufficient to express both the refinement operation and the translation operation in a single LLM request.
3. The composite prompt assets created in the project MUST live under the root-level `prompts/` folder and follow the existing sequential prefix convention.
4. Runtime user-editable composite prompt files MUST be provisioned and loaded through the existing `~/.tool-agents/untype/prompts/` startup prompt configuration mechanism.
5. Missing default composite prompt files MUST be handled consistently with the existing prompt provisioning behavior.
6. Empty or unreadable required composite prompt files MUST raise a typed configuration error before a runtime session starts.
7. The normal combined refine-plus-translate path MUST make exactly one LLM request for the section and MUST NOT make one request for refinement followed by another request for translation.
8. The composite path MUST preserve the existing translation policy behavior, including source-language detection and target-language selection.
9. The composite path MUST preserve the protocol section event model by recording:
   - the original raw text;
   - the refined text when the LLM response provides it;
   - the final translated output text;
   - source and target language metadata where the existing controller records them.
10. When only `refine` is enabled, the existing refinement-only path MUST continue to use the existing refinement prompt behavior.
11. When only `translate` is enabled, the existing translation-only path MUST continue to use the existing translation prompt behavior.
12. Runtime LLM failures in the composite path MUST remain fail-open and MUST NOT terminate transcription sessions.
13. Composite prompt contents, rendered prompt text, raw transcript text, refined text, translated text, secrets, and provider payloads MUST remain excluded from diagnostics, release-latency logs, persisted UI state, protocol settings, and issue logs.
14. Azure OpenAI and Google Gemini request construction MUST both support the composite path through the existing mockable LLM HTTP boundary.
15. Existing accepted-but-unimplemented LLM provider stubs MUST remain explicit startup configuration failures when selected.
16. The implementation MUST add focused automated coverage under the existing Swift test suite for prompt configuration, LLM request construction, protocol-controller routing, failure handling, and CLI/UI runtime factory wiring.

## Constraints
- The active project root is `~/aiwork/coding-platform/untype-s`.
- The project is a Swift Package Manager application targeting macOS 14 or newer.
- Existing build and test entry points are `swift build` and `swift test`.
- The existing LLM provider implementation surface is Azure OpenAI and Google Gemini; other configured providers remain accepted-but-unimplemented stubs.
- The existing configuration precedence chain must remain unchanged: CLI flag, `<cwd>/.env`, `~/.tool-agents/untype/.env`, then shell environment.
- Required missing configuration must raise typed errors; the project must not introduce fallback configuration settings.
- New runtime dependencies should not be added unless absolutely necessary and dependency-vetted first.
- New prompt project artifacts must be placed under `prompts/` with sequential names.
- User-editable runtime prompt files must live under `~/.tool-agents/untype/prompts/`.
- No version-control operations are part of this request.

## Acceptance Criteria
1. `swift test` passes after implementation.
2. With both `refine` and `translate` enabled, a submitted section causes exactly one LLM HTTP request on the normal success path for both Azure OpenAI and Google Gemini.
3. With only `refine` enabled, the existing refinement-only behavior and prompt usage are preserved.
4. With only `translate` enabled, the existing translation-only behavior and prompt usage are preserved.
5. A combined refine-plus-translate response produces a protocol processed-section record that includes raw text, refined text, final output text, and language metadata consistent with existing expectations.
6. CLI runtime sessions and `untype ui` runtime sessions both use the same composite prompt configuration.
7. Edited composite prompt files under `~/.tool-agents/untype/prompts/` are reflected in subsequent composite LLM requests after startup.
8. Empty or unreadable required composite prompt files fail startup with a typed configuration error that identifies the affected prompt file.
9. Composite LLM failures are reported through existing fail-open warning/diagnostic paths and do not terminate the transcription session.
10. Diagnostics, release-latency logs, UI state, protocol settings, and transcript/event exports do not persist prompt contents, rendered prompts, provider payloads, secrets, raw transcript text beyond existing explicit transcript surfaces, or processed text beyond existing explicit transcript/history/export surfaces.
11. `docs/design/project-design.md`, `docs/design/project-functions.md`, and `docs/design/configuration-guide.md` are updated to describe the composite prompt behavior and configuration surface.

## Assumptions
- The composite path should be activated by runtime operator state, not by a separate user-facing mode toggle, because the user asked for this behavior specifically when refine and translate are used together.
- The normal combined path should not fall back to two sequential LLM calls after a composite-call failure, because the stated goal is that only a single LLM call is made when both operations are requested.
- If the composite call fails, the runtime should preserve current fail-open semantics and continue with the best available text rather than terminating the session.
- The composite prompt should be part of the existing configurable prompt system rather than hardcoded in source, because FR-23 already requires application prompts to be startup-loaded from `~/.tool-agents/untype/prompts/`.
- The downstream implementation may choose the exact response format for the composite LLM output, provided it can be parsed reliably and supports the required protocol fields.

## Open Questions
- Should a composite-call failure output the original raw text only, or should it attempt to preserve any parseable partial refined/translated content from a malformed response?
- Should the composite prompt be represented as one combined user-template file or as separate refinement-instruction and translation-instruction template files under the shared composite system prompt?

## Original Request
"Can you also introduce a composite prompt that will work when we have both refine and translate together? In this case we will have one system prompt and one prompt for refinement and one for translation, so that only a single call is made to the LLM instead of two, and both the translation and the refinement are served faster."
