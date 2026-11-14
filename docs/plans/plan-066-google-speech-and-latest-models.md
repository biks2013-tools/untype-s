# Plan 066 — Google speech-to-text and the providers' latest realtime models

Date: 2026-11-14 · Status: implemented, not yet used in the installed app

## Request
1. Add Google as a speech-to-text provider, with Google's newest model for the job.
2. Check that the Soniox and ElevenLabs models in use are the latest and update them.

## What the providers offer (checked 2026-11-14)
| Provider | Was in untype | Latest realtime model | Source |
|---|---|---|---|
| Soniox | `stt-rt-v5` (deprecated, removed 2026-12-15, then routed to v6) | `stt-rt-v6` (released 2026-11-03), same API | https://docs.soniox.com/stt/models |
| ElevenLabs | `scribe_v2_realtime` (still available) | `scribe_v3_live`, same WebSocket, `model_id` only | https://elevenlabs.io/docs/overview/models |
| Google | — | `gemini-3.5-transcribe-live` (August 2026) over the Gemini Live API | https://ai.google.dev/gemini-api/docs/live-api/live-transcribe |

Each model was called with the keys in `~/.tool-agents/untype/.env` and synthetic Greek speech (`say -v Melina`): all three returned the sentence. Soniox v6 was also called with the meeting recorder's options (language identification, speaker diarization): same token shape as v5.

## Google live transcription: what the service does (measured)
- WebSocket `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent`; the key is accepted in the `x-goog-api-key` header (kept out of the URL).
- First frame `{"setup":{"model":"models/<model>","generationConfig":{"responseModalities":["TEXT"]},"inputAudioTranscription":{"languageCodes":[…]}}}`; the server answers `{"setupComplete":{}}` in about 0.35 s. Frames arrive as binary JSON.
- Audio: `{"realtimeInput":{"audio":{"data":"<base64 PCM16 16 kHz mono>","mimeType":"audio/pcm;rate=16000"}}}`.
- `serverContent.interimInputTranscription.text`: the sentence so far (cumulative). `serverContent.inputTranscription.text`: the finished sentence.
- `{"realtimeInput":{"audioStreamEnd":true}}` finalizes at once (final text about 0.3 s later) and the session accepts more audio afterwards. With `realtimeInputConfig.automaticActivityDetection.disabled`, `activityStart` / `activityEnd` mark speech.
- `languageCodes` accepts `el`, `en` as well as `el-GR`, `en-US`.
- A wrong key or model is reported only as a WebSocket close reason (codes 1007 / 1008).
- **A session that receives no audio is closed after about 60 s** (close 1008 "The operation was aborted"); sessions are limited to 10 minutes: a session fed silence received `{"goAway":{"timeLeft":"50s"}}` after 9 minutes. No speaker diarization.

## Design
- `STTProvider.google`; the provider now carries its default model, endpoint and key name (`defaultModel`, `defaultEndpoint`, `apiKeyEnvName`). Key: `GOOGLE_API_KEY`, the same variable the Google LLM provider uses (`--google-api-key`, `GOOGLE_API_KEY_EXPIRES_AT`).
- `GoogleTranscriber` (`RuntimeTranscriber`):
  - `start()` connects, sends the setup and waits for `setupComplete` (10 s limit), so a wrong key (`google_speech_auth`) or model (configuration error) fails the start and is not retried.
  - Endpoint detection on: server detection; `commit()` sends `audioStreamEnd`. Off: `activityStart` with the first audio that is not silence, `activityEnd` at `commit()`.
  - **Connection replacement.** untype keeps the push-to-talk session warm for hours, the service allows 10 minutes. The transcriber opens a new connection and moves the audio to it once the server accepted it: after 7 minutes at a quiet moment (silence, nothing waiting for a finished sentence), after 9 min 20 s in any case, and when the server sends `goAway`. The old connection stays open 1.5 s for a sentence it was finishing. The closed push-to-talk gate already sends silence, which keeps the session from the 60 s idle close.
  - A close of the connection in use is reported once (`google_speech_network`); the existing warm-session recovery restarts the session.
- `URLSessionRealtimeWebSocketClient` now reports the server's close reason (`RealtimeWebSocketCloseError`), for all providers.
- Latest models: defaults `stt-rt-v6`, `scribe_v3_live`. A stored `stt-rt-v3/4/5` or `scribe_v2_realtime` is replaced by its successor when the UI settings are normalized (`STTProvider.currentModel(for:)`), so existing installations move without a manual step.
- Settings → Speech: Google in the provider list; changing the provider changes the model to the new provider's default unless the user typed their own; a **Latest** button; a footer naming the key and the limits.
- Sample rate must be 16000 Hz with Google (configuration error otherwise).

## Not included
- Meeting recording stays on Soniox (it needs speaker diarization, which the Google live model does not have): with Google or ElevenLabs as the speech provider a recording is refused with the existing message.
- Google `customVocabulary` and `mode: SMART` are not exposed.
- ElevenLabs v3 Live turn prediction, multilingual mode and diarization are not used.

## Verification
- `swift build`; 430/430 tests (18 new: `GoogleTranscriberTests`, resolver tests).
- The real `GoogleTranscriber` against the live service, endpoint detection on and off: three turns with a connection replacement between them, three correct finals, no errors, final text 300–370 ms after `commit()` (250 ms of it is the drain wait).
- Not done: a push-to-talk turn in the installed app with Google, `scribe_v3_live` or `stt-rt-v6`; ten real minutes on one Google session.
