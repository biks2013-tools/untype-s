# Refined Request: Global Push-To-Talk Hotkey Regression

## Category
Development

## Objective
Restore reliable press-and-hold push-to-talk hotkey detection when `untype.app` is running in the background and another application has keyboard focus.

## Scope
In scope:
- Diagnose the native UI hotkey registration path used by push-to-talk.
- Preserve existing Quartz event-tap behavior when available, including key suppression and operator hotkeys.
- Add or adjust a fallback global hotkey mechanism so push-to-talk press and release can still be detected when another app is focused.
- Keep the UI fallback press/release button available.
- Document the issue, root cause, and solution in project docs and pending/completed issues.
- Verify with `swift build` and `swift test`.

Out of scope:
- Changing provider, transcription, refinement, translation, focused-input, clipboard, or overlay layout behavior.
- Adding a new runtime dependency.
- Changing user hotkey configuration semantics.
- Performing live macOS permission smoke tests unless explicitly requested.

## Requirements
- A configured push-to-talk hotkey must trigger press handling while another application has focus when macOS allows global hotkey registration.
- Releasing the same hotkey must trigger release handling while another application has focus.
- Existing Quartz event-tap path must remain the preferred path for suppression when it starts successfully.
- Duplicate press/release events from multiple hotkey sources must not start/stop multiple sessions.
- When the Quartz tap is unavailable, diagnostics must surface that global hotkey registration is using fallback behavior.
- No transcript text, processed text, provider payloads, or secrets may be logged by the hotkey diagnostics.

## Constraints
- Use only existing macOS frameworks available to the SwiftPM target.
- Do not add package dependencies.
- Do not perform version-control operations.
- Preserve existing user work in the dirty worktree.

## Acceptance Criteria
- `untype ui` still compiles with the native hotkey monitor.
- Press-and-hold hotkey detection has a global fallback path independent of `NSEvent` local focus.
- Existing event-tap and AppKit fallback behavior remains available.
- `swift build` succeeds.
- `swift test` succeeds.
- Project design/functions and issue history record the regression and fix.

## Assumptions
- The reported regression is in the native macOS UI push-to-talk path, not the CLI transcription path.
- The packaged app may still require users to grant Accessibility/Input Monitoring permissions to the rebuilt `untype.app` identity for event taps and focused input.

## Open Questions
None blocking.

## Original Request
“The application has lost the ability to detect the 'press and hold to talk' hotkey when the focus is on another application.”
