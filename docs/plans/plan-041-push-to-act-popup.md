# Plan 041 — Push-to-Act pop-up

## Request
Rename the selection hotkey (Ctrl+Opt+`) to **Push-to-Act**. Pressing it opens a pop-up where the user can change the model used for the action, see and change the active flags, and change the translation language; Enter runs the action.

## Decisions (confirmed with the user)
- Key: the existing selection hotkey (`selectionHotkey`, default `Control+Option+``); stored setting names unchanged.
- Models: Primary / Alternative LLM (the configured pair; Alternative hidden when not configured).
- Persistence: pop-up changes apply to the current run only.
- Languages: the existing translation directions (opposite, to English, to Greek).

## Steps
1. `PushToActChoice` (core, `SelectionHotkey.swift`): built from `UntypeUISettings`; R/T/A/F/C/L toggles, translation policy, `canRun`, `operators` (Selection + Input on). `SelectionHotkeyPlan.operators` delegates to it.
2. `UntypeRuntimeFactory.runSelectionHotkey(translationPolicy:)` overrides the configured direction; latency trigger `push-to-act`.
3. `PushToActPanel.swift`: non-activating, key-capable borderless `NSPanel` with a SwiftUI view (selected text preview, Model / Operators / Translation pills, Run/Cancel). Keys: Enter/keypad Enter run, Esc cancel, r t a f c l toggle, 1–3 translation. Resign-key cancels.
4. `UntypeUIModel.handleSelectionHotkey`: guards → read selection → `showPushToActPanel`; Enter → `runPushToAct`; cancel re-activates the target if needed; `handleHotkeyPress` cancels an open pop-up first.
5. Rename user-facing labels (Settings group, caption, menu bar line, log lines).
6. Tests: `PushToActChoice` per-run edits, Alternative unavailable.
7. Docs: FR-45, project-design, configuration guide.

## Verification
`swift build`, `swift test` (303/303), signed+notarized build 34 installed; manual: select text → Ctrl+Opt+` → pop-up → change options → Enter → selection replaced; newest `release-latency.jsonl` record `trigger: "push-to-act"`, `focused_input.ok=true`; push-to-talk Ctrl+` unaffected.
