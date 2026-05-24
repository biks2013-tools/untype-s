# Refined Request: Swift Drop-In Replacement for untype

## Category
Development

## Objective
Create a Swift implementation in `~/aiwork/coding-platform/untype-s` that serves as a drop-in replacement for the existing TypeScript `untype` project at `~/aiwork/coding-platform/untype`, preserving the user-facing command behavior, configuration contract, transcription pipeline, voice-agent protocol, macOS integration, and documented operational semantics while replacing the TypeScript/Node/Electron implementation with Swift-native code where feasible. The work must be broken into autonomous, context-preserving agent-sized phases with durable documentation artifacts so downstream implementation can proceed without relying on transient conversation memory.

## Scope
- **In scope**:
  - Study the source TypeScript project at `~/aiwork/coding-platform/untype`, including its README, design documents, functional requirements, source modules, tests, tools documentation, and pending issues.
  - Build the replacement under the active project root `~/aiwork/coding-platform/untype-s`.
  - Preserve the installed user-facing command contract for `untype`, including `untype`, `untype --help`, `untype --version`, existing CLI flags, exit-code behavior, stdout/stderr separation, and pipe-safe output behavior.
  - Preserve the documented configuration model: CLI flags, local `.env`, per-user `~/.tool-agents/untype/.env`, shell environment, explicit precedence, credential expiry warnings, typed validation, and no fallback values for missing required configuration.
  - Preserve supported realtime STT provider behavior for Soniox and ElevenLabs, including provider-specific validation, realtime streaming, partial/final transcript handling, endpoint/commit behavior, and typed auth/network/protocol errors.
  - Preserve the transcription rendering modes and behavior: `overwrite`, `append`, `final-only`, TTY-aware overwrite handling, non-TTY auto-downgrade to append, duplicate partial suppression, and marker-token filtering.
  - Preserve turn detection, LLM refinement/translation behavior, supported LLM provider configuration surface, fail-open runtime LLM handling, and fatal startup validation for missing required LLM configuration.
  - Preserve the voice-agent command protocol, including spoken command markers, persistent operator state, JSONL protocol events, section submission/cancellation/status behavior, clipboard copy, focused-input delivery, and remembered non-secret protocol settings.
  - Preserve macOS-specific behavior, including microphone capture, microphone permission handling, focused-input delivery, push-to-talk/hotkey behavior, and any required native permission diagnostics.
  - Provide a Swift-native equivalent for the current UI command behavior (`untype ui`) or explicitly document any justified deviation discovered during investigation before implementation begins.
  - Create and maintain downstream planning/design documentation under `docs/design/`, reference material under `docs/reference/`, functional requirements under `docs/design/project-functions.md` or the project-required equivalent, and pending issue tracking in `Issues - Pending Items.md`.
  - Decompose implementation into autonomous agent work packages with clear inputs, outputs, handoff artifacts, and verification criteria to preserve memory context across phases.
  - Add tests and validation scripts appropriate to the Swift implementation, placing standalone test scripts under `test_scripts/` when scripts are needed.
- **Out of scope**:
  - Changing the public tool identity, command name, config folder, or environment-variable namespace unless the user explicitly approves the change.
  - Replacing Soniox, ElevenLabs, Azure OpenAI, Google Gemini, or other provider contracts with different external services unless a later investigation recommends and the user approves it.
  - Creating undocumented fallback configuration values or placeholder credentials.
  - Performing version-control operations such as commits, resets, checkouts, or branch management unless explicitly requested.
  - Expanding platform support beyond the behavior already promised by the source project, except where Swift/macOS replacement work requires equivalent native macOS implementation.
  - Shipping a reduced MVP that omits source-project features without documenting the omission as a phased milestone and receiving approval before implementation.

