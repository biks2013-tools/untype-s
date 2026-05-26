# Plan 023: Push-to-talk release latency logging

Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-push-to-talk-release-latency-logging.md`
Investigation: skipped - single established approach, no new external technology.
Technical research: skipped - no new library/API/dependency introduced.
Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-push-to-talk-release-latency-logging.md`

## Objective
Add opt-in, file-backed JSONL diagnostics that measure each push-to-talk release attempt from release detection to focused-input delivery completion, without recording transcript text, processed text, clipboard contents, prompts, secrets, or target application contents.

## Files to Modify
- `Sources/UntypeCore/ResolvedConfig.swift` - add the non-secret release latency logging config model.
- `Sources/UntypeCore/ConfigResolver.swift` - add `--release-latency-log`, `--no-release-latency-log`, `--release-latency-log-path`, `UNTYPE_RELEASE_LATENCY_LOG`, and `UNTYPE_RELEASE_LATENCY_LOG_PATH`.
- `Sources/UntypeCore/UntypeCommand.swift` - document the new CLI flags in `--help`.
- `Sources/UntypeCore/UntypeRuntimeFactory.swift` - build and inject the optional latency logger.
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift` - create one latency record per push-to-talk release attempt and measure provider finalization/submission timings.
- `Sources/UntypeCore/VoiceAgentProtocolController.swift` - return privacy-safe operator/focused-input timing summaries for release submissions.
- `Sources/UntypeCore/ReleaseLatencyLogger.swift` - new append-only JSONL writer and Codable record types.
- `Tests/UntypeCoreTests/*` - focused unit coverage for config parsing, disabled behavior, enabled records, privacy boundaries, and representative failure records.
- `docs/design/project-design.md`, `docs/design/project-functions.md`, `docs/design/configuration-guide.md`, `test_scripts/ui-mode-smoke.md`, and `Issues - Pending Items.md` - project documentation and analysis instructions.

## Out of Scope
- Changing push-to-talk, Quick Close, provider finalization, protocol, clipboard, or focused-input behavior beyond observation.
- Adding a log-analysis CLI/tool.
- Reading or logging target control contents to prove visual text appearance.
- Adding new runtime dependencies.

## Implementation Steps
1. Add release latency config with disabled-by-default behavior and a documented default JSONL path under `~/.tool-agents/untype/`.
2. Add an append-only JSONL logger that creates the parent config directory with `0700`, creates the log with `0600`, and appends one structured line per release attempt.
3. Extend protocol processing to report privacy-safe stage durations and focused-input result metadata.
4. Extend runtime release handling to create timing records for provider-final, Quick Close, timeout fallback, no-text, ignored-release, success, and failure outcomes.
5. Keep logging failures non-fatal by emitting existing diagnostic warnings only.
6. Add unit tests and update project docs/smoke-test instructions.

## Acceptance Checks
- `swift test` passes.
- Logging is disabled when the setting is absent or false.
- Logging appends a structured JSONL record when enabled.
- Records include stage durations and focused-input success/failure metadata without transcript or processed text.
- Documentation explains enabling, disabling, log location, log format, clearing/archiving, and analysis steps.
