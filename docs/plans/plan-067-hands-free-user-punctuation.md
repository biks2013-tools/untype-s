# Plan 067 — Hands-free: the user ends the sentences

Date: 2026-11-14 · Status: implemented behind a switch that is off by default; not yet used in the installed app

## Request
In a hands-free turn (a tap of the hotkey: untype listens while the user also edits) untype should not decide where sentences end:
1. no full stop when the speaker pauses; full stops are the user's;
2. a capital at the start of what is written only when a full stop precedes it in the text, so the text around the caret must be read;
3. a space before the words when they start right after text (for example right after a full stop); none when a space precedes or the caret is at the start of a line;
4. optionally, a full stop after a pause of three to four seconds.
All of it "nice to have": nothing that works today may be damaged.

## Where the full stops and capitals come from
The speech provider ends an utterance at a pause, closes it with a full stop and starts the next with a capital. `LiveFocusedInputTyper` types those utterances one after the other, joined with a space.

## Design
- Two switches, Settings → Push-to-Talk → "Hands-free (after a tap)" (`handsFree` in `ui-state.json`, both off by default): **I end the sentences** (`userPunctuates`) and **Full stop after a long pause** (`periodAfterPause`, only with the first). With both off no code path changes.
- `HandsFreePunctuation.swift`:
  - `LiveUtteranceShaper.shape(utterance, context:)`: drops the provider's closing full stop (question mark, exclamation mark and ellipsis stay); capital when the last written character before the caret is `.`, `!`, `?`, `…` (or `;` before Greek text), or nothing is before it; lower case otherwise, except "I" and words with more capitals; a space when the character right before the caret is not white space or an opening bracket or quote.
  - `HandsFreeTextFlow`: the text of the turn. The context is read once per utterance, when its first words arrive and before they are typed, so a full stop the user typed, or a caret the user moved, between utterances is taken into account. Finished utterances are never rewritten.
  - `LiveCaretContextReader`: the 80 characters before the caret and whether the line ends after it, through Accessibility (`AXSelectedTextRange`, `AXStringForRange`, else `AXValue`); nil for another app's control, a password field, or a control that does not report (terminals). With nil the first utterance is typed as recognised minus its closing full stop, and later ones follow from what untype itself wrote.
  - Pause: measured from the arrival of an utterance's final text to the first words of the next; 3 s there is about 3.5–4 s of silence. A full stop is written (". " and a capital) only when the caret still stands right after the text untype wrote last, at the end of its line, and that text ends in a letter or digit. It is written when the next words come, never by a timer, so nothing is typed while the user is elsewhere.
- `LiveFocusedInputTyper.leavePunctuationToUser(pausePeriodSeconds:)` is called when a turn becomes hands-free (`beginHandsFreeTurn`). Words already typed in the first moments are rewritten by the same rules.
- Finishing the turn: when the delivered text is the spoken text unchanged (no Refine, Translate or Ask), `reconcile` leaves the field as it is, with the user's edits, and reports the delivery as done (so Enter still sends). When an operator changed the text, the text is edited into the processed result as before.

## Limits (known, accepted)
- A name at the start of an utterance inside a sentence is written in lower case: the provider capitalises every first word and the two cannot be told apart.
- Full stops the provider writes inside one utterance (the speaker did not pause) stay.
- Editing during an utterance (not between utterances) is as unsafe as before: a revision of the words being recognised deletes backwards from the caret.
- With Refine on, the processed text replaces what was typed, counted from the caret; the user's own edits during the turn are not known to untype (as before).
- Held push-to-talk is unchanged.

## Verification
- `swift build`; 441/441 tests (11 new in `HandsFreePunctuationTests`: shaping rules in English and Greek, the flow across utterances, the pause rule and its guards, settings default and merge).
- Not done: any turn in the installed app. The Accessibility reader and the keystroke path can only be checked there.

## Restore point
Commit `44008c0` (build 66 as installed) precedes this change; the change is confined to `HandsFreePunctuation.swift`, `LiveFocusedInputTyper.swift`, the settings plumbing and one hook in `beginHandsFreeTurn`.

## After the first try in the app (2026-11-14, builds 68 and 69)
- Reported: after a short pause the next words were written right against the last letter, with a capital. The words in the report itself ("τοΓράμμα", ".Κενό") show the cause: the control typed into answers the caret question as an empty field would (nothing before the caret), so every utterance was treated as the start of the text.
- Build 68: an answer "nothing before the caret" is not believed once untype has written into the field (or the user has typed in this turn); terminals are not asked at all; each answer is logged without text (`hands-free: before the cursor: …`).
- Build 69: the user's own keys are watched during a hands-free turn with the switch on (`UserKeystroke`, `UserTypingTrail`; the Enter/Esc key tap reports every other key press and left click, never swallowing them, and nothing of it is logged). Where the field does not tell, the text before the caret is untype's last words plus what the user typed after them, so a full stop typed by hand gives a space and a capital. An arrow key, a click, or a shortcut with Command or Control means the caret may be elsewhere: then only untype's own text is used (a space, lower case). Where the field does report its text, the field is what counts.
- 446/446 tests. Not yet confirmed in the app.
