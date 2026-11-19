# Plan 074 - Pause the microphone or the system audio of a meeting

Date: 2026-11-19. FR-78.

## Why
User request: during a meeting recording, pause the capture of the microphone or of the system audio for a while and
resume it, with the controls in the transcription window, on the Microphone and System tabs.

## What it does
The Microphone tab and the System tab of the transcription window have a **Pause** button (it reads **Resume** while
paused); the Both tab has none. A paused side gets silence of the same length in place of what was captured, the same
way the microphone is muted during a dictation turn (plan-064):

- nothing of that side is transcribed, shown or saved in its audio file while it is paused;
- the other side goes on, and the times of the transcript and of the audio files stay aligned;
- the status line says which side is paused and its dot turns amber; the paused tab says so when it is empty;
- while a side is paused the recording does not stop after silence; the count starts again at the resume;
- a pause ends with the recording and never carries over to the next one;
- dictation is not affected: it has its own microphone during every recording (plan-072).
- with echo cancellation on, the canceller keeps getting the system audio as it is while that side is paused (the loudspeakers go on playing), so the call's sound stays out of the microphone.

## Changes
- `MeetingMicrophoneGate`: `isPaused` next to `isMuted`; `filter` gives silence for either. `MeetingRecorder.systemGate`
  on the system audio; `setPaused(_:side:)`, `isPaused(_:)`; `checkSilence` waits while a side is paused.
- `MeetingTranscriptFeed`: `paused`, `togglePause`, `setPaused`, `onPauseRequest`.
- `UntypeTranscriptionView`: the Pause / Resume button, the status line.
- `UntypeUIModel`: `transcriptFeed.onPauseRequest` calls the recorder.

## Limits
- The pause is not marked in the saved transcript; the event log has "paused" and "resumed" with the second.
- Words being spoken at the moment of the pause may be cut.
- The capture devices keep running (the overlay's trace of that side goes flat); only what the meeting gets is silence.

## Verification
`swift build`; 487/487 tests (4 new in `MeetingPauseTests`). Not run in a recording.
