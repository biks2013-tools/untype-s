# Plan 006: Transcript And Events Export Copy

Refined request: `docs/reference/refined-request-transcript-events-export-copy.md`
Codebase scan: `docs/reference/codebase-scan-transcript-events-export-copy.md`
Investigation: skipped - localized SwiftUI/AppKit extension using existing project patterns.
Technical research: skipped - no new technology or dependency introduced.

## Objective
Add explicit native UI actions that let users copy or save the current transcript timeline and current event log without changing session state or introducing automatic persistence.

## Files To Modify
- `Sources/UntypeCore/UntypeUITimeline.swift`
- `Sources/UntypeCore/UntypeUIExport.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/UntypeUITimelineTests.swift`
- `Tests/UntypeCoreTests/UntypeUIExportTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Steps
1. Add plain-text export formatting for transcript timeline state, preserving turn order, bubble labels, status values, and live partial text.
2. Add a small export action helper with injectable copy and save closures so clipboard/save routing is testable without opening AppKit panels.
3. Wire Transcript tab `Copy` and `Save` buttons to transcript export documents, disabled when no transcript content exists.
4. Wire Events tab `Copy` and `Save` buttons to event export documents, disabled when no event content exists.
5. Use `NSPasteboard` for explicit copy actions and `NSSavePanel` plus atomic UTF-8 writes for explicit save actions.
6. Update project design, functional requirements, and issue history.
7. Run `swift test`.

## Acceptance Criteria
- Transcript tab exposes enabled `Copy` and `Save` actions when transcript content exists.
- Events tab exposes enabled `Copy` and `Save` actions when event lines exist.
- Empty transcript and empty event states do not produce copy/save output.
- Copy actions place the selected export text on the macOS clipboard without mutating visible state.
- Save actions write the selected export text to a user-selected file without stopping or altering active sessions.
- Transcript export includes committed turns and live partial text in chronological reading order.
- Event export includes retained event lines in chronological order.
- `swift test` passes.
