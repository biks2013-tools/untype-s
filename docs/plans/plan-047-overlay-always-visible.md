# Plan 047 — Keep the dictation overlay visible

## Request
A settings option that keeps the dictation overlay always visible, even when the user is not dictating.

## Decisions
- Settings → Appearance → **Keep overlay visible** (`overlayAlwaysVisible` in `ui-state.json`, default off). A UI setting like the theme: saved through `updateLayout`, so it never reconfigures the hotkeys or the warm session. No CLI flag or environment variable (UI-only, like the theme).
- Idle look: a flat, dim line instead of the waveform, with the operator chips (clickable, with tooltips). Recording, processing and notices look as before; afterwards the overlay returns to idle instead of hiding.
- While visible, the overlay moves to the screen under the mouse when a turn starts.
- Clicks: a device probe showed that a clear panel that takes mouse events blocks clicks in its transparent area (the window server does not pass them through). The panel now ignores the mouse except while the pointer is over a chip; a 30 Hz poll of the mouse position switches `ignoresMouseEvents` and sets the hovered chip for the tooltip (a panel that ignores the mouse gets no tracking events). This also fixes the dead zone of builds 42–43.

## Steps
1. `UntypeUISettings.overlayAlwaysVisible` (+ patch, merge, derivation, persisted field, coding key).
2. `UntypeOverlayController`: `applyAlwaysVisible()`, `hideNow()` keeps the idle overlay, `show` follows the mouse's screen, mouse poll (`followMouse`, `chipFrames`, `hoveredChip`); idle drawing in `UntypeOverlayView`.
3. Settings toggle; applied at launch and on change.
4. Test `OverlayAlwaysVisibleTests`; docs (FR-52, design, configuration guide).
