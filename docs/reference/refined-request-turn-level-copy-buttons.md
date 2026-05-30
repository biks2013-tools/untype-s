# Refined Request: Turn-Level Copy Buttons

## Category
Development

## Objective
Add copy controls to each transcript/history turn in the native UI so users can copy the raw dictated text and processed output separately from the existing whole-transcript export controls.

## Scope
In scope:
- Add a copy button for each committed raw turn segment when raw text exists.
- Add a copy button for each committed processed/refined/translated turn segment when processed text exists.
- Use the existing macOS pasteboard behavior already used by the Transcript and Events export copy actions.
- Keep transcript/history content in memory only; do not add automatic persistence.
- Preserve existing layout, turn grouping, labels, warning rows, clear behavior, save/export behavior, and runtime behavior.
- Add focused automated coverage where the copy behavior or copy payload can be verified without live macOS UI automation.
- Update project design/function documentation and the implementation plan for this change.

Out of scope:
- Changing whole-transcript or event-log export format.
- Adding clipboard history, background persistence, or diagnostics containing copied transcript text.
- Changing the transcription, refinement, translation, clipboard-delivery, or focused-input runtime pipeline.

## Requirements
- Each turn view must expose a visible copy affordance beside or within the raw section when raw text is present.
- Each turn view must expose a visible copy affordance beside or within the processed section when processed text is present.
- Copying raw text must place only that raw section text on `NSPasteboard.general`.
- Copying processed text must place only that processed/refined/translated output text on `NSPasteboard.general`.
- The controls must be compact and consistent with the native macOS utility UI.
- The controls must not appear for empty text sections.
- Existing transcript-level Copy/Save actions must continue to work.

## Constraints
- Use existing SwiftUI/AppKit and Foundation dependencies only; do not add runtime dependencies.
- Preserve the project no-fallback configuration rule.
- Do not perform version-control operations.
- Do not persist transcript or processed output outside explicit user-triggered copy/save behavior.
- Keep code changes localized to the native UI/timeline surface unless tests require small testability hooks.

## Acceptance Criteria
- In the Transcript tab, every committed turn with raw text has a raw copy button and every committed turn with processed output has a processed copy button.
- In the History tab, every retained turn with raw text has a raw copy button and every retained turn with processed output has a processed copy button.
- Pressing the raw copy button writes exactly the raw text for that turn to the pasteboard.
- Pressing the processed copy button writes exactly the processed text for that turn to the pasteboard.
- Existing whole-transcript and event copy/save controls remain unchanged.
- `swift build` succeeds.
- Relevant automated tests pass.

## Assumptions
- “Each turn” refers to the grouped transcript/history turn cards shown in the screenshot, not low-level event-log rows.
- The same per-section copy affordances should appear in both Transcript and History because both views show raw and processed turn content.
- Accessibility labels should identify whether the action copies raw or processed output.

## Open Questions
None blocking.

## Original Request
“I want you to add a copy button to each turn [Image #1] both for raw and for processed output”
