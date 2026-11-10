# Plan 050 — Menu-bar dropdown tidy-up

## Request
Tidy the dropdown that opens from the menu-bar icon. The operator switches are also on the screen overlay: when the overlay is kept on screen they need not be in the dropdown; when it is not, they may stay, in a separate tab.

## Decisions
- `overlayAlwaysVisible` on: no tabs and no operator switches. The dropdown names the operators that are on ("On now"), offers the translation target while Translate is on, and points to the overlay.
- `overlayAlwaysVisible` off: two tabs under the header, **Controls** and **Operators · n** (n = operators on). The Operators tab has the nine switches (short names, the description as tooltip, the 1× mark, the translation target under Translate).
- Controls: aligned rows Hotkey (key + switch), Trigger (Push-to-talk / Push-to-listen), Mode; one hint line for the hotkey (a warning when it is off); the Push-to-Act hotkey when enabled.
- Removed from the dropdown: the Theme control (still in Settings → General and the main window's titlebar) and the separate Hotkeys reference section (folded into the hint line and the Operators tab footer).
- Behaviour unchanged: same bindings, `UntypeUIModel.update` / `toggleOperator`, same locking, same action rows and shortcuts. No hotkey, session or overlay code touched.

## Steps
1. Rewrite the body, controls and operators parts of `UntypeMenuBarPanel.swift`.
2. Check both states and the Operators tab with rendered snapshots (throwaway test), light and dark.
3. Docs: FR-55, design, configuration guide, pending on-device check.
