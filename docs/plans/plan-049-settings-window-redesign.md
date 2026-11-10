# Plan 049 — Settings window redesign

## Request
Redesign the Settings screen: better organised, in sections that are easier to read and navigate, and looking like the settings window of a macOS app.

## Decisions
- System Settings layout: sidebar of panes with coloured icon tiles on the left (running to the top of the window, under the traffic lights), pane title and a grouped form (`Form.formStyle(.grouped)`) on the right. Native rows (`Toggle`, `Picker`, `TextField`, `LabeledContent`), section headers and footers for the explanations.
- Panes (sidebar groups): General | Push-to-Talk, Push-to-Act | Speech, Operators, Language Models, Prompts | Permissions & Keys. Every setting of the old single scrolling page is kept; the read-only "Session" summary is shortened (its values are editable in Speech).
- Moves: Translate direction from Protocol to Operators → Options; the three LLM groups into Language Models; credentials and permissions together; "Hold to talk" becomes a two-option picker; operators show their key and a one-line description; Processing and Delivery operators are separate sections.
- New: overlay position Reset in General (same as double-clicking the grip).
- `settingsTab` ids `general` and `prompts` keep working; unknown ids open General. The Prompts pane stays mounted so unsaved drafts survive pane switches; its file list uses the inset style (no second sidebar look).
- Behaviour unchanged: the same bindings and `UntypeUIModel.update` / `updateLayout` calls, the same locking while a session is active (now also stated in the pane header).

## Steps
1. Rewrite `UntypeSettingsWindow.swift` (window, `UntypeSettingsPane`, `UntypeSettingsView`).
2. `UntypeUIModel.resetOverlayPosition()`.
3. Check each pane with a window snapshot (throwaway test), light theme.
4. Docs: FR-54, design, configuration guide (pane table, updated paths).
