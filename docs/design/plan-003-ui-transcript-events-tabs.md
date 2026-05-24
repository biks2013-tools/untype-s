# Plan 003: UI Transcript And Events Tabs

Refined request: `docs/reference/refined-request-ui-transcript-events-tabs.md`

## Objective
Give the native UI monitoring area more usable vertical space by moving transcript timeline and event log views into separate tabs.

## Files To Modify
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`

## Steps
1. Extract the existing event-log view into a reusable `eventsPane`.
2. Replace the stacked transcript/events layout in `mainPane` with a tabbed `monitorPane`.
3. Keep `transcriptPane` and `eventsPane` behavior unchanged inside their tabs.
4. Update design and function documentation to record the UI layout change.
5. Run `swift test`.

## Acceptance Criteria
- `Transcript` and `Events` tabs are visible in the main monitoring pane.
- Transcript timeline behavior remains unchanged.
- Event log behavior remains unchanged.
- The Swift package test suite passes.
