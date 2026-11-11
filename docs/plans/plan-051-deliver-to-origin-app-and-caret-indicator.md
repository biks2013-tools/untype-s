# Plan 051 — Deliver to the app the dictation started in; processing line at the caret

## Request
1. The text of a dictation goes to the app it started in, not to whichever app is in front when it is delivered, so the user can move to another app while dictating.
2. The line shown while the turn is processed (after the dictation ends) appears at the text cursor of the active field.

## Decisions
- **Origin app.** A push-to-talk / push-to-listen turn already records the app in front at the press (`sessionFocusedInputApplication`). `prepareFocusedInputDelivery` now brings that app to the front whenever another app is in front at delivery (before: only when untype itself was in front), waits until it is in front (up to about a second), delivers as before, then gives the focus back to the app the user had moved to (`finishFocusedInputDelivery`, new `focusedInputCompletion` hook of `UntypeRuntimeFactory.makeForUI`). If the origin does not come to the front, a warning is logged and the text goes to the app in front, as before. Manual sessions and Push-to-Act are unchanged.
- **Scope of "where it started".** The app, with its own focused field and caret. A field changed inside the same app during the dictation is not tracked.
- **Processing line.** New `CaretIndicator.swift`: `CaretLocator` (Accessibility: focused control → caret rectangle), `CaretIndicatorLayout` (placement, pure), `CaretIndicatorController` (a 44×14 click-through panel with a travelling wave, re-placed every 0.2 s off the main thread). The overlay controller runs it during the `finalizing` phase. While it is visible the overlay steps back: hidden, or its idle look when "Keep overlay visible" is on. Where the focused control reports no caret (terminals, many Electron apps such as Teams), nothing changes: the overlay shows the processing wave as before.
- **Caret rectangle.** AppKit text views report the rectangle of an empty range one line too high (measured in TextEdit), so the caret is taken from the character after it, then the character before it (start of the next line after a line break), and the empty range only for an empty field.

## Checks
- Probes on this Mac: activating another app from a background process works (0.09 s); `CaretLocator` gives the right line and column at six caret positions and in an empty document (TextEdit, in the background).
- Unit tests: `CaretIndicatorTests` (6). Suite 332/332.
- On device, pending: both behaviours in real use, and `focused_input.ok=true`.
