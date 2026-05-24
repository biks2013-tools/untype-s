# Refined Request: UI Transcript And Events Tabs

## Category
Development

## Objective
Change the native `untype ui` monitoring window so the transcript timeline and event log are shown in separate tabs, giving users more usable space when monitoring transcription and push-to-talk processing.

## Scope
In scope:
- Update the existing SwiftUI native UI layout.
- Preserve the current transcript timeline behavior, including clear action, live partials, committed turns, processed output, and warning bubbles.
- Preserve the current event log behavior, including bounded event storage, auto-scroll, selectable monospaced text, and warning/error coloring.
- Keep the settings pane and session header behavior unchanged.
- Update project design/function documentation for the UI layout change.

Out of scope:
- Changing transcription, push-to-talk, Soniox finalization, protocol operators, clipboard delivery, or focused-input behavior.
- Adding a new UI framework or dependency.
- Changing event severity classification or the warning fallback logic.

## Requirements
- The main monitoring area must expose a Transcript tab and an Events tab.
- Only the selected tab's content should consume the main pane's vertical space.
- Transcript and Events tab content must reuse the existing rendering logic where practical.
- The UI must compile as part of the existing Swift package.

## Constraints
- No new dependencies.
- Keep the implementation local to the native UI layout unless compilation requires otherwise.
- Preserve existing user-facing labels unless a label must move to the tab control.

## Acceptance Criteria
- The native UI main pane shows tab controls for `Transcript` and `Events`.
- The Transcript tab shows the existing transcript timeline and Clear button.
- The Events tab shows the existing event log and continues to auto-scroll as events arrive.
- Existing settings controls remain in the right-side pane.
- `swift test` passes.

## Assumptions
- The Transcript tab should be the default selected tab because it is declared first.
- Existing header buttons such as `Stop Listening`, `Refresh`, and `Clear` should keep their current behavior.

## Open Questions
- None blocking.

## Original Request
You can put the transcript and the events in different tabs, so that there is more available space for the user when you want the UI to show what is happening, to monitor what is happening.
