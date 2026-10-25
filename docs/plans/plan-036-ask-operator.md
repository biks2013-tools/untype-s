# Plan 036 — Ask operator: dictate a request, get the model's answer

Date: 2026-10-25

## Request

Add one more operator flag. When it is on, what the user says is a request to
the model ("write…", "explain…", "summarize…"), and untype returns the model's
answer instead of the dictated text. The prompt must be suited to that.

## Design

- **Operator.** `OperatorKey.ask` / `OperatorState.ask`. It is an optional key
  in `state.json`, so older files load `false`, as `input` already did.
- **Defaults.** `--ask-default on|off` / `UNTYPE_ASK_DEFAULT` (default `off`),
  with the same setting-source rules as the other operators. The UI setting
  `ask` is optional in `ui-state.json`.
- **Processing** (`VoiceAgentProtocolController.processSection`): with `ask`
  active, one call goes to the asker.
  - System prompt `010-ask-system.txt`, user message `011-ask-user-template.txt`
    (`{text}`).
  - With Translate on, `012-ask-translated-user-template.txt` (`{text}`,
    `{target_language}`) instead, so the answer is in the target language from
    the translation policy.
  - Refine and the composite/translate calls are skipped.
  - Fail-open: the dictated text is delivered, with a warning.
- **Prompt.** The default system prompt:
  - treats the input as a noisy speech transcript of a request and fulfils it;
  - returns only the requested text, because it is inserted where the user is
    typing: no preamble, closing remarks or questions back;
  - keeps the request's language and fits the stated length, format and tone;
  - picks the most reasonable reading of an ambiguous request;
  - admits unknowns instead of inventing them.
- **Editing.** The files are provisioned, validated (`ConfigResolver` and
  `PromptFileStore`), editable in Settings → Prompts (group "Ask") and
  hot-reloaded.
- **UI.** The A chip appears in the main window, compact view and overlay, the
  dropdown has an "Ask the model" row (key A) and Settings → General has a
  toggle. Hotkey + A toggles Ask mid-turn, and the spoken command is
  `<command> ask on/off`.
- **Telemetry.** Latency gets `durations_ms.ask_ms`. The protocol JSONL operator
  map and the status report include `ask`.
- **Push-to-talk wiring** (hotkey monitor, session control, press/release, overlay
  phases, delivery) is unchanged. A long answer is delivered by the existing live
  reconciliation: chunked keystrokes, or a paste when the answer contains line
  breaks.

## Verification

- `swift test`: 257/257, including `AskOperatorTests` (6):
  - the answer replaces the request;
  - Ask + Translate is one call in the target language;
  - fail-open;
  - the spoken toggle and backward-compatible decoding;
  - the flag and prompt-file validation;
  - UI session arguments.
- Manual on the signed build:
  - with Ask + Input on, a push-to-talk request lands as the answer in a focused
    field;
  - `release-latency.jsonl` shows `focused_input.ok=true` and `ask_ms`.
