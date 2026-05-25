# Refined Request: Untype UI Discovery Screenshots

## Category
Documentation / UI discovery

## Objective
Attach to the currently running `untype` application, discover the visible user interface and available options, and collect screenshots that explain the application's capabilities and user workflow.

## Scope
- In scope:
  - Locate and observe the running `untype` UI.
  - Capture screenshots of the main monitoring window and relevant UI states/options that can be reached without destructive actions.
  - Document the visible capabilities, controls, settings, tabs, and workflow represented by the screenshots.
  - Store screenshots and the discovery summary under `docs/reference/`.
- Out of scope:
  - Changing application source code.
  - Changing persisted settings unless required to reveal a non-destructive UI state.
  - Sending text to external services, starting paid provider usage, or saving files through the app without explicit user confirmation.
  - Version-control operations.

## Requirements
- Use the already-running application when accessible.
- Prefer non-destructive observation and UI navigation.
- Include screenshots in the final response and preserve them as project reference material.
- Record any limitations, such as UI areas that could not be reached because credentials, permissions, or app attachment were unavailable.

## Constraints
- Do not perform version-control operations.
- Do not expose secrets in screenshots or notes.
- Do not trigger external provider transcription, clipboard writes, focused-input delivery, or file-save dialogs unless needed and explicitly safe.
- Keep collected reference artifacts under `docs/reference/`.

## Acceptance Criteria
- A screenshot set exists under `docs/reference/untype-ui-discovery-screenshots/`.
- A concise UI discovery report exists under `docs/reference/`.
- The final response lists the captured UI states and links or embeds the screenshots.
- The final response clearly identifies any gaps in coverage.

## Assumptions
- The running application is the native SwiftUI/AppKit `untype ui` window described by the project design.
- Capturing screenshots of the user interface is allowed for this task.
- Non-destructive UI exploration is acceptable; risky or external-impact actions require confirmation.

## Open Questions
- None blocking. If the running app cannot be attached to directly, the discovery will use the safest available local capture method and report that limitation.

## Original Request
> I want you to attach to the untype application (which is running), discover its user interface, the options it has in its user interface, and collect all the screenshots that describe its capabilities and how it works.
