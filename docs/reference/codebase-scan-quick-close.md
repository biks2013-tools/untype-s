---
language: swift
framework: none
package_manager: swiftpm
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/untype-input-helper/main.swift
last_scanned_commit: fcc66148cfde8de07137af11321d22022a3c896b
scanned_for_request: refined-request-quick-close.md
scanned_at: 2026-05-26T20:19:32Z
---

# Codebase Scan — untype-s

## 1. Project Overview
This is a Swift 6 / SwiftPM macOS project with one shared library target, `UntypeCore`, and two executables: the main `untype` app and the `untype-input-helper` companion binary. The codebase is organized around a shared runtime, UI state model, and configuration resolver that feed both CLI and native UI launch paths. Core behavior already exists for push-to-talk release finalization, transcript rendering, protocol processing, and persisted non-secret UI state.

## 2. Module Map
| Path | Purpose | Representative symbols |
|---|---|---|
| `Sources/UntypeCore` | Shared runtime, config, UI state, protocol, transcript, and persistence logic used by both executables. | `TranscriptionSessionRuntime.submitPending`, `ConfigResolver.resolve`, `UntypeUISettingsStore.loadForUI` |
| `Sources/untype` | CLI executable entry point that dispatches `ui` vs command-line runtime execution. | `UntypeExecutable.main`, `UntypeCommand.run` |
| `Sources/untype-input-helper` | Small helper executable for focused-input delivery plumbing. | `FocusedInputHelperMain.run`, `FocusedInputHelperMain.encodeResult` |
| `Tests/UntypeCoreTests` | Swift Testing coverage for config precedence, runtime finalization, UI settings persistence, and protocol behavior. | `sessionRuntimeStopWithSubmitPendingFallsBackToLatestPartialWhenFinalNeverArrives`, `uiSettingsStorePersistsOnlyNonSecretFields`, `helpWritesToStdoutAndExitsZero` |

## 3. Conventions
- Shared code prefers small `public` value types plus `final` implementation classes, with `Foundation`, `SwiftUI`, and `AppKit` imported directly where needed. There is no separate logging framework; diagnostics flow through `ProtocolControllerDiagnostics`, `TextOutput`, and `UntypeError.diagnosticLine`. `Sources/UntypeCore/TranscriptionSessionRuntime.swift:154-191`, `Sources/UntypeCore/NativeUntypeUILauncher.swift:1-6`, `Sources/UntypeCore/UntypeCommand.swift:3-18`.
- Config precedence is explicit and centralized: CLI flag > local `./.env` > `~/.tool-agents/untype/.env` > shell environment. That precedence is enforced by `EnvChain` and documented in the CLI help text. `Sources/UntypeCore/EnvChain.swift:15-41`, `Sources/UntypeCore/UntypeCommand.swift:135-139`.
- Required configuration values do not fall back silently. `ConfigResolver` throws `missingConfiguration` / `invalidConfiguration` when secrets or required runtime values are absent or malformed, while optional values are normalized and validated before being accepted. `Sources/UntypeCore/ConfigResolver.swift:45-96`, `Sources/UntypeCore/ConfigResolver.swift:169-403`, `Sources/UntypeCore/ConfigResolver.swift:418-603`.
- Non-secret UI state is persisted separately from secrets in `~/.tool-agents/untype/ui-state.json`. `UntypeUISettings.sessionArguments()` reconstructs CLI arguments for the UI bootstrap path, and the persisted JSON intentionally omits secret values and transient permission state. `Sources/UntypeCore/UntypeUISettings.swift:190-210`, `Sources/UntypeCore/UntypeUISettings.swift:359-553`, `Sources/UntypeCore/UntypeUISettings.swift:556-687`.
- Runtime release handling is already a dedicated pipeline: `submitPending()` requests provider finalization, `finalizePendingUtterance()` waits for final text with a timeout, then falls back to the latest partial and suppresses late provider partials after submission. `Sources/UntypeCore/TranscriptionSessionRuntime.swift:19-79`, `Sources/UntypeCore/TranscriptionSessionRuntime.swift:335-487`.
- Tests use Swift Testing (`@Test`, `#expect`) with small local fixtures and table-style JSON assertions instead of XCTest. The style is consistent across config, runtime, and UI-state tests. `Tests/UntypeCoreTests/UntypeCommandTests.swift:1-17`, `Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift:13-77`, `Tests/UntypeCoreTests/UntypeUISettingsTests.swift:5-24`.

