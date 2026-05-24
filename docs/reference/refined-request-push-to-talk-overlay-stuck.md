# Refined Request: Push-To-Talk Overlay Stuck On Release

## Category
Development / Debugging

## Objective
Diagnose why the native UI push-to-talk overlay sometimes remains visible after the push-to-talk key/button is released and only closes after pressing the control again.

## Scope
In scope:
- Inspect the native UI push-to-talk press/release event path.
- Inspect overlay show/hide behavior and hotkey state transitions.
- Determine the most likely root cause from code and existing project documentation.
- If a localized fix is evident, implement it without changing transcription/provider/protocol behavior.
- Document the issue and solution in project documentation if a fix is applied.

Out of scope:
- Changing speech recognition, finalization, refine/translate, clipboard, or focused-input behavior.
- Adding new dependencies.
- Reworking the full UI layout.

## Requirements
- Releasing push-to-talk should reliably transition the UI out of recording/finalizing overlay state.
- The UI must not require a second press only to dismiss a stuck overlay.
- Existing fallback behavior for environments that cannot observe key-up events must remain usable.
- Hotkey diagnostics should remain privacy-safe.

## Constraints
- Keep changes localized to the existing native UI/AppKit push-to-talk path unless investigation proves otherwise.
- Preserve existing warm-session and release-submission behavior.
- No version-control operations.

## Acceptance Criteria
- The root cause is explained with code references.
- If code is changed, `swift test` passes.
- The project issue/design documentation reflects the diagnosed issue and fix if applicable.

## Assumptions
- "Push-to-talk button" refers to the configured keyboard push-to-talk control, though the UI fallback button is considered if the same code path applies.

## Open Questions
- None blocking.

## Original Request
So, sometimes the overlay that appears when I use the push-to-talk button doesn’t close when I release the button, and I have to press it again for it to close.
Can you detect what is going wrong?
