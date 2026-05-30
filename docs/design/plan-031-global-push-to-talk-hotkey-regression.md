# Plan 031: Global Push-To-Talk Hotkey Regression

Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-global-push-to-talk-hotkey-regression.md`
Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-global-push-to-talk-hotkey-regression.md`
Investigation: skipped; the project already has an established native macOS hotkey path and the issue is localized to fallback global detection.
Technical research: skipped; Carbon global hotkey registration is an existing macOS framework capability and no new dependency is introduced.

## Objective
Restore reliable push-to-talk press/release detection while `untype.app` is in the background and another application has focus.

## Root Cause
The native UI currently relies on a Quartz event tap for global key-down/key-up detection. When the tap cannot be installed, is blocked by macOS permission state, or stops receiving events while another app has focus, the fallback path is only `NSEvent` local/global monitoring. That fallback is not a reliable press-and-hold global hotkey mechanism for background focus.

## Files To Modify
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
  - Add a Carbon `RegisterEventHotKey` monitor that emits global hotkey pressed/released events.
  - Start the Carbon monitor alongside the Quartz event tap and keep AppKit monitors as fallback/local handling.
  - Use the existing shared hotkey state to dedupe duplicate events from Quartz, Carbon, and AppKit sources.
  - Add descriptor helpers for Carbon key-code/modifier registration.
- `docs/design/project-design.md`
  - Record the Carbon fallback decision.
- `docs/design/project-functions.md`
  - Register the fixed feature slice.
- `Issues - Pending Items.md`
  - Document the resolved issue and dependency-vetting outcome.

## Steps
1. Import Carbon hotkey APIs into the native UI file.
2. Add `UntypeCarbonHotkeyMonitor` with `RegisterEventHotKey`, `InstallEventHandler`, press/release callbacks, and cleanup.
3. Wire it into `UntypeHotkeyMonitor.configure(settings:)`.
4. Keep the Quartz event tap as the preferred suppressing path and update status/diagnostics to expose Carbon fallback readiness.
5. Add descriptor helpers for Carbon modifier combinations, including `CommandOrControl` registration as both Command and Control variants.
6. Update documentation.
7. Run `swift build` and `swift test`.

## Acceptance Criteria
- Hotkey monitor compiles with Carbon fallback support.
- If the Quartz event tap is unavailable, Carbon global hotkey registration can still emit press/release events.
- If both Quartz and Carbon fire, duplicate press/release events are deduped through shared state.
- AppKit fallback monitors remain installed for local handling and last-resort behavior.
- `swift build` and `swift test` pass.
