# Plan 071 - Text edited during the dictation is what gets processed

Date: 2026-11-18. FR-76.

## Why
User report: with Translate on, in a hands-free turn, the user changed something in the middle of the dictated text and
then went on dictating at the end. When the turn ended, the translated text was wrong: the correction was lost, and
what was dictated in the middle stood where the end of the text was when it was dictated.

Cause: the live text is typed where the caret is, but the turn's result was built from the transcript alone, in the
order the words were spoken, and written by pressing Backspace once per typed character from wherever the caret stood.
The field was never read. So the user's own typing was not part of the model's input, an insertion in the middle came
out in spoken order, and the Backspaces erased the wrong characters. The same held for Refine and Ask. The event log
of the reported turns (2026-11-17 20:37 to 20:39) shows them in cmux, a terminal, hands-free, with Translate.

## What changes
When a turn that Refine, Translate or Ask processes ends, untype first finds out what the field holds of the turn's
text. If it is what untype typed, with the caret right after it, nothing changes. If the user changed it or moved the
caret, the text in the field is what the model gets, and the result replaces that text in the field.

How the field is read (`TurnFieldAnchor`, captured when the turn starts):

| Field | Read back | Replaced |
|---|---|---|
| A control that reports its text and caret through Accessibility | the text between what stood before and after the caret at the start | that text is selected (Accessibility, or arrow keys) and the result inserted over it |
| The prompt box of a terminal coding agent (Claude Code; `TerminalPromptParser`) | the prompt, without what it held at the start | Right to the end of the prompt, Backspace over the turn's text, the result typed (pasted when it has a line break) |
| Anything else (a plain shell, a control that reports nothing) | what the keys tell (`TypedTailModel`): untype's own keystrokes and what the user typed or erased at the end | Backspaces and typing, as before |

Where the field cannot be read and the user moved the caret or used a shortcut, the place of the live text is not
known: the field is left as the user has it, the overlay says "Edited by hand: left as it is", and the turn's delivery
is recorded as failed (`edited_text_not_replaced`). Before, Backspaces were pressed at the wrong place.

A terminal does not report its caret. There, the turn counts as edited when the prompt does not hold the typed words
or the user pressed any key or clicked during the turn (known in hands-free turns, from the key tap).

## Changes
- `TurnFieldText.swift` (new): `TurnFieldReading`, `TurnFieldRegion` (pure), `TypedTailModel` (pure),
  `TurnFieldAnchor` (capture, `read`, `replace`).
- `TerminalPrompt.swift`: `TerminalPromptParser.box(in:)` and `TerminalPromptAnchor.currentBox()` tell an empty prompt
  box from no box.
- `LiveFocusedInputTyper`: keeps a `TypedTailModel`; `reconcile` edits from what the field holds, leaves the field
  alone when nothing processed the text, and returns `.untouched` when the place of the text is not known.
- `UntypeTurnContext.setFieldTextReader` / `editedFieldText()`; `VoiceAgentProtocolController.processSection` asks for
  it when Refine, Translate or Ask is on, nothing is selected and the section is not empty. An edited turn is not
  refined together with the sentence around the caret (FR-58): the turn's own text is processed.
- `SentenceDeliveryPlan`: `.typed`, `.paste`, `.untouched`; `UntypeRuntimeFactory` maps them to delivery results.
- `UntypeUIModel`: `turnFieldAnchor` captured in `startLiveTyping`, `editedTurnText()` (waits until the last keystrokes
  are in the field, at most 0.6 s), replacement in `prepareSentenceDelivery`. The key tap of a hands-free turn now
  reports the user's keys in every hands-free turn typed live (before: only with "I end the sentences"), and ignores
  the push-to-talk hotkey itself.

## Not changed
A turn nobody edited takes the same path as before (the field is read once to confirm it). Turns without Refine,
Translate or Ask never touch the field at the end. Push-to-talk press and release, the audio gate and the overlay are
not touched.

## Limits
- A terminal that shows no prompt box (a plain shell, another program): only typing and erasing at the end is
  followed; after an arrow key, a click or a shortcut the text is left as it is.
- In a terminal prompt that already held text when the turn started with the caret in the middle of it, the whole
  prompt is processed.
- A change the user makes outside the turn's text (earlier in the document) while dictating is not followed.
- Esc (discard) after the caret was moved in a field that cannot be read leaves the typed text in place.
- An accented letter typed with a dead key is seen without its accent by the key tap (unreadable fields only).

## Verification
`swift build`; 474/474 tests (11 new in `EditedTurnTextTests`: the controller sends the field's text, regions in a
field and in a prompt, the empty prompt box, the tail model). cmux was probed through Accessibility: its terminal
panes are `AXTextArea` elements whose text holds the prompt box. Reading the field, selecting and the keystrokes were
not run in an app: to be checked on the device.

## On the device (build 74, 2026-11-18, from the event log)
- Unedited turns in a Claude Code prompt in cmux: read back as typed, delivered the regular way.
- One edited turn with Translate in the prompt: read (136 characters), erased, the result pasted (it had a line break).
- One edited turn with Translate in a field that cannot be read (M365Mail): left as it is, with the notice.
- Defect: an edited hands-free turn that nothing processes ended as `edited_text_not_replaced` when the delivered text
  differed from the typed one, so Return was not pressed after Enter. Fix (build 75): `reconcileLiveInput` reports such
  a turn as delivered; only turns whose text is processed (`turnTextIsProcessed`) can end as not replaced.