## Requirements
1. The implementation team MUST treat `~/aiwork/coding-platform/untype` as the behavioral source of truth until a specific requirement is superseded by a later approved project artifact.
2. The implementation MUST produce a Swift-based project in `~/aiwork/coding-platform/untype-s` using Swift Package Manager unless a downstream investigation identifies a stronger project-compatible reason to use another Swift build structure.
3. The replacement MUST expose an installed executable named `untype` with the same end-user invocation semantics as the TypeScript project.
4. `untype --help` MUST document every supported command, subcommand, flag, environment-variable alias, and at least one usage example with behavior equivalent to the source project.
5. `untype --version` MUST return the replacement project's semantic version and exit with code `0`.
6. Missing required configuration MUST raise typed errors with deterministic non-zero exit codes and actionable messages; the implementation MUST NOT substitute fallback values for missing required settings.
7. The configuration resolver MUST implement the source project's documented precedence order: CLI flag, current working directory `.env`, `~/.tool-agents/untype/.env`, then shell environment.
8. The Swift implementation MUST preserve stdout/stderr separation: transcript or JSONL protocol output belongs on stdout according to the selected interaction mode, while readiness, diagnostics, warnings, and errors belong on stderr unless the UI mode owns presentation.
9. The microphone capture path MUST support macOS default microphone recording with equivalent audio format behavior for the selected provider and must surface missing tooling, permission denial, unsupported platform, and capture failures as typed errors.
10. The Soniox provider MUST support realtime audio streaming, configured endpoint/model/language/sample-rate/endpoint-detection values, partial/final transcript emission, marker filtering, repeated-prefix handling, graceful finalization, and typed provider error mapping equivalent to the TypeScript implementation.
11. The ElevenLabs provider MUST support the source project's realtime STT behavior, including provider-specific language restrictions, API-key configuration, partial/final transcript handling, commit/VAD behavior, and typed error mapping.
12. The renderer MUST support `overwrite`, `append`, and `final-only` modes with equivalent TTY/non-TTY behavior, duplicate partial suppression, wrapped-row cleanup, and final flushing semantics.
13. The tool MUST preserve graceful shutdown behavior for `SIGINT` and `SIGTERM`, including bounded finalization/draining of pending provider output and deterministic exit behavior.
14. The voice-agent protocol MUST preserve operator state, spoken marker matching, section lifecycle, JSONL event schema, monotonically increasing event sequence numbers, protocol warnings, remembered non-secret state, and stream separation.
15. LLM refinement and translation MUST preserve the configured provider surface, startup validation, fail-open runtime behavior, output rendering, and omission of secrets or transcript content from persisted settings.
16. Focused-input delivery MUST preserve privacy and permission behavior: processed text must not be passed through process arguments, persisted, or echoed in diagnostics; missing Accessibility permissions must produce explicit non-fatal warnings.
17. UI mode (`untype ui`) MUST provide feature parity for the source project's monitoring/configuration/push-to-talk workflow, including typed event-driven rendering, non-secret UI settings persistence, credential-status display without secret values, hotkey overlay behavior, protocol operator controls, and accessibility-aware macOS behavior, unless a later approved investigation scopes UI parity into a separate phase.
18. The downstream plan MUST divide the work into autonomous agent-sized phases such as source study, contract extraction, Swift architecture/design, provider implementation, protocol implementation, UI implementation, test migration, integration verification, and documentation sync.
19. Each autonomous phase MUST define its input artifacts, output artifacts, implementation boundaries, verification commands, and handoff notes so another agent can continue without relying on conversation memory.
20. The implementation MUST include automated tests for config parsing, provider adapters with mocked network surfaces, rendering behavior, protocol state machine behavior, persistence, error mapping, and CLI contract behavior.
21. Any live-provider or macOS-permission-dependent behavior that cannot be fully automated MUST be covered by documented manual smoke tests under `test_scripts/` or `docs/reference/`.
22. Runtime or build dependencies added to the Swift project MUST be vetted before adoption, and dependency decisions MUST be recorded according to the active project's dependency-vetting instructions.
23. Project documentation MUST be updated as the implementation evolves: design changes in `docs/design/project-design.md`, functional requirements in `docs/design/project-functions.md` or the project-required equivalent, and open defects or deferred items in `Issues - Pending Items.md`.
24. The final replacement MUST be validated against the source project's documented functional requirements and a compatibility checklist derived from the source README and design documents.

## Constraints
- The active project root is `~/aiwork/coding-platform/untype-s`.
- The source project to study is `~/aiwork/coding-platform/untype`.
- The request is for a Swift replacement of a TypeScript implementation; TypeScript may be studied for behavior but must not remain the primary implementation language of the replacement.
- The source project is macOS-oriented and currently depends on macOS microphone, focused-input, hotkey, and UI behavior; the Swift replacement must prioritize macOS parity.
- The active project instructions require refinement before downstream planning or implementation for this non-trivial, multi-step request.
- Downstream plans must live under `docs/design/` and use the `plan-xxx-<description>.md` naming pattern.
- Reference material must live under `docs/reference/`.
- Test scripts, when created, must live under `test_scripts/`.
- Configuration settings must not use hidden fallback values. Missing required settings must raise errors.
- No version-control operations may be performed unless explicitly requested by the user.
- Any new dependency must be vetted for security and suitability before being added.
- The implementation must not leak API keys, provider endpoints, transcript text, processed output, or protocol payloads into persisted UI/protocol state where the source project forbids it.

