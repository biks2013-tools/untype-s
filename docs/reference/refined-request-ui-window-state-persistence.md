# Refined Request: UI Window State Persistence

## Category
Development

## Objective
Make `untype ui` remember the main window size and monitor layout state between launches, specifically whether the settings pane is visible and whether the Transcript or Events tab is selected.

## Scope
- **In scope**: Persist the main UI window width and height in the existing non-secret UI state file.
- **In scope**: Restore the persisted main window size when launching `untype ui`.
- **In scope**: Persist and restore whether the settings pane is hidden or visible.
- **In scope**: Persist and restore whether the Transcript or Events tab is selected.
- **In scope**: Preserve existing non-secret UI settings persistence and transient credential/permission privacy rules.
- **In scope**: Add or update focused tests for UI state persistence.
- **Out of scope**: Persisting window screen position, maximized/full-screen state, transcript content, event log content, secrets, credentials, permission status, or overlay window geometry.

## Requirements
1. The app MUST save main window width and height after the user changes the window size.
2. The app MUST launch with the last saved main window size when the saved values are valid.
3. The app MUST save the settings pane visibility whenever the user hides or shows settings.
4. The app MUST launch with the settings pane visibility restored from the previous run.
5. The app MUST save the selected monitor tab when the user switches between Transcript and Events.
6. The app MUST launch with the previously selected monitor tab.
7. The persisted UI state MUST remain non-secret and MUST NOT persist API key values, credential status values, permission status values, transcript text, or event log text.
8. Invalid persisted UI layout values MUST be reported as configuration errors rather than silently accepted.
9. Existing UI configuration, hotkey, protocol operator, transcript export, and overlay behavior MUST remain unchanged.

## Constraints
- The project is a Swift Package Manager macOS 14 project.
- Existing UI state is stored at `~/.tool-agents/untype/ui-state.json` with file mode `0600` under a `0700` directory.
- The implementation must use the existing SwiftUI/AppKit UI architecture and must not add runtime dependencies.
- Missing required configuration values must continue to raise typed errors; this request must not introduce configuration fallbacks for secrets or provider settings.
- No version-control operation may be performed unless explicitly requested.

## Acceptance Criteria
1. Resizing the main UI window, closing/relaunching, and reopening `untype ui` restores the saved window size.
2. Hiding settings, closing/relaunching, and reopening restores settings hidden.
3. Showing settings, closing/relaunching, and reopening restores settings visible.
4. Selecting Events, closing/relaunching, and reopening restores Events as the active monitor tab.
5. Selecting Transcript, closing/relaunching, and reopening restores Transcript as the active monitor tab.
6. Automated tests verify the persisted UI state contains the new layout fields and still excludes transient/secret values.
7. `swift test` passes.

## Assumptions
- "Window size" means the main monitoring window width and height, not screen position or full-screen/maximized state.
- "Window state" in this request refers only to settings-pane visibility and selected monitor tab, because those are the states named by the user.
- The existing UI state file is the right storage location because these values are non-secret user UI preferences.

## Open Questions
None.

## Original Request
"Now I want you to make the application remember the window size and the window state: whether the settings are hidden or visible, and whether the selected tab is the transcript or the events."
