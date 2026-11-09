# Plan 048 — Drag handle on the dictation overlay

## Request
A small handle on the overlay that lets the user drag it anywhere on the screen.

## Decisions
- A small grip (`line.3.horizontal` in a dark capsule) in the top-left corner of the overlay. It takes the mouse like the chips (the panel ignores the mouse elsewhere), brightens on hover, and its tooltip reads "Drag to move · double-click to reset".
- Dragging moves the panel with the mouse (manual drag on `mouseDown`/`mouseDragged`/`mouseUp`, so the panel never becomes key and the focus stays in the app being dictated into). While a drag is in progress the mouse poll does not switch `ignoresMouseEvents`, so a fast drag that outruns the handle is not lost.
- The position (bottom-left corner, global screen points) is saved on mouse-up as `overlayPosition` in `ui-state.json` and used every time the overlay appears; it no longer jumps to the screen under the mouse. If the saved place is on no connected screen, the default (bottom centre of the screen under the mouse) is used.
- Double-click on the handle forgets the position (`resetOverlayPosition`) and puts the overlay back at the bottom centre.

## Steps
1. `UntypeOverlayPosition`, `UntypeUISettings.overlayPosition`, patch `overlayPosition` / `resetOverlayPosition`, persisted field.
2. `UntypeUIModel.setOverlayPosition(_:)` (layout only, no reconfiguration).
3. `UntypeOverlayController`: `savedFrame()`, `beginDrag/continueDrag/endDrag`, `resetPosition()`; handle in the hover/hit regions.
4. `UntypeOverlayView.dragHandle` + `UntypeOverlayDragArea` (NSView for the mouse).
5. Test; docs (FR-53, design, configuration guide).
