# STT Prompt and Context Fields

## Purpose
This note records the provider prompt/context surfaces used for configurable transcription prompts in `untype-s`.

## Soniox
Soniox realtime STT supports a `context` object in the session configuration message. The context object can include four optional sections:

- `general`: structured key-value information such as domain, topic, setting, participants, or intent.
- `text`: longer free-form background text.
- `terms`: domain-specific or uncommon words and phrases.
- `translation_terms`: source/target translation preferences.

The official Soniox docs describe context as improving transcription and translation accuracy by helping the model understand the domain, recognize important terms, and apply custom vocabulary. The documented size limit is 8,000 tokens, approximately 10,000 characters.

Implementation choice for this project: expose a user-editable Soniox transcription context prompt as free-form text and send it as `context.text` when non-empty. This preserves current behavior when the file is empty and gives users a low-friction place to describe the domain or expected terminology.

Source:
- `https://soniox.com/docs/stt/concepts/context`
- `https://soniox.com/docs/api-reference/stt/websocket-api`

## ElevenLabs
ElevenLabs Scribe v2 Realtime supports two relevant context/prompting mechanisms:

- `keyterms`: repeated WebSocket query parameters used to bias transcription toward specific words or phrases. Realtime supports up to 50 keyterms, each up to 20 characters.
- `previous_text`: context sent alongside the first audio chunk only. The docs describe it as useful for agent text, reconnect context, or a short description of what the transcription will be about. It works best under 50 characters and sending it after the first chunk causes an error.

Implementation choice for this project: expose provider-specific files for ElevenLabs keyterms and previous-text context. The adapter sends keyterms in the WebSocket URL and sends `previous_text` only with the first non-empty audio chunk.

Source:
- `https://elevenlabs.io/docs/overview/capabilities/speech-to-text`
- `https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/batch/keyterm-prompting`
- `https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/client-side-streaming`
- `https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference`

## Assumptions
- The user request uses “transcription prompt” broadly to mean provider-supported context/prompting controls for realtime STT.
- A single free-form text prompt is appropriate for Soniox because Soniox supports `context.text`.
- ElevenLabs should not receive arbitrary long prompt text as `previous_text` because the provider documents it as short, first-chunk-only context.
