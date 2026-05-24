# Refined Request: UI settings pane polish

## Category
Design and development.

## Objective
Make the native UI settings form tidier by aligning controls and applying a restrained glass/material visual treatment to the settings sections.

## Scope
In scope:
- Update the SwiftUI settings pane layout in `NativeUntypeUILauncher.swift`.
- Align labels, values, text fields, pickers, steppers, toggles, and action buttons in consistent rows.
- Replace default grouped gray panels with material-backed section panels.
- Preserve existing settings behavior, bindings, disabled states, and push-to-talk actions.

Out of scope:
- Changing transcription/runtime behavior.
- Adding new settings or changing persisted settings schema.
- Introducing external design dependencies.

## Requirements
- Controls must remain readable and usable at the current settings-pane width.
- The visual style must fit a macOS utility app and avoid decorative clutter.
- Existing enable/disable behavior during active sessions must remain intact.
- The implementation must build with the current SwiftPM target.

## Constraints
- No new dependencies.
- Keep the change localized to the native UI and project documentation.
- Do not persist any new transient UI-only visual state.

## Acceptance Criteria
- Settings sections use a glass/material background style.
- Form rows have consistent label widths and aligned controls.
- `swift test` passes.
- The design change is documented in project docs/issues.

## Assumptions
- The user is referring to the right-side settings form in `untype ui`.
- Material-backed SwiftUI panels are an acceptable interpretation of "glass effects" for the current macOS SwiftUI target.

## Open Questions
- None blocking.

## Original Request
> can you make the form more tidy ?
> aligned controls ?
> use glass effects for the form ?
