# Native UI Live Smoke Test

## Purpose
Verify that `untype ui` opens the SwiftUI/AppKit monitoring UI, resolves non-secret settings, starts and stops the shared Swift transcription runtime, maintains warm push-to-talk state, and displays the overlay without persisting transcript text or secrets.

## Prerequisites
- Build the project with `swift build`.
- Configure either `SONIOX_API_KEY` or `ELEVENLABS_API_KEY` through the documented configuration chain.
- If LLM refinement is enabled, configure the selected LLM provider credentials or disable LLM refinement in the UI before starting.
- Grant Microphone permission to the terminal app that launches `untype ui`.
- For global push-to-talk release detection, grant Accessibility/Input Monitoring permission to the launching terminal app if macOS requires it.

## UI Launch Check
Run:

```sh
.build/debug/untype ui
```

Expected result:
- A native macOS window titled `untype` opens.
- The credentials panel shows the active API-key name, configured/missing status, source tier, and expiry value without showing the secret value.
- The system panel shows current Microphone and Accessibility trust status so the remaining macOS permission checks can be verified before starting a session.
- The settings panel exposes provider, model, languages, sample rate, endpoint detection, protocol operator defaults, translation policy, LLM settings, and push-to-talk settings.
- The Push to Talk panel exposes `Quick Close` as a non-secret persisted toggle.
- The event log remains inside the window; no transcript text is printed to terminal stdout by UI rendering.
- `Command+W` closes the UI window and `Command+Q` quits UI mode through the native app menu.

## Manual Session Check
1. Click `Start Listening`.
2. Speak a short utterance.
3. Confirm partial/final transcript text appears in the UI transcript/events panes.
4. While the session is listening, confirm provider/model/language/protocol/LLM/push-to-talk settings are disabled and the four protocol operator switches remain enabled.
5. Click `Stop Listening`.

Expected result:
- Session state transitions through `starting`, `listening`, `stopping`, and `idle`.
- The event log shows `starting microphone capture`, `microphone capture started`, `connecting <provider> realtime stream`, and then `<provider> realtime stream connected` when the STT WebSocket is ready.
- The header and System panel show `Audio: waiting` before microphone chunks arrive, then `Audio: silent <n>%` or `Audio: active <n>%` while the provider may still be connecting. If this stays `waiting`, the UI runtime has not received microphone PCM.
- The Events tab shows throttled `audio.input` lines while audio chunks arrive. `provider receives microphone audio` means the STT provider is receiving real mic PCM; `provider receives silence` means the microphone is active but the push-to-talk gate is intentionally closed.
- Partial text appears as a live partial row, final text becomes a committed dictated-text row, and processed/refined text appears as a follow-up row in the same grouped turn.
- The `Clear` action removes only the visible transcript timeline and live partial text; it does not stop the active session or change protocol operator state.
- Session-shaping settings remain locked until the session returns to idle; refine, translate, clipboard, and focused-input switches stay editable and affect the active protocol controller.
- Typed provider/microphone/configuration failures appear as UI event warnings or errors.
- If a provider returns a fatal transcriber error, the UI must not repeatedly restart the warm push-to-talk session; it should leave the error visible and require the user to retry after resolving the provider issue.
- Non-secret protocol settings are still written through the existing protocol state store on graceful stop.

## Push-To-Talk and Overlay Check
1. Enable push-to-talk in the UI.
2. Use the configured hotkey, default `Control+\``.
3. Speak while holding the hotkey, then release it.
4. While holding the hotkey, press `R`, `T`, `C`, or `I` to toggle refine, translate, clipboard, or focused-input state.
5. If pressing the physical hotkey does not change capture state, click `Press Hotkey` in the Push to Talk panel, then click `Release Hotkey`.