## 4. Integration Points
### In-Scope
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift:154-487` - the current finalization / fallback release path already exists here; `Quick Close` is most likely a new branch in `finalizePendingUtterance()` plus a new runtime option on `TranscriptionSessionRuntimeOptions`.
- `Sources/UntypeCore/UntypeRuntimeFactory.swift:14-157` - this is the runtime construction boundary for both CLI and UI launches. Any new policy flag must be threaded into the runtime here so the release behavior is consistent across entry points.
- `Sources/UntypeCore/UntypeUISettings.swift:3-687` - this file owns the persisted non-secret UI model, UI-state JSON, and `sessionArguments()`. It is the natural landing site for a `Quick Close` toggle if the policy is exposed through the native UI and bootstrapped via config arguments.
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:260-375, 482-600, 696-747, 1768-1930, 2110-2141` - the hotkey release handler, runtime startup path, settings pane, and settings patch router all live here. This is where the UI toggle, diagnostics text, and event surfacing would be wired.
- `Sources/UntypeCore/ConfigResolver.swift:45-403` and `Sources/UntypeCore/ResolvedConfig.swift:139-155` - if `Quick Close` is exposed as CLI/env configuration, these are the parsing and data-model surfaces that need a new field.
- `Sources/UntypeCore/UntypeCommand.swift:44-149` - the CLI dispatch and help text live here, so a shared config option would also need a help-text update.
- `Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift:112-301` - existing tests already cover the disabled wait/fallback behavior, final-text preference, and late-partial suppression. This is the primary regression suite for the new policy.
- `Tests/UntypeCoreTests/UntypeUISettingsTests.swift:5-311` and `Tests/UntypeCoreTests/UntypeCommandTests.swift:68-417` - these are the natural tests for any new UI persistence or CLI/env option round-trip.

### Out-of-Scope
- `Sources/UntypeCore/SonioxTranscriber.swift` and `Sources/UntypeCore/ElevenLabsTranscriber.swift` - provider transport, endpoints, and streaming frame handling are explicitly out of scope for this request.
- `Sources/UntypeCore/AVFoundationAudioSource.swift` - audio capture should stay unchanged; the policy affects release timing, not microphone collection.
- `Sources/UntypeCore/MacOSClipboardWriter.swift` and `Sources/UntypeCore/FocusedInputDelivery.swift` - clipboard and focused-input delivery remain downstream consumers of submitted text, not policy owners.
- `Sources/UntypeCore/ProtocolSettingsStore.swift` - protocol operator persistence is separate from the push-to-talk release policy and should not be repurposed for this feature.
- `Sources/UntypeCore/UntypeUITimeline.swift` - timeline/history structures already accept partial, final, and processed events; they only need changes if diagnostics require a new presentation shape.

### New Integration Points
- `Quick Close` does not exist anywhere in source today; the new policy is a fresh non-secret configuration bit or release-policy enum that should probably land first in `UntypeUISettings` / `UntypeUISettingsPatch` and then propagate through `sessionArguments()` if the UI is the source of truth.
- If the policy is shared across UI and CLI, the next landing site is `ConfigResolver.resolve(...)` and `ResolvedConfig`, followed by `UntypeRuntimeFactory` and `TranscriptionSessionRuntimeOptions` so the runtime can decide whether to wait for final text or submit the latest partial immediately.
- Diagnostic presentation likely needs one new label path in `NativeUntypeUILauncher.shouldSurfaceDiagnosticInTimeline(...)` so the UI can distinguish provider-final, Quick Close partial, timeout fallback partial, and no-text release outcomes.

## 5. Notes
- The disabled behavior requested by `Quick Close` is already implemented today as the default release path, so the change is an extension of the existing pipeline rather than a new transcription architecture.
- There is no `Quick Close` symbol, config key, or help-text mention in the source tree; the only occurrence is the refined request document.
- No SwiftLint / swift-format configuration was found, so `swift build` / `swift test` appear to be the only project-level build/test entry points.
