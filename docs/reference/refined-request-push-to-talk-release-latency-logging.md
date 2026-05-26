# Refined Request: Push-to-talk release latency logging

## Category
Development

## Objective
Add an opt-in, file-backed diagnostic logging capability that lets maintainers measure and analyze the elapsed time between a native UI push-to-talk release event and successful delivery of the resulting text to the currently active focused input control. The logging must be disabled unless explicitly enabled by configuration, must avoid recording transcript text or secrets, and must be documented so a future maintainer can enable the diagnostics, reproduce a push-to-talk run, collect the log file, and interpret the timing data.

## Scope
- **In scope**:
  - Add a configuration setting that enables or disables release-to-input latency logging.
  - Write latency diagnostics to a documented file when the setting is enabled.
  - Record privacy-safe timing markers for the push-to-talk release pipeline from release detection through focused-input delivery completion.
  - Capture enough structured timing data to identify whether latency is caused by provider finalization, Quick Close/fallback selection, protocol processing, refinement/translation, clipboard delivery, focused-input delivery, or UI/runtime scheduling.
  - Surface failure outcomes in the log when a released turn does not reach the active input control.
  - Preserve existing UI event log behavior while adding durable file logging for later analysis.
  - Document the configuration setting, log file location, log format, enable/disable procedure, and analysis workflow in the project documentation.
  - Add focused automated coverage for configuration parsing, disabled-by-default behavior, enabled log writing, privacy boundaries, and representative success/failure timing records.
  - Update manual smoke-test instructions so future sessions can verify and analyze push-to-talk release-to-input latency.
- **Out of scope**:
  - Changing the functional behavior of push-to-talk release submission, Quick Close, provider finalization, refinement/translation, clipboard delivery, or focused-input delivery except where needed to observe timing.
  - Adding new STT providers, LLM providers, output targets, or macOS input methods.
  - Persisting transcript text, processed text, provider payloads, API keys, provider endpoints containing secrets, clipboard contents, or target application text.
  - Replacing the existing UI event log or transcript/history views.
  - Creating a full log-analysis tool unless a later request explicitly asks for one.
  - Implementing code as part of this refinement step.

## Requirements
1. The downstream implementation MUST add an explicit configuration setting for enabling release-to-input latency logging, and the default behavior MUST leave the logging disabled.
2. The setting MUST follow the project's existing configuration conventions and precedence rules: CLI flag, current working directory `.env`, `~/.tool-agents/untype/.env`, then shell environment.
3. When latency logging is disabled, no latency log file MUST be created or appended solely because of push-to-talk release activity.
4. When latency logging is enabled, each push-to-talk release attempt MUST append a structured record to a documented file.
5. Each structured record MUST identify one logical push-to-talk turn without recording the dictated or processed text.
6. Each record MUST include a release timestamp and elapsed durations in milliseconds for the measurable stages available in the existing pipeline, including release detection, finalization request/wait, text-source selection, protocol processing, operator processing, focused-input delivery attempt, and focused-input delivery result.
7. Each record MUST indicate the text source used for submission, such as provider final text, Quick Close partial text, timeout fallback partial text, or no submitted text, without recording the text itself.
8. Each record MUST include privacy-safe outcome fields for focused-input delivery, such as success/failure, delivery method, error code, and whether Accessibility trust was required or missing.
9. If the application cannot directly verify visual appearance of text in the active control without reading or logging sensitive target contents, the log MUST define the end marker as the focused-input delivery path reporting success; any stronger verification must remain privacy-safe and explicitly documented.
10. Latency logs MUST NOT include transcript text, processed/refined/translated text, clipboard contents, API keys, raw provider payloads, LLM prompts/responses, host-specific permission snapshots beyond privacy-safe status/error codes, or target application document contents.
11. The logging path MUST be append-only for normal operation and resilient to repeated push-to-talk turns in the same UI session.
12. Logging failures MUST NOT crash an otherwise working transcription session; they MUST surface a privacy-safe diagnostic through the existing diagnostics/event path.
13. The downstream implementation MUST document how to enable the setting, where the log file is written, how to disable the setting, how to clear or archive the log file, and how to interpret the timing fields.
14. The downstream implementation MUST update the project design and functional requirements documentation if it changes the configuration surface, diagnostic behavior, or smoke-test workflow.
15. The downstream implementation MUST add or update tests for the smallest practical units of the feature, including disabled behavior, enabled structured log output, privacy filtering, and representative success/failure records.

