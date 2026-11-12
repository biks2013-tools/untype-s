# Plan 054 — Window text operator: send the whole text of the app's window

## Request
Send the entire content of the window, not only what a screenshot shows, so that for example an email whose text is not fully visible goes to the model together with the dictation.

## Decisions
- **Text, not a taller picture.** The window's text is read through Accessibility (`WindowTextCapture`): it includes what is scrolled out of view, is exact, and is small to send. A scrolling screenshot was rejected (slow, visible, fragile).
- **New operator, next to Screenshot.** `OperatorKey.windowText` (raw value `windowtext`, key **X**, default off), wired like Screenshot: chip in the overlay and windows, row in the menu-bar dropdown and Settings → Operators, per-turn option, `--windowtext-default` / `UNTYPE_WINDOWTEXT_DEFAULT`, setting `windowText`. Screenshot and Window text can be on together. The overlay is 26 points wider (274) for the tenth chip.
- **What is collected** (`WindowTextCollector`, pure): the values of the text elements (`AXStaticText`, `AXTextArea`, `AXTextField`, `AXComboBox`) of the front window in reading order, one per line. Not collected: menus, toolbars, scroll bars, button titles, password fields, the children of a text element (they repeat it), a line equal to the one before. The whole window is read (in a mail app: the folder and message lists too), not only the main content.
- **Limits.** 30 000 characters, 20 000 elements, 2 seconds, depth 80; beyond a limit the text is cut and the log says so.
- **Capture.** At the push-to-talk press, or when the operator is switched on mid-turn, off the main thread; the turn waits for it before its LLM call (`UntypeTurnContext.windowText()`). Only the character count is logged.
- **Use.** Refine / translate / combined: reference block from `018-window-text-context-template.txt` (`{app}`, `{text}`) appended to the input. Ask: `019-ask-window-text-template.txt` before the request; a release with no dictation asks about the window's text. Operator on but nothing captured: no LLM call, one warning (as Screenshot).
- **Not included.** Push-to-Act does not offer Window text. No voice command wording was tried for `windowtext`.

## Checks
- Capture measured on this Mac (counts only): M365Mail 2 891 characters in 44 ms, Teams 5 751 in 91 ms, Chrome 5 482 in 100 ms, cmux 3 214, Finder 1 483; none cut.
- Unit tests: `WindowTextOperatorTests` (8). Suite 353/353.
- On device, pending: the operator in real use, the wider overlay, the model's use of the text.