Expected result:
- Enabling push-to-talk starts or keeps a hotkey-owned warm session.
- Clicking `Stop Warm Session` during either `starting` or `warm` returns the UI to `Session: idle` and `Capture: idle`; it must not remain stuck in `starting`.
- The Push to Talk panel reports `global event tap ready` when macOS permits the Quartz event tap; if not, it reports fallback monitoring and the event log shows a warning.
- Pressing the hotkey changes capture state to `recording` and opens the audio gate.
- With `Quick Close` disabled, releasing the hotkey waits for provider final text, submits the current turn or the timeout fallback partial, attempts enabled refine/translate/clipboard/focused-input delivery, stops that provider session, then returns to a fresh warm session for the next press.
- Enable `Quick Close`, repeat a push-to-talk utterance, and confirm the Events tab shows `Quick Close submitting latest partial transcript` when the provider has only partial text at release. Processed output should appear without waiting for the normal finalization timeout.
- Disable `Quick Close` again and confirm the older finalization-wait behavior returns.
- Each new hotkey press starts a fresh content collection turn; stale partial text from the previous press must not remain as the active live partial.
- During a warm push-to-talk session with the key released, the System panel may show `Audio: muted by push-to-talk <n>%`; this confirms the microphone path is receiving PCM while the audio gate sends silence to the provider.
- During warm push-to-talk, the Events tab should show `audio.input: muted by push-to-talk <n>%; ... provider receives silence`; this is expected until the hotkey or fallback button opens the gate.
- The event log records a privacy-safe push-to-talk source such as `quartz-event-tap`, `local-monitor`, `global-monitor`, or `ui-button`; if only `ui-button` works, macOS is not delivering the keyboard hook to the launching app.
- A bottom-center non-activating overlay appears while recording, shows live/committed text, does not take focus, and clears/hides after release.
- Long overlay text wraps within the overlay width. The overlay should not move while the text still fits the current height; when a new wrapped line needs space, it grows upward from the same bottom-left anchor captured when the overlay first appeared.
- Holding the configured hotkey must not produce repeated `push-to-talk pressed`, `ui-hotkey-release`, or `no text was submitted` cycles while the key remains down; repeated cycles indicate key-repeat is being treated as fresh push-to-talk presses.
- Click `Hide Settings` and `Show Settings` to confirm the right settings sidebar collapses and expands without stopping the active session.
- The overlay shows compact `R`, `T`, `C`, and `I` operator indicators and updates them when the matching operator hotkeys are pressed during recording.
- If global key release detection is blocked, the UI shows an Accessibility/Input Monitoring warning and pressing the hotkey again stops the fallback recording session.

## Push-To-Talk Release Latency Log Check
Use this only for diagnostic runs. Enable logging before launching UI mode:

```sh
UNTYPE_RELEASE_LATENCY_LOG=on .build/debug/untype ui
```

Optional isolated log path:

```sh
UNTYPE_RELEASE_LATENCY_LOG=on \
UNTYPE_RELEASE_LATENCY_LOG_PATH=/tmp/untype-release-latency.jsonl \
.build/debug/untype ui
```

Steps:
1. Enable push-to-talk and the focused-input operator.
2. Focus a disposable editable control, such as a scratch TextEdit document.
3. Press the push-to-talk hotkey, speak a short utterance, and release.
4. Quit UI mode and inspect `~/.tool-agents/untype/release-latency.jsonl`, or the custom `UNTYPE_RELEASE_LATENCY_LOG_PATH`.

Expected result:
- One JSON line is appended for the release attempt.
- The record includes `release_timestamp`, `trigger`, `text_source`, `outcome`, `total_ms`, `durations_ms`, `sections_processed`, and `focused_input`.
- Successful focused-input delivery reports `outcome:"delivered_to_focused_input"` and `focused_input.ok:true`.
- Failed focused-input delivery reports `outcome:"focused_input_failed"` with a privacy-safe `focused_input.code`, such as `accessibility_not_trusted`.
- The log does not contain dictated text, processed/refined/translated text, clipboard contents, API keys, prompts, provider payloads, or target application contents.
- After the diagnostic run, disable logging by removing `UNTYPE_RELEASE_LATENCY_LOG`, setting it to `off`, or using `--no-release-latency-log`.

## Persistence and Privacy Check
Inspect:

```sh
cat ~/.tool-agents/untype/ui-state.json
```

Expected result:
- The file contains non-secret UI settings and `push_to_talk` settings.
- The file may contain `"quickClose"` as a non-secret UI preference.
- The file does not contain API key values, transcript text, processed output, protocol payloads, provider endpoint diagnostics, or transient Microphone/Accessibility permission status.
- File permissions are `0600`; the parent `~/.tool-agents/untype` directory is `0700`.
