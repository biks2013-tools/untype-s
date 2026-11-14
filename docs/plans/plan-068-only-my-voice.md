# Plan 068 — Only my voice: dictation keeps the user's words when others talk nearby

Date: 2026-11-14 · Status: implemented behind a switch that is off by default; not yet used in the installed app

## Request
In places where other people talk, untype writes their words as if the user had said them. Wanted: an option, trained with the user's voice, that keeps only the user's words; switchable, because in a quiet place it should not cost accuracy.

## Assessment and measurement
Three ways were weighed: loudness alone, the provider's speaker labels, a voiceprint computed on the device (a new model and dependency; macOS has no speaker-recognition API). Before choosing, they were measured with `test_scripts/voice-filter/probe.ts` on three recordings the user made while reading `test_scripts/voice-filter/script-el.txt` with people talking around (words found in the script count as the user's):

| Recording | User / others at the microphone | "Loudest speaker" (Soniox labels): user's words kept | other words let through |
|---|---|---|---|
| someone talks first | -23 / -47 dBFS | 115/115 | 5/27 |
| little other speech | -22 / — | 117/117 | 4/4 |
| a lot of speech around | -23 / -42 dBFS | 117/117 | 5/135 |

The few "other" words in the user's own label have the user's loudness: most likely the user's words recognised differently from the script. Loudness alone lost 10–15% of the user's words; "the first speaker" kept the wrong person in the first recording. So: speaker labels decide who said a word, loudness decides which speaker is the user, and no voiceprint for now.

## Design
- Settings → Speech → "Other voices": **Only my voice** (`voiceFilter.enabled`, default off) and **My voice level** with **Learn** (`voiceFilter.voiceLevelDb`). Soniox only.
- Training = learning the user's loudness: after **Learn**, the next dictation runs in learning mode (the loudest speaker is taken as the user); when it ends, the median loudness of that speaker's word pieces is stored. Fewer than 5 measured pieces: nothing is stored and the user is asked for a full sentence.
- `VoiceFilter.swift`: `StreamLevelMeter` (mean square per 10 ms of the audio sent, by stream time), `SpeakerLevelFilter` (median loudness per speaker label over the whole stream; a speaker is kept when within 10 dB of the user's level; unlabeled or unmeasured pieces are kept), `VoiceFilterPreferences`, `SonioxVoiceFilterMode` (`filter(userLevelDb:)`, `learn`).
- `SonioxTranscriber`: with a mode it asks for speaker diarization, measures each recognised piece from its `start_ms`/`end_ms`, and builds partial and final text from the kept pieces only. Without a mode nothing changes (the request and the token handling are the old ones).
- `NativeUntypeUILauncher`: the mode is chosen when a session starts; changing the switch or learning restarts the warm push-to-talk session (never during a turn). Dropped words are logged as numbers per utterance (`only my voice: about N words kept, M dropped (speaker 2 at -44 dB dropped; …)`).
- With the switch on but no learned level, or another provider: a warning in the event log and all voices are transcribed.

## Verification
- `swift build`; 454/454 tests (8 new in `VoiceFilterTests`).
- The three recordings replayed through the real `SonioxTranscriber` against Soniox, filter off and on, level learned from the second recording (-23.1 dB): in the recording with much speech around, other words fell from 88 to 3 and the user's stayed at 78 of 78 recognised in that run; in the others the user's words were unchanged (77/77, 66/65). (The replay was fed twice real time and closed early, so each run covers about two thirds of its recording.)
- Not done: a turn in the installed app; learning through the Settings button; a speaker sitting close to the user.

## Limits
- Someone as loud as the user at the microphone (sitting close) is kept; someone talking over the user is not separated.
- The level belongs to one microphone and distance: learn again after changing either.
- A turn in which only others spoke yields no text: the release then waits for a final text that does not come (about 1.5 s) before it ends.
- Next step if close speakers get through: a voiceprint as a second test on each speaker label; the log shows where it would be needed.

## After the first try in the app (2026-11-14, build 71)
- Learn was changed: it no longer waits for the next dictation with the hotkey (nothing showed that it was waiting, and the user cancelled it each time by pressing the button again). It starts a push-to-talk turn itself, listens for 8 seconds while Settings counts down, discards the turn (nothing is delivered) and stores the level reported when the stream stops. The Cancel button is gone.
- The user reports that learning and the filter work as expected.
