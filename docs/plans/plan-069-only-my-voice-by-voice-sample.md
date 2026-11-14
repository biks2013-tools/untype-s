# Plan 069 - Only my voice: recognise the user by a voice sample

Date: 2026-11-14. Changes plan-068 (FR-74).

## Why
The user reported that "Only my voice" does not separate them from a person talking next to them. A recording of both
(`~/Recordings/recording-2026-11-14-16-05`, the user reading `test_scripts/voice-filter/script-el.txt`, the other person
talking alone and then over the user) was measured with `test_scripts/voice-filter/probe.ts`:

| Filter | User's words kept | Other person's words let through |
|---|---|---|
| untype's rule (speakers within 10 dB of the learned level, -31.6 dBFS) | 116/116 | 100/100 |
| Soniox speaker label of the user | 116/116 | 4/100 |

Both voices reached the microphone at the same level (-26.0 and -26.3 dBFS). Loudness cannot separate them; the
provider's speaker labels can, but a new stream does not say which label is the user.

## What
Every filtered stream starts with a saved sample of the user's voice; the label Soniox gives it is the user's.

Measured on the hard part of the recording (the other person first, then both at once), sample cut from the user's solo
part, sent in one burst followed by 200 ms of silence and `finalize`:

| Run | User's words kept | Other's words through | Sample recognised after |
|---|---|---|---|
| audio right after the sample | 48/49 | 4/94 | 2.2 s |
| audio 3 s after the sample | 50/50 | 1/96 | 2.2 s |

A sample of 2, 4 or 8 seconds gave the same labels. Four seconds are kept.

## Changes
- `VoiceFilter.swift`: `VoiceSample`, `VoiceSampleStore` (`~/.tool-agents/untype/voice-sample.wav`, 0600),
  `SonioxVoiceFilterMode.filter(sample:)`, `UserSpeakerFilter` (replaces `SpeakerLevelFilter`): drops the sample's
  pieces and every other speaker's; keeps everything while the user's label is unknown; a log line per utterance.
  `VoiceFilterPreferences.voiceLevelDb` removed (an old value in `ui-state.json` is ignored).
- `SonioxTranscriber`: sends the sample, the silence and `finalize` after the config frame; a sample at another sample
  rate than the stream is a configuration error (no resampling). Learning keeps up to 60 s of audio and reports four
  seconds from the first word of the speaker who said the most (at least 2 s and 5 pieces of words).
- Launcher and Settings → Speech → Other voices: "My voice: Learned (4.0 s sample)"; Learn saves the file.
- `probe.ts`: `--primer`, `--primer-wait`, `--user-level`.

## Not done / open
- Words said while both talk at once are still mixed now and then.
- The delay of the first words when a turn starts on a stream opened less than about two seconds earlier was not
  measured in the app.
- Other providers: no speaker labels are used there; the switch stays Soniox only.
