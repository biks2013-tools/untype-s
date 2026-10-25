# Plan 038 — Voice commands on/off

Date: 2026-10-25

## Request

Give the user a flag, in Settings, that enables or disables the voice commands. It does not need to be changeable in real time during a push-to-talk turn.

## Design

- `MarkerConfig.voiceCommandsEnabled` (default `true`). When it is false, `markerDefinitions(for:)` returns no definitions, so the following are not recognised:
  - the command phrase;
  - section end and the guard phrase;
  - cancel;
  - `literal phrase`.

  `partialContainsActionableCommand` is therefore always false, and all speech is section text, submitted on release or stop.
- Configuration:
  - `--voice-commands` / `--no-voice-commands` and `UNTYPE_VOICE_COMMANDS` (boolean, default on);
  - documented in the `.env` template and the help text.
- UI:
  - `UntypeUISettings.voiceCommands` (default true; optional in `ui-state.json`, so older files load as on);
  - passed through `sessionArguments()`;
  - a Settings → General → Protocol toggle with a caption.
  - The toggle is disabled while a manual session runs, like the other session-shaping controls. Because `isProtocolSwitchOnlyChange` includes the field, a change restarts the warm hotkey session.
- Hotkey-letter operator toggles do not use markers and keep working.

## Verification

- `VoiceCommandsToggleTests`:
  - the default, the flag, the environment variable and the flag-over-environment precedence;
  - an invalid value is rejected;
  - with commands disabled, spoken commands are kept as text and submitted on drain;
  - with commands enabled, commands still work;
  - session arguments;
  - the store round trip, and an older file loading as on.
- Signed build: switch voice commands off, then say "command translate on" in a push-to-talk turn. The words must be delivered as text, with `focused_input.ok=true`.
