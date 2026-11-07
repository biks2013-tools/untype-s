# Plan 043 — Push-to-Act remembers its choices

## Request
Push-to-Act should always remember the choices made in its pop-up, so the next time it opens they are already set. Push-to-Act and push-to-talk / push-to-listen are two separate modes.

## Decisions
- Push-to-Act gets its own remembered choices (model, R/T/A/F/C, translation direction); the push-to-talk / push-to-listen operators are a separate set and are never changed by Push-to-Act.
- Saved on Run (Enter or the Run button); Esc / cancel saves nothing.
- First use (nothing saved yet): start from the push-to-talk operators, as before.
- A remembered model that is no longer configured opens as Primary.

## Steps
1. `PushToActPreferences` (Codable) in `SelectionHotkey.swift`; `PushToActModel: String`.
2. `UntypeUISettings.pushToAct` (+ patch, persisted `pushToAct`, kept in `loadForUI` derivation).
3. `PushToActChoice` init from `settings.pushToAct`; `preferences`.
4. `UntypeUIModel.rememberPushToActChoice` on Run: merge + save only (no hotkey/runtime reconcile, so push-to-talk is not disturbed).
5. Pop-up / Settings caption text; test; docs (FR-48); build 38.
