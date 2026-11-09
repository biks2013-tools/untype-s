# Plan 045 — Push-to-Act uses the whole field when nothing is selected

## Request
When Push-to-Act is used and no text is selected, the text of the active edit control should be treated as the selected text.

## Decisions
- Only when Accessibility reports the focused element with nothing selected (`AXSelectedText` empty). untype then reads the field's `AXValue` and sets `AXSelectedTextRange` to the whole text, so the field shows it selected and everything downstream (anchor, `ax-selection` replacement, focused-input fallback) works exactly as for a selection: the result replaces the field's whole text.
- The whole-field selection is used only when it is confirmed: the selection must be settable and must read back equal to the field's text. Otherwise nothing is changed and Push-to-Act reports "No selected text or field text found" as before.
- Terminals (build 41, user report: in cmux "No selected text or field text found"): terminals expose only the screen as one read-only `AXTextArea` (cmux: `AXSelectedText` unsupported, `AXSelectedTextRange` not settable), so the whole-field selection cannot work there. The "edit box" is the prompt of a terminal coding agent (Claude Code): the `❯` lines between two horizontal rules (the top one may carry a label, `──── folder ─`; `❯` is followed by a no-break space). After the ⌘C read finds nothing, untype parses that box from the focused text area (`TerminalPromptParser`; terminal-wrapped lines joined with a space, user line breaks kept). User's choice of replacement: on Run, one Backspace per character (the cursor is expected at the end of the prompt, as after typing), then the screen is re-read for up to 1.5 s; empty prompt → the result is delivered by ordinary focused-input delivery; not empty (cursor was elsewhere) → nothing is typed, warning, the result is put on the clipboard. The pop-up says "Nothing selected · terminal prompt".
- Esc / cancel puts the original caret or selection back.
- The pop-up header says "Nothing selected · whole field, N characters".
- Push-to-talk's Selection operator is unchanged.

## Steps
1. `SelectedTextReader.selectWholeFocusedField()` and `WholeFieldSelection` (text, `restore()`).
2. `handleSelectionHotkey`: `.nothingSelected` → whole field; anchor captured on it; `showPushToActPanel(wholeField:)` restores on cancel; pop-up label.
3. Terminal prompt: `TerminalPromptParser`, `TerminalPromptAnchor`, `SelectedTextReader.readTerminalPrompt()` / `pressBackspace(times:)`, `terminalPromptReplacer` in the launcher.
4. Docs (FR-50).