## Acceptance Criteria
1. A source-study artifact exists under `docs/reference/` summarizing the TypeScript project modules, CLI contract, provider contracts, UI behavior, tests, and pending issues that affect the Swift replacement.
2. A downstream implementation plan exists under `docs/design/plan-xxx-<description>.md` and references this refined request file by absolute path.
3. The plan decomposes the work into autonomous agent-sized phases with explicit inputs, outputs, handoff artifacts, verification steps, and dependency ordering.
4. The active project contains a Swift build structure that can be built with the documented command, expected to be `swift build` unless later design documents justify another command.
5. The built executable can be installed or symlinked as `untype` and supports `--help` and `--version` with exit code `0`.
6. A compatibility checklist derived from the source project README and functional requirements is present under `docs/reference/` and is used by downstream verification.
7. Automated tests pass for configuration precedence, missing/invalid configuration errors, rendering modes, protocol state transitions, JSONL event structure, provider adapter error mapping, and persistence behavior.
8. The replacement passes CLI contract smoke tests for help, version, missing configuration, non-TTY output behavior, and deterministic exit-code mapping.
9. Mocked provider tests demonstrate that Soniox and ElevenLabs adapters emit partial/final transcripts and typed errors according to the source contract.
10. Manual smoke-test instructions exist for real microphone capture, real Soniox and ElevenLabs sessions, macOS microphone permissions, focused input, push-to-talk, overlay behavior, and UI mode.
11. Documentation in `docs/design/project-design.md` and `docs/design/project-functions.md` or the project-required equivalent reflects the Swift architecture and preserved functional requirements.
12. `Issues - Pending Items.md` exists and records any deferred parity gaps, live-verification gaps, dependency vetting notes, or unresolved discrepancies discovered during source study or implementation.
13. No required source-project behavior is silently omitted; every unsupported or deferred behavior is documented as an open issue or phased milestone with rationale.
14. The final verification report states whether the Swift implementation is a drop-in replacement for the TypeScript project and lists any remaining blockers before replacing the TypeScript `untype` command in normal use.

## Assumptions
- **Drop-in replacement means public-behavior parity**: Based on the phrase "drop in replacement," the Swift project is expected to preserve user-facing CLI, config, provider, protocol, UI, and persistence behavior, not merely reproduce the core transcription loop.
- **The executable remains named `untype`**: The source project documents `untype` as the supported OS command, so the replacement should install under the same command name even though the active folder is named `untype-s`.
- **Swift Package Manager is acceptable**: The request specifies Swift but does not specify Xcode, SwiftPM, or another build system; SwiftPM is the default assumption for a command-line Swift project.
- **macOS is the primary target**: The source project is macOS-only for microphone and native integration behavior, so cross-platform parity is not assumed unless later requested.
- **UI parity is required unless explicitly phased out**: The source project exposes `untype ui`, so a true drop-in replacement includes an equivalent UI command unless a later investigation and user decision split it into a separate milestone.
- **"spane" means "span" or "split across"**: The raw request appears to contain a typo; it is interpreted as a requirement to break steps and actions into autonomous agents to preserve context.
- **Autonomous agents are a workflow constraint, not runtime functionality**: The request is interpreted as asking the development process to be split into autonomous agent work packages, not asking the delivered Swift tool to spawn AI agents at runtime.

## Open Questions
- Should `untype ui` be implemented as a Swift-native macOS UI in the first replacement milestone, or may UI parity be delivered after the CLI/protocol replacement is complete?
- Should the Swift replacement intentionally preserve every partially implemented or stubbed provider behavior from the TypeScript project, including currently accepted-but-not-implemented LLM providers, or should those providers be implemented fully during the Swift port?
- What level of binary/package distribution is required for "drop-in": local symlink/install only, Homebrew formula, signed/notarized macOS app bundle for UI mode, or another distribution target?

## Original Request
"I want you to study the ../untype project and create a drop in replacement of the implementation in swift instead of typescript. I want you to spane the steps and actions in autonomous agents to preserve the memory context"
