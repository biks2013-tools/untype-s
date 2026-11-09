# Plan 046 — Clickable operator chips on the push-to-talk overlay

## Request
The operator indicators under the waveform of the push-to-talk overlay should be clickable, so the user can switch an operator with the mouse instead of its key.

## Decisions
- A click on a chip does exactly what its key does while holding push-to-talk (`UntypeUIModel.toggleOperator`), including the mid-turn screenshot capture when W is switched on.
- The panel stays non-activating and never becomes key (`becomesKeyOnlyIfNeeded`), so a click never takes the focus from the app being dictated into; `acceptsFirstMouse` makes the first click act.
- `ignoresMouseEvents` is now false; the transparent parts of the panel (around the trace and between the chips) let clicks through to the window behind.
- A click while the turn is being processed (after release) changes the operator for the next turn, the same as Settings or the menu bar.

## Steps
1. `UntypeOverlayController.createPanel`: mouse events on, `UntypeOverlayHostingView` (accepts first mouse).
2. `UntypeOverlayView`: each chip a plain `Button` calling `controller.toggleOperator(letter:)`, with a tooltip.
3. Docs (FR-51, design), on-device check item.
