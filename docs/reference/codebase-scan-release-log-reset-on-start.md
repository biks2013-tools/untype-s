---
language: swift
framework: SwiftUI/AppKit
package_manager: swiftpm
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - ~/aiwork/coding-platform/untype-s/Sources/untype/main.swift
  - ~/aiwork/coding-platform/untype-s/Sources/untype-input-helper/main.swift
last_scanned_commit: e5f08b969b68fea70018896fc8377eb779fefddf
scanned_for_request: refined-request-release-log-reset-on-start.md
scanned_at: 2026-05-26T22:16:40Z
request_file: ~/aiwork/coding-platform/untype-s/docs/reference/refined-request-release-log-reset-on-start.md
scan_scope: request-driven
generated_at: 2026-05-26T22:16:40Z
---

# Codebase Scan — untype-s

## 1. Project Overview
`untype-s` is a SwiftPM macOS package with one shared runtime library target, `UntypeCore`, and two executable targets: the main `untype` CLI and the `untype-input-helper` stdin/stdout helper. The current implementation already centralizes config resolution, startup orchestration, and push-to-talk release-latency JSONL logging, so this request extends an existing diagnostic/logging seam rather than introducing a new subsystem. The reset-on-start behavior is not implemented yet; today the logger only appends to the resolved JSONL file when release logging is enabled.

## 2. Module Map
| Path | Purpose | Representative symbols |
|---|---|---|
| [`~/aiwork/coding-platform/untype-s/Sources/UntypeCore`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore) | Shared runtime surface for configuration, transcription/session orchestration, protocol processing, UI state, focused-input delivery, and release diagnostics. | `ConfigResolver.resolve`, `UntypeRuntimeFactory.make`, `TranscriptionSessionRuntime.start`, `ReleaseLatencyJsonlLogger.append` |
| [`~/aiwork/coding-platform/untype-s/Sources/untype`](~/aiwork/coding-platform/untype-s/Sources/untype) | Thin executable entry point that dispatches `ui` into the native launcher and otherwise runs the CLI/runtime path through `UntypeCommand`. | `UntypeExecutable.main`, `UntypeCommand.run` |
| [`~/aiwork/coding-platform/untype-s/Sources/untype-input-helper`](~/aiwork/coding-platform/untype-s/Sources/untype-input-helper) | Standalone helper executable wrapper that reads stdin and emits one JSON result line for focused-input delivery. | `inputData`, `FocusedInputHelperMain.run`, `FocusedInputHelperMain.encodeResult` |
| [`~/aiwork/coding-platform/untype-s/Tests/UntypeCoreTests`](~/aiwork/coding-platform/untype-s/Tests/UntypeCoreTests) | Swift Testing suite covering config parsing, release-timing behavior, protocol JSONL, UI settings persistence, and focused-input/privacy seams. | `releaseLatencyLoggingIsDisabledByDefaultWithDocumentedUserPath`, `releaseLatencyJsonlLoggerAppendsStructuredPrivacySafeRecords`, `sessionRuntimeWritesReleaseLatencyRecordForFocusedInputSuccessWithoutTranscriptText` |

