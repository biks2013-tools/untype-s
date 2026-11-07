# Plan 045 — Push-to-Act uses the whole field when nothing is selected

## Request
When Push-to-Act is used and no text is selected, the text of the active edit control should be treated as the selected text.

## Decisions
- Only when Accessibility reports the focused element with nothing selected (`AXSelectedText` empty). untype then reads the field's `AXValue` and sets `AXSelectedTextRange` to the whole text, so the field shows it selected and everything downstream (anchor, `ax-selection` replacement, focused-input fallback) works exactly as for a selection: the result replaces the field's whole text.
- The whole-field selection is used only when it is confirmed: the selection must be settable and must read back equal to the field's text. Otherwise nothing is changed and Push-to-Act reports "No selected text or field text found" as before.
- Apps without Accessibility selection support (terminals, some Electron apps), where untype falls back to ⌘C: unchanged. Their whole "field" cannot be identified safely (⌘A would select a terminal's whole buffer).
- Esc / cancel puts the original caret or selection back.
- The pop-up header says "Nothing selected · whole field, N characters".
- Push-to-talk's Selection operator is unchanged.

## Steps
1. `SelectedTextReader.selectWholeFocusedField()` and `WholeFieldSelection` (text, `restore()`).
2. `handleSelectionHotkey`: `.nothingSelected` → whole field; anchor captured on it; `showPushToActPanel(wholeField:)` restores on cancel; pop-up label.
3. Docs (FR-50).
