# Plan 026: Release log reset on start

Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-release-log-reset-on-start.md`
Investigation: skipped - single established approach, no new external technology.
Technical research: skipped - no new library/API/dependency introduced.
Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-release-log-reset-on-start.md`

## Objective
Add an environment-variable configuration parameter that controls whether the configured push-to-talk release latency JSONL log is cleared when the application process starts.

## Files to Modify
- `Sources/UntypeCore/ResolvedConfig.swift` - extend release latency logging configuration with a reset-on-start flag.
- `Sources/UntypeCore/ConfigResolver.swift` - resolve `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START` from the existing environment chain and validate boolean values.
- `Sources/UntypeCore/ReleaseLatencyLogger.swift` - add privacy-safe truncation of the configured log path.
- `Sources/UntypeCore/UntypeRuntimeFactory.swift` - run the reset when release latency logging is enabled and reset-on-start is true.
- `Tests/UntypeCoreTests/UntypeCommandTests.swift` and `Tests/UntypeCoreTests/ReleaseLatencyLoggerTests.swift` - cover default false, enabled reset, disabled/no-reset, custom path, and invalid boolean behavior.
- `docs/design/configuration-guide.md`, `docs/design/project-design.md`, and `docs/design/project-functions.md` - document the new configuration surface and design decision.

## Out of Scope
- Adding a CLI flag for this setting.
- Changing the release latency JSONL schema.
- Logging transcript text, processed text, provider payloads, prompts, secrets, or target application contents.
- Resetting logs while release latency logging is disabled.

## Implementation Steps
1. Extend the resolved release latency logging config with `resetOnStart`, defaulting to `false`.
2. Parse `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START` with the existing boolean parser.
3. Before creating an enabled release latency logger, truncate the configured path when `resetOnStart` is true.
4. Guard the reset with a process-local path registry so UI warm-session restarts do not erase records after application startup.
5. Update tests and documentation.

## Acceptance Checks
- `swift test` passes.
- Omitted or `off` reset config preserves existing log content and appends new records.
- `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=on` clears existing content for the configured log path before new records are written.
- Invalid boolean values raise a typed configuration error.
- The configuration guide documents accepted values, default, storage recommendation, and custom path behavior.
