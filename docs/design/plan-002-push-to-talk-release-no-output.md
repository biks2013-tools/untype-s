# Plan 002 - Push-to-talk release no output

Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-push-to-talk-release-no-output.md`
Investigation: skipped - localized regression in an existing UI/runtime path.
Technical research: skipped - no new technology or external API introduced.
Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-push-to-talk-release-no-output.md`

## Objective
Make the existing native UI push-to-talk release path visibly prove whether finalization, processing, clipboard delivery, and focused-input delivery ran, and show explicit privacy-safe diagnostics when release produces no submitted text.

## Scope
- Extend the current runtime release/finalization path in `TranscriptionSessionRuntime`.
- Extend existing protocol-controller diagnostics for refine/translate/clipboard/input operator attempts and failures.
- Surface release/operator warning diagnostics in the native UI timeline so the monitor is not silent.
- Add focused unit coverage for the empty-release diagnostic and visible operator failure diagnostics.
- Update project design, function registry, and issue log with the defect and solution.

## Files to Modify
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift`
- `Sources/UntypeCore/VoiceAgentProtocolController.swift`
- `Sources/UntypeCore/UntypeRuntimeFactory.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift`
- `Tests/UntypeCoreTests/ProtocolControllerTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Checks
- `swift test` passes.
- Releasing push-to-talk with no provider final text emits a visible warning instead of silently doing nothing.
- UI sessions emit privacy-safe diagnostics for release finalization and operator delivery stages.
- Operator failures remain fail-open and are visible in the UI without requiring verbose mode.