## 3. Conventions
- Startup is intentionally thin at the executable layer. [`Sources/untype/main.swift`](~/aiwork/coding-platform/untype-s/Sources/untype/main.swift#L1-L20) only parses the `ui` shortcut and delegates to `UntypeCommand`, while [`Sources/UntypeCore/UntypeCommand.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/UntypeCommand.swift#L44-L92) resolves config, starts the runtime, waits for shutdown, then maps typed errors to exit codes.
- Configuration is strict and layered. [`Sources/UntypeCore/EnvChain.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/EnvChain.swift#L20-L41) reads `<cwd>/.env`, `~/.tool-agents/untype/.env`, then shell env, and [`Sources/UntypeCore/ConfigResolver.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/ConfigResolver.swift#L44-L48) turns that chain plus CLI flags into a single `ResolvedConfig`.
- `.env` parsing is permissive but still normalized. [`Sources/UntypeCore/Dotenv.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/Dotenv.swift#L3-L53) supports comments, `export`, quoted values, and inline comment stripping, while blank values fall through to lower-priority sources.
- Boolean env settings share one parsing convention. [`Sources/UntypeCore/ConfigResolver.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/ConfigResolver.swift#L675-L688) accepts `true`, `false`, `yes`, `no`, `on`, `off`, `1`, and `0`, and invalid values raise `UntypeError.invalidConfiguration` instead of being coerced.
- File-backed output uses explicit directory creation and permissions. [`Sources/UntypeCore/ReleaseLatencyLogger.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/ReleaseLatencyLogger.swift#L30-L61) creates the directory tree, sets `0700` on the directory and `0600` on the file, and appends JSONL records with sorted keys and no escaping of slashes.
- Release latency emission happens at the runtime boundary, not in the logger. [`Sources/UntypeCore/TranscriptionSessionRuntime.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/TranscriptionSessionRuntime.swift#L629-L669) builds a `ReleaseLatencyLogRecord` at `finishReleaseLatencyTurn` and hands it to `ReleaseLatencyLogWriting`, so any reset-on-start behavior must occur before the first runtime append.

## 4. Integration Points

### In-Scope
- [`Sources/UntypeCore/ConfigResolver.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/ConfigResolver.swift#L351-L360) and [`Sources/UntypeCore/ResolvedConfig.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/ResolvedConfig.swift#L139-L158) are the config-model seam for the new `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START` boolean. The new setting should follow the existing boolean parsing and typed-error path, and it likely belongs on the release-latency config struct.
- [`Sources/UntypeCore/EnvChain.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/EnvChain.swift#L20-L41) and [`Sources/UntypeCore/Dotenv.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/Dotenv.swift#L3-L53) are the env-loading seam. The request explicitly wants the new setting to resolve through the current `.env`/user-env/shell chain, so no new resolver should be introduced.
- [`Sources/UntypeCore/UntypeCommand.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/UntypeCommand.swift#L64-L80) is the startup orchestration point that resolves config before runtime creation. Reset-on-start has to happen before the first release record can be appended, so this startup path should remain the high-level control flow boundary.
- [`Sources/UntypeCore/UntypeRuntimeFactory.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/UntypeRuntimeFactory.swift#L45-L80) and [`Sources/UntypeCore/UntypeRuntimeFactory.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/UntypeRuntimeFactory.swift#L215-L220) are the most likely landing site for the reset hook. The factory already owns release-logger construction for both CLI and UI paths, so it can reset/truncate once per process before handing the logger into the runtime.
- [`Sources/UntypeCore/ReleaseLatencyLogger.swift`](~/aiwork/coding-platform/untype-s/Sources/UntypeCore/ReleaseLatencyLogger.swift#L3-L61) is the logger implementation seam. It already encapsulates path creation, permissions, and append-only writes, so a new reset helper would naturally live here or alongside it.
- [`Tests/UntypeCoreTests/UntypeCommandTests.swift`](~/aiwork/coding-platform/untype-s/Tests/UntypeCoreTests/UntypeCommandTests.swift#L151-L184) and [`Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift`](~/aiwork/coding-platform/untype-s/Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift#L318-L407) are the most relevant test surfaces for config parsing and runtime release behavior. [`Tests/UntypeCoreTests/ReleaseLatencyLoggerTests.swift`](~/aiwork/coding-platform/untype-s/Tests/UntypeCoreTests/ReleaseLatencyLoggerTests.swift#L5-L54) already covers the privacy-safe append format and is the natural place to add file-reset assertions.
- [`docs/design/configuration-guide.md`](~/aiwork/coding-platform/untype-s/docs/design/configuration-guide.md#L54-L87), [`docs/design/project-design.md`](~/aiwork/coding-platform/untype-s/docs/design/project-design.md#L99-L103), and [`docs/design/project-functions.md`](~/aiwork/coding-platform/untype-s/docs/design/project-functions.md#L80-L81) already document release-latency logging. They need the new reset flag and startup semantics if implementation proceeds.

### Out-of-Scope
- [`Sources/untype-input-helper/main.swift`](~/aiwork/coding-platform/untype-s/Sources/untype-input-helper/main.swift#L1-L11) is a focused-input helper wrapper only; it does not participate in release-latency config or startup log reset.
- [`Sources/untype/main.swift`](~/aiwork/coding-platform/untype-s/Sources/untype/main.swift#L1-L20) is a thin launcher shim. The actual reset logic should stay in `UntypeCore` unless startup routing itself changes.

### New Integration Points
- A new boolean field on the release-latency config model, likely `resetOnStart`, is not present today. The cleanest extension point is `ReleaseLatencyLoggingConfig` plus the `ConfigResolver` branch that already builds it.
- There is no startup-time truncate/reset helper today. The likely new landing site is `UntypeRuntimeFactory`, which can reset the configured file once per process before constructing the runtime.
- The logger itself only exposes append today. If the reset behavior should be encapsulated, `ReleaseLatencyJsonlLogger` needs a new explicit `reset()` or similar helper that reuses the same path and permission rules as append.

## 5. Notes
- The current release-latency implementation is append-only; no reset-on-start behavior exists anywhere in the scanned source.
- Existing tests cover enabled/disabled/path-override behavior for release logging, but the repo does not yet have invalid-boolean coverage for release-log settings or the proposed reset flag.
- `docs/design/configuration-guide.md` currently tells users to archive or remove the file manually after a diagnostic run, so that guidance will need to be updated if startup reset is added.
- The executable entry points are intentionally thin, so the implementation should remain in `UntypeCore` rather than spreading logic into the launcher shims.