## Constraints
- The project is a Swift Package Manager macOS application/CLI project; `swift build` and `swift test` remain the authoritative build and test commands.
- The feature must preserve the existing strict configuration model; missing required configuration values must raise typed errors and must not be replaced by fallback values.
- No new runtime dependency is expected for this feature. Any new dependency would require dependency vetting before adoption.
- Existing privacy guarantees remain binding: transcripts and processed output may be visible in approved in-memory UI surfaces or explicit user exports, but must not be written to diagnostic latency logs.
- Existing focused-input privacy behavior must remain intact: processed text must not pass through process arguments or diagnostic log lines.
- Existing push-to-talk behavior, including Quick Close enabled/disabled semantics, must remain functionally unchanged except for additional observability.
- Documentation updates should use existing project locations, including `docs/design/project-design.md`, `docs/design/project-functions.md`, and `test_scripts/ui-mode-smoke.md`; if a configuration guide is added or updated, it must live at `docs/design/configuration-guide.md`.
- No version-control operation may be performed unless explicitly requested by the user.

## Acceptance Criteria
1. With the new logging setting absent or disabled, push-to-talk release behavior is unchanged and no release-to-input latency log is written.
2. With the new logging setting enabled, a push-to-talk press/speak/release cycle that successfully inserts text into the active focused input control appends one structured log record for that turn.
3. The log record includes total elapsed time from push-to-talk release detection to focused-input delivery success, plus stage-level elapsed timings sufficient to distinguish provider finalization latency, protocol/operator processing latency, and focused-input delivery latency.
4. If focused-input delivery fails, the log record includes a privacy-safe failure outcome and error code rather than transcript text or target control contents.
5. Quick Close, provider-final, timeout-fallback, and no-text release outcomes are distinguishable in the log.
6. Automated tests verify disabled-by-default behavior, enabled log writing, structured timing field presence, and absence of transcript/processed text in the log.
7. `swift test` passes after the downstream implementation.
8. Project documentation explains the configuration setting, log file path, log format, enable/disable steps, and a repeatable analysis procedure for future maintainers.
9. Manual smoke-test documentation includes a push-to-talk release-to-input latency logging scenario using `untype ui` and a focused editable control.

## Assumptions
- The request targets native UI push-to-talk behavior because it mentions the push-to-talk button release and the active input control.
- "Appearance of the text in the active input control" is interpreted as the focused-input delivery path completing successfully unless downstream implementation can verify actual target-control contents without violating privacy constraints.
- The log should be durable enough for later analysis, so the downstream implementation should write to a documented file rather than only the existing bounded in-window event log.
- The log file should use a structured, machine-readable format such as JSON Lines unless the downstream design phase identifies an already-established project diagnostic format.
- The logging configuration should be exposed through the same general configuration chain as other runtime/UI settings; the exact flag/env names and file path are left to downstream planning/design.
- The logging should measure the existing pipeline and should not optimize or alter latency as part of this request.

## Open Questions
- Should the latency log file path be fixed under the existing `~/.tool-agents/untype/` directory, configurable, or both?
- Should this logging be available only for native UI push-to-talk sessions, or should the shared runtime expose it for CLI-driven push-to-talk-like flows if those exist later?
- Should downstream implementation define a retention/rotation policy for the log file, or is manual clearing/archiving sufficient for the first version?
- Is delivery-success timing sufficient for analysis, or does the user require an additional manual or automated verification step that proves the text is visibly present in the target application?

## Original Request
> "Great, can you create logs that allow us to understand the time spent between the push-to-talk button release and the appearance of the text in the active input control.
> I want you to create a configuration setting, that will enable this logging and have it recorded in some file, so that I can enable it when needed to perform log analysis. And I want you to document this in the project, so that in some future session the instructions will be available for someone to perform the analysis."
