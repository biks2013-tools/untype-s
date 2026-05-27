# Refined Request: Release Log Reset on Startup

## Category
Development

## Objective
Add a configurable environment-variable setting that controls whether the existing push-to-talk release latency JSONL log file is reset when `untype` starts, so diagnostic runs can begin with an empty release log without requiring the user to manually delete or archive the file first.

## Scope
- **In scope**:
  - Add a new boolean environment-variable setting for release latency log reset behavior, using the existing configuration resolution and boolean parsing conventions.
  - Apply the setting during application startup before the first release latency log record can be appended.
  - Ensure the existing append-only behavior remains unchanged unless the new setting is explicitly enabled.
  - Document the new setting in the project configuration documentation alongside `UNTYPE_RELEASE_LATENCY_LOG` and `UNTYPE_RELEASE_LATENCY_LOG_PATH`.
  - Add or update focused automated tests for configuration parsing, default behavior, enabled reset behavior, disabled reset behavior, and invalid boolean values.
- **Out of scope**:
  - Changing the release latency log JSONL schema.
  - Changing which runtime events are logged.
  - Adding automatic log rotation, timestamped archive creation, or retention policies.
  - Adding a UI control for this setting.
  - Changing provider finalization, Quick Close, focused-input delivery, transcript persistence, or protocol processing behavior.
  - Introducing new runtime dependencies.

## Requirements
1. The implementation MUST introduce a new boolean environment-variable setting named `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START`.
2. The setting MUST be resolvable through the existing configuration chain where environment variables are currently read: current working directory `.env`, `~/.tool-agents/untype/.env`, and shell environment, preserving the project's documented precedence model.
3. The setting MUST default to `false` when omitted, preserving the current append-only release latency log behavior.
4. The setting MUST accept the same boolean values as existing boolean environment variables: `true`, `false`, `yes`, `no`, `on`, `off`, `1`, and `0`.
5. Invalid values for `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START` MUST raise a typed configuration error instead of being ignored or silently coerced.
6. When release latency logging is enabled and `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START` resolves to true, the configured release latency log file MUST be emptied or recreated at application startup before any new release latency records are appended.
7. When the setting resolves to false or is omitted, startup MUST NOT truncate, remove, or rewrite an existing release latency log file.
8. The reset operation MUST target the same path resolved by the existing release latency log path setting, including custom paths from `UNTYPE_RELEASE_LATENCY_LOG_PATH`.
9. The reset operation MUST preserve the existing privacy and permissions expectations for the release latency log: the directory is under the configured log path, the log file contains no transcript text or secrets, and file permissions remain consistent with the existing release latency logger behavior.
10. The reset operation MUST run at most once per application process startup and MUST NOT run before every push-to-talk release attempt.
11. The configuration documentation MUST include the new environment variable, its default value, accepted values, recommended usage, and its interaction with release latency logging and custom log paths.
12. Project design and functional requirement documentation SHOULD be updated during implementation if the implementation phase changes the documented configuration surface or release latency logging behavior.

## Constraints
- The project is an existing Swift Package Manager macOS application whose executable product is `untype`.
- The existing configuration precedence is CLI flag, current working directory `.env`, `~/.tool-agents/untype/.env`, then shell environment; implementation must align with the current resolver behavior and documentation.
- Missing required configuration must raise typed errors and must not be replaced with fallback values. This new setting is optional and has an explicit documented default of `false`.
- No new runtime dependencies should be introduced for this change.
- Release latency logging must remain privacy-safe and must not persist transcript text, processed text, clipboard contents, prompts, provider payloads, secrets, or target application contents.
- The existing release latency log path defaults to `~/.tool-agents/untype/release-latency.jsonl` unless configured otherwise.
- Version-control operations are not part of this request.

## Acceptance Criteria
1. `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START` is recognized by the configuration resolver from supported environment sources and is represented in the resolved configuration used at startup.
2. With release latency logging enabled, a configured log path containing existing content, and `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=on`, starting the application clears the existing log content before the first new release latency record is written.
3. With release latency logging enabled and the new setting omitted or set to `off`, starting the application preserves existing log content and subsequent release latency records append to the existing file.
4. With a custom `UNTYPE_RELEASE_LATENCY_LOG_PATH`, the reset behavior applies to the custom file path rather than the default file path.
5. Invalid values such as `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=maybe` fail configuration validation with a typed configuration error.
6. Automated tests cover at least the default false behavior, true reset behavior, false/no-reset behavior, custom-path behavior, and invalid boolean parsing.
7. `docs/design/configuration-guide.md` documents the new environment variable in the release latency logging section, including accepted values and the default.
8. Existing tests for release latency logging, configuration precedence, and startup behavior continue to pass.

## Assumptions
- **Release log identity**: "release log file" refers to the existing push-to-talk release latency JSONL log configured by `UNTYPE_RELEASE_LATENCY_LOG` and `UNTYPE_RELEASE_LATENCY_LOG_PATH`, because the current project documentation and source use that terminology for release-related file-backed diagnostics.
- **No CLI flag required**: The request specifically asks for an environment-variable/configuration-file parameter, so a CLI flag is not required unless the implementation phase decides CLI parity is necessary for consistency.
- **Reset only when logging is enabled**: The reset behavior is expected to matter only when release latency logging is enabled, to avoid deleting diagnostic files during runs that are not collecting release latency logs.
- **Startup means process startup**: "Every time the application starts" means once per `untype` process launch, not once per session restart, warm push-to-talk restart, or push-to-talk release attempt.

## Open Questions
None.

## Original Request
"Add a parameter to the environment variables in the configuration file that determines if the release log file is reset every time the application starts."
