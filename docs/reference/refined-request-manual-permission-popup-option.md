# Refined Request: Manual Permission Popup Option

## Category
Development

## Objective
Add an explicit application option that lets users manually open the existing permission-management popup/sheet for macOS operating-system permission issues.

## Scope
In scope:
- Reuse the existing `UntypeOnboardingView` sheet that guides users through Microphone, Accessibility, and provider setup.
- Add a visible option in the native UI Permissions area to open that sheet on demand.
- Ensure the manual option works even if the automatic onboarding sheet was recently skipped.
- Keep existing automatic onboarding behavior unchanged.
- Preserve non-persistence of transient permission statuses.
- Update design/function documentation and issue history.
- Verify with `swift build` and `swift test`.

Out of scope:
- Redesigning the onboarding sheet.
- Adding new permission APIs or changing macOS TCC behavior.
- Changing provider credentials, transcription, hotkey, focused-input, or clipboard logic.
- Adding runtime dependencies.

## Requirements
- The native UI must include a clear permission-management option in the app’s inspector/settings surface.
- Activating the option must present the existing permission-management popup/sheet immediately.
- The manual option must bypass the 24-hour “Skip for now” suppression used by automatic onboarding.
- The existing automatic popup behavior must remain unchanged.
- The permission popup must continue to use the current permission/credential status values.

## Constraints
- Use existing SwiftUI/AppKit code only.
- Do not persist transient OS permission status.
- Do not perform version-control operations.
- Preserve existing dirty worktree changes.

## Acceptance Criteria
- A user can open the permission-management popup from the app UI after the app is already running.
- The popup opens even after the user previously selected “Skip for now.”
- `swift build` succeeds.
- `swift test` succeeds.
- Project documentation records the new option.

## Assumptions
- “Pop-up screen responsible for handling operating system permission management issues” refers to the existing `UntypeOnboardingView` sheet.
- The best placement is the existing Permissions section in the right inspector because that is where Microphone, Accessibility, and Input Monitoring statuses already appear.

## Open Questions
None blocking.

## Original Request
“I want you to add an option to the application that enables the activation of the pop-up screen responsible for handling operating system permission management issues.”
