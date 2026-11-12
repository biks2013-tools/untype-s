# Plan 059 — Pinned chips on the overlay

## Request
The user works mostly with a few operators (R, T, A and I). From the overlay itself they want to pin their favourites quickly, so that at rest the overlay shows only the pinned chips; when it is in use, all chips show.

## What the user sees
- **Pin.** With the mouse on a chip (the tray is open), a small pin appears on the chip's corner. Clicking the pin pins or unpins the chip; clicking the chip still switches the operator. The tray's lines say "Refine · pinned" for a pinned chip and "Pin Refine — Always shown, also at rest" / "Unpin Refine — Shown only when the mouse is on the overlay" on the pin.
- **At rest** (idle or under a card, the mouse away from the overlay): only the pinned chips, centred, plus any chip that is on, so an active operator is never hidden.
- **In use:** all chips, as soon as the mouse enters the overlay (before it reaches a chip, so the chips do not move under it) and while dictating or processing.
- **Nothing pinned** (the default): all chips, as before.

## Decisions
- **Pinning is only about what shows.** It does not switch operators on or off.
- **Saved with the UI state** as `pinnedOperators` (letters, kept in chip order); no Settings field.
- **Pin wins over the chip** in the mouse hit test where they overlap; pins react only while the tray is open.

## Checks
- Unit test `pinnedOperatorsAreKeptInChipOrderAndRoundTrip`; full suite.
- On device: see `Issues - Pending Items.md`.
