# Plan 052 — Refine the whole sentence when dictating in the middle of it

## Request
When the user dictates in the middle of a sentence, the refinement must cover the part of the sentence before the cursor and the part after it, not only the dictated words.

## Decisions
- **What is refined.** With Refine on, a push-to-talk / push-to-listen turn that starts with the cursor inside a sentence sends the whole sentence to the model: the part before the cursor, the dictation, the part after it (`SentenceSpan.compose`). The result replaces that sentence in the field. Without Refine, with Ask, or with a text selection in the field, nothing changes.
- **Sentence.** `SentenceSpan.around(caret:in:)` (pure): from the previous sentence end (`. ! ? ; …`, the Greek question mark, each followed by a space or the end; or a line break) to the next one. A decimal point is not an end. Nothing is captured when the cursor is at the start of a line or right after a finished sentence with nothing after it, or when a part is longer than 1500 characters.
- **Capture.** At the press, when the focused control reports no selection, `SentenceAnchor.capture` reads its text and cursor through Accessibility (no side effects). Skipped for terminals, password fields, and controls whose selection cannot be set. The span goes to `UntypeTurnContext`; the controller takes it once per turn.
- **Delivery.** `UntypeUIModel.prepareSentenceDelivery` (new `focusedInputSentenceDelivery` hook of `UntypeRuntimeFactory.makeForUI`) waits for the live keystrokes to land, checks that the text around the sentence is unchanged and the sentence still starts and ends with the captured parts, selects it (with the live-typed text inside), and the regular delivery inserts the refined sentence over the selection.
- **When the sentence cannot be selected** (control lost the focus, text changed, the control ignores the selection): the dictated part alone is delivered the regular way: the refined part when the model left both captured parts unchanged, the dictation as spoken otherwise. A warning is logged. The existing sentence is never touched in that case.
- **No setting.** The behaviour follows the Refine operator.

- **Selection with keys (after build 51).** In `M365Mail` (web view) the sentence was captured but not selected. `SentenceAnchor.selectRegion` now reports why, and where the control does not take an Accessibility selection it presses Right over the part after the cursor and Shift+Left over the whole sentence, then checks the reported selection range; on a mismatch it puts the cursor back and the dictated part alone is delivered.

## Checks
- Unit tests: `SentenceContextTests` (11). Suite 343/343.
- On device, pending: TextEdit / Notes / a browser text field, and `focused_input.ok=true`.
