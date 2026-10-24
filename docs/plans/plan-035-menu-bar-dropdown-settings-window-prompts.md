# Plan 035 — Menu-bar dropdown, Settings window, editable hot-reloaded prompts

Date: 2026-10-24

## Request

1. The menu-bar icon opens a compact dropdown that shows only the switches a user
   actually flips day to day (hotkey on/off, push-to-talk vs push-to-listen,
   protocol mode, the four operators, translation target), not the whole window.
2. The dropdown lists the available hotkeys and offers **Transcript…**, **History…**
   and **Settings…** entries, each with a keyboard shortcut (⌘1, ⌘2, ⌘,).
3. A dedicated **Settings** window holds the full settings (formerly the main
   window's inspector) plus a **Prompts** tab that shows the refinement and
   translation prompts, lets the user edit them, and hot-reloads them.

## Design

- `PromptFileStore` (new, `UntypeCore`): descriptors for the nine prompt files in
  `~/.tool-agents/untype/prompts/` (title, group, required, required placeholders,
  default), validated read/write (`0600`, atomic), reset-to-default, and a
  fingerprint (mtime + size) used by `PromptFileWatcher` (1 s poll, main actor).
  The validation rules mirror `ConfigResolver.resolvePromptConfig`, so a save from
  the editor can never produce a file that breaks session start.
- Hot reload: the model owns a `PromptFileWatcher`. On any change (editor save or
  an external editor) it logs `prompts.reloaded: <files>` and, when the hotkey
  session is only **warm** (no turn in progress), recycles it through the existing
  `stopHotkeyWarmSession(restartAfterStop: true)` path so the next turn already
  uses the new prompts. During a turn nothing is interrupted: the warm session is
  restarted after release anyway and re-resolves the prompts then. A running
  manual session picks the prompts up at its next start (logged).
- `UntypeMenuBarController`: left click toggles an `NSPopover` (transient) hosting
  `UntypeMenuBarPanel`; right click shows a small menu (Transcript, History,
  Settings, Quit). The attached/"popped out" window modes are removed: the main
  window is an ordinary window opened from the dropdown at the requested tab,
  and it reopens at launch if it was open at quit or setup is needed.
- Settings window (`UntypeSettingsWindowController` + `UntypeSettingsView`):
  tabs **General** (the former inspector groups, unchanged bindings) and
  **Prompts** (editor per prompt file with Save / Revert / Reset to default,
  placeholder hints, validation errors inline, unsaved-change marker; external
  changes refresh the editor unless it has unsaved edits).
- Main window: the inspector pane and its toggle are replaced by a Settings
  (gear, ⌘,) button; the detach button disappears. Application menu gains
  Settings… (⌘,) and a Window menu with Transcript (⌘1) / History (⌘2).
- Session-shaping controls become editable while the hotkey session is only warm
  (`UntypeUIModel.canReshapeSession`); they stay locked during a recording /
  finalizing turn or a manual session. Changing them already restarts the warm
  session through `update(_:)`.

## Push-to-talk / focused-input guardrails

No change to `UntypeHotkeyMonitor`, `HotkeySessionControl`, the press/release
handlers, the overlay or the delivery path. The only new session interaction is
the warm-session recycle, which reuses the five-minute recycle code path and is
skipped while `hotkeyPressed` or `captureState != "warm"`.

## Verification

- `swift build`, `swift test` (new `PromptFileStoreTests`).
- Manual: dropdown opens/closes, toggles persist, ⌘1/⌘2/⌘, open the right
  window/tab, prompt edit → `prompts.reloaded` + warm recycle in Events, next
  push-to-talk turn uses the new prompt, `focused_input.ok=true` in
  `~/.tool-agents/untype/release-latency.jsonl`.
