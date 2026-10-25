# Plan 037 — Processing wave, per-operator persistence, Follow-up and Selection operators

Date: 2026-10-25

## Request

1. Keep the waving overlay on screen while the model refines, translates or
   answers, so the user sees that work is in progress.
2. For every operator, the user chooses in Settings whether a change lasts for
   **one push-to-talk turn** or **until changed again**. For example, Ask is
   requested every time, while Translate stays on until switched off.
3. A **Follow-up** operator: Ask also sends the conversation so far, so the
   model can refine or extend its previous answer. It applies to Ask only.
4. A **Selection** operator: the text selected in the active app at press time
   is included in what refine, translate or Ask receive.

User decisions (2026-10-25):

- The role of the selection is a user setting: either **material** (it is
  processed, and the result replaces it) or **context** (it is reference
  only, and the result is inserted after it).
- Reading the selection: Accessibility first. Where that fails, a ⌘C is sent
  and the clipboard is restored right after.
- With Follow-up off, every Ask starts a new conversation.

## Design

### 1. Processing wave

- `stopHotkeySession` used to schedule `hideAfterDelay()` (1.2 s) right after
  showing the `finalizing` phase.
- The overlay now stays in `finalizing` (the breathing wave) until the stop
  completes, which is when delivery has finished. It then hides after the
  usual short delay.

### 2. Per-operator persistence

- New UI setting `perTurnOperators: [String]`, optional in `ui-state.json`.
  The default is `["ask", "followup", "selection"]`.
- A per-turn operator is switched off again when a push-to-talk turn is
  delivered (the stop completion of `ui-hotkey-release`). It is reset before
  the next warm session is started, so that session already has it off.
- Settings → General → Operators: every row has a "This turn only / Until
  changed" picker. The dropdown marks per-turn operators with "1×".

### 3. Follow-up (`OperatorKey.followup`, key F)

- `AskConversation` is a thread-safe store owned by the UI model and injected
  into every runtime. It must outlive the per-turn runtimes.
- With Follow-up on, the Ask message is prefixed with
  `015-ask-conversation-template.txt` (`{history}`), which renders the earlier
  `User:` / `Assistant:` exchanges.
- With Follow-up off, the conversation is cleared before the call.
- A successful Ask appends its exchange, keeping at most 20 exchanges.
- The dropdown has a "New conversation" entry.

### 4. Selection (`OperatorKey.selection`, key S)

- `SelectedTextReader` reads the selection.
  - At every press it reads `AXSelectedText` of the focused element (no side
    effects). It cannot read it after live typing has started, because the
    typing replaces the selection.
  - When Selection is on and AX returns nothing, it falls back to ⌘C: it posts
    a marked synthetic event, waits up to 300 ms for the pasteboard to change,
    and restores the previous pasteboard items.
- Live typing is paused until the capture finishes.
- In the context role, a Right-arrow keystroke collapses the selection first,
  so the output is inserted after it.
- `UntypeTurnContext` is a thread-safe store owned by the UI model and injected
  into every runtime. It carries the selection and its role, which is set from
  the UI setting `selectionRole`: `material` (the default) or `context`.
- Controller behavior:
  - Ask: the message is prefixed with `014-ask-selection-template.txt`
    (`{selection}`).
  - Material with refine or translate: the processed text is the selection
    followed by the dictation, if any.
  - Context with refine or translate: `013-selection-context-template.txt`
    (`{selection}`), a reference-only block, is appended to the refine input,
    the rendered translation prompt or the composite input.
- A release with no dictated text still submits when a selection can be
  processed (material, or any Ask): `submitWithoutDictation`.

### Shared changes

- `--followup-default`, `--selection-default` and their `UNTYPE_*` variables.
- JSONL operator map and status report.
- Chips in the main window, compact view and overlay; dropdown rows; Settings
  toggles; hotkey letters F and S.
- Prompts 013–015 are provisioned, validated and editable (Settings → Prompts),
  and hot-reloaded.
- Push-to-talk wiring and focused-input delivery are unchanged, except for
  pausing live typing until the selection capture finishes.

## Verification

- Unit tests:
  - controller handling of the selection roles, Ask with selection, Follow-up
    history and clearing;
  - the selection-only submission;
  - config flags and prompt validation;
  - the per-turn reset policy;
  - the settings round trip.
- Signed build and manual checks:
  - the wave stays until delivery;
  - Ask resets after one turn and Translate persists;
  - a Follow-up refines the previous answer;
  - a selection is translated and replaced (material) or used as context;
  - `focused_input.ok=true`.
