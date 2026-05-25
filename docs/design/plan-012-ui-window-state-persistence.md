# Plan 012: UI Window State Persistence

Refined request: `docs/reference/refined-request-ui-window-state-persistence.md`
Investigation: skipped - this extends the existing non-secret UI settings persistence path; no approach or dependency choice is required.
Technical research: skipped - no new framework, API, or external library is introduced.
Codebase scan: `docs/reference/codebase-scan-ui-window-state-persistence.md`

## Objective
Persist and restore the main UI window size, settings-pane visibility, and selected monitor tab across `untype ui` launches.

## Files To Modify
- `Sources/UntypeCore/UntypeUISettings.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/UntypeUISettingsTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Steps
1. Add non-secret layout fields to `UntypeUISettings`: window width, window height, settings visibility, and selected monitor tab.
2. Normalize those fields with minimum window dimensions and an explicit tab allow-list.
3. Extend `UntypeUISettingsStore` JSON save/load to persist the layout fields while keeping transient credential/permission statuses out of the file.
4. Restore the saved window size when creating the main `NSWindow`.
5. Add an AppKit window delegate callback that records size changes back into `ui-state.json`.
6. Bind settings-pane visibility and `TabView` selection to persisted model state.
7. Add focused tests for persistence, privacy exclusions, and invalid tab rejection.
8. Update project design/function/issue documentation.
9. Run `swift test`.

## Acceptance Criteria
- Main window size is restored after relaunch.
- Settings hidden/visible state is restored after relaunch.
- Transcript/Events tab selection is restored after relaunch.
- The UI state file remains non-secret and excludes transient status values.
- Invalid persisted UI state values fail with a typed configuration error.
- `swift test` passes.
