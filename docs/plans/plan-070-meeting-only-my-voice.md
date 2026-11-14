# Plan 070 - Meeting: only my voice in the microphone's transcript

Date: 2026-11-14. FR-75. Builds on plan-069 (voice sample).

## Why
Without headphones the meeting's microphone also hears the call from the loudspeakers, so the call's words appear on
the user's side of the transcript too. The existing remedy, "Remove speaker sound from the microphone" (plan-065, Apple
voice processing), changes how the microphone itself works; the user reports that with it the other side of the call
hears them badly (cause not measured). The voice sample of plan-069 can separate the user from the loudspeakers in the
transcript without touching the microphone.

## Measurement
One recording without headphones, echo cancellation off (`~/Recordings/recording-2026-11-14-16-37`, 76 s, a person on
the call and the user talking in between). The call's audio (`.system.m4a`) was transcribed on its own; the microphone
(`.mic.m4a`) with the user's saved sample ahead (`probe.ts --primer`). A microphone word counts as echo when the same
word is in the call's transcript within 2 s.

| Microphone words | Label of the sample (kept) | Other label (dropped) |
|---|---|---|
| also in the call's audio (echo), 141 | 4 | 137 |
| only at the microphone, 61 | 46 | 15 |

All 15 dropped microphone-only words were said while the call was speaking: echo recognised differently on the two
sides, or the user's own words over the loudspeakers; the measurement cannot tell which.

## Changes
- `MeetingUserVoiceFilter` (`MeetingTranscript.swift`): drops the sample's tokens and other speakers' tokens, shifts
  times back by the sample's length, counts words kept and dropped; keeps everything while the sample's label is unknown.
- `MeetingSonioxStream`: for the microphone side with a sample, diarization on, the sample and `finalize` after the
  config frame, the filter before the aggregator (saved transcript, live text, silence detection), `voiceSummary`.
- `MeetingRecordingOptions.voiceSample` (a sample at another rate than the recording's is an error),
  `MeetingPreferences.onlyMyVoice`, launcher (warning when on without a sample), Settings → Meetings → Audio.

## Not done / open
- The saved microphone audio still contains the loudspeakers.
- People in the room who are not the user are dropped as well.
- Speaker labels over a long meeting (30+ minutes) were not measured.
- Whether voice processing is the cause of the bad call quality was not measured.
