# Plan 055 - Experimental operators

Date: 2026-11-12. Requirement: FR-61.

## Request

Put Selection (S), Screenshot (W), Window text (X) and Follow-up (F) in a category of experimental options, with one switch that turns the category on or off.

## Decisions

- `OperatorKey.experimental` = `[.followup, .selection, .screenshot, .windowText]`; `OperatorKey.isExperimental`.
- UI setting `experimentalOperators` (Bool, default off, stored in the UI settings state). A state file written before the setting loads with it off.
- Off means: the four operators are kept switched off (`UntypeUISettings.normalized()` forces them to false, so every path that changes settings obeys it), and they are not offered: no chip in the overlay or the window rows, no row in the menu-bar dropdown, their hotkey letters do nothing while the hotkey is held (`UntypeUIModel.toggleOperator` returns early; the letter is still swallowed, not typed).
- Switching the category back on does not restore the operators: each is switched on again by the user.
- The menu-bar dropdown has the same switch, under the Overlay row ("Experimental · Operators F, S, W, X").
- Settings → Operators has a new "Experimental" section: the master switch first, the four operator rows under it while it is on.

## Not covered

- Voice commands (`command selection on`) reach the protocol state machine of the running session, not the UI settings, so they can still switch an experimental operator on for that session.
- Push-to-Act keeps its own Follow-up and Screenshot choices; the selection hotkey is unchanged.
- The CLI flags (`--selection-default` and the others) are unchanged; the switch is a UI setting.
- The overlay keeps its width (274 points) with fewer chips.

## Files

`ProtocolStateMachine.swift`, `UntypeUISettings.swift`, `NativeUntypeUILauncher.swift`, `UntypeMenuBarPanel.swift`, `UntypeSettingsWindow.swift`; tests `ExperimentalOperatorsTests.swift`, `ScreenshotOperatorTests.swift`.
