# Plan 040 — Selection hotkey (process the selected text and replace it)

## Request
"Can we define Ctrl+Opt+` as a hotkey to refine/translate/ask the selected text and replace it with the result?" The user chose: use the operators that are active at that moment.

## Behaviour
- A second hotkey, `selectionHotkey` (default `Control+Option+``), on by default (`selectionHotkeyEnabled`), set in Settings → Selection hotkey.
- On press, untype reads the selection of the app in front. It uses Accessibility `AXSelectedText` first and falls back to a synthetic ⌘C, restoring the pasteboard. The microphone is not opened and no STT session is involved.
- The selection is processed as **material**, with the active operators: Refine, Translate (alone or combined), Ask (with Follow-up), and Alternative (L, the alternative LLM). Clipboard applies if it is on. Focused-input delivery is always on for the run, so the result replaces the selection.
- Nothing happens, with a warning event, when:
  - none of R/T/A is on;
  - no external app is in front;
  - nothing is selected;
  - a push-to-talk turn is recording or being delivered;
  - a manual session is running;
  - a previous selection run is still in flight.
- The overlay shows the processing wave until delivery.
- A release-latency record is written with `trigger=selection-hotkey`, `text_source=selection`, `stt_provider=none`.

## Design
- `SelectionHotkeyPlan` (new file `SelectionHotkey.swift`):
  - `operators(for:)` returns the active operators with `selection` and `input` on, or nil without R/T/A.
  - `turnContext(selectedText:)` sets the selection role to material.
- `UntypeRuntimeFactory.runSelectionHotkey(...)` builds a one-shot `VoiceAgentProtocolController`. It uses the primary and alternative clients, the prompts and the focused-input delivery, then runs `submitWithoutDictation()` (the existing "selection without dictation" path), ends the session and writes the latency record.
- `UntypeUIModel.handleSelectionHotkey` handles the guards, reads the selection, resolves the config from `sessionArguments()` and runs the factory in a detached task. It re-activates the target app before delivery when needed.
- `UntypeHotkeyMonitor`:
  - a second descriptor, checked on key-down in the Quartz event tap and the NSEvent monitors, only while push-to-talk is not held;
  - autorepeat is swallowed;
  - no Carbon registration, because the Carbon handler does not distinguish hotkey IDs and would treat it as a push-to-talk press.
- Push-to-talk descriptors, shared state and the press/release paths are unchanged.
- Settings:
  - `selectionHotkeyEnabled` and `selectionHotkey` are persisted, and optional in `ui-state.json`, so older files load the defaults;
  - normalized like `hotkey`;
  - rejected when equal to the push-to-talk hotkey in any modifier order;
  - a change reconfigures the hotkey monitor (`hotkeyMonitorConfigurationChanged`) without a warm-session restart.
- UI: a Settings group with toggle, field and caption, plus a line in the menu-bar dropdown's Hotkeys section.

## Limits
- It needs the push-to-talk hotkey listener (Push to talk → Enabled), because it runs on the same event tap.
- The replacement is plain text. Rich formatting of the selection is not kept.

## Verification
- `SelectionHotkeyTests` (7): operator plan, refine delivery, Ask with the alternative LLM, settings defaults and round trip, collision check, monitor reconfiguration.
- `swift test`: 300/300.
- Manual: select text, press Ctrl+Opt+`, check that the text is replaced and that the newest `release-latency.jsonl` record shows `trigger=selection-hotkey`, `focused_input.ok=true`. Check that push-to-talk (Ctrl+`) still works.
