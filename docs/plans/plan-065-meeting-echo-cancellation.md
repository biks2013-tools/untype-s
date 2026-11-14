# Plan 065 - Speaker sound removed from the meeting's microphone

Date: 2026-11-14. Requirement: FR-71.

## Problem

Recording a meeting without headphones, the microphone also hears the call from the loudspeakers: the same words appear in the microphone's and in the system's transcript and, worse, the call is in the microphone's audio file.

## Options considered

1. Apple voice processing on the meeting's microphone (chosen).
2. Our own echo cancellation with the recorded system audio as reference (WebRTC AEC3 or an adaptive filter): a new C++ dependency or moderate quality; much more work. Kept in reserve.
3. Dropping duplicate lines from the transcript: does not fix the audio. Still worth doing later as a safety net.
4. Muting the microphone while the loudspeakers play: loses the user's voice when both talk.

## Measurements (2026-11-14, MacBook Pro microphone and speakers, volume 56 to 63)

Test speech played by a separate process (`afplay`), as a call application would.

- Unprocessed capture: the speech is in the microphone at about -19 dB (three runs); correlation with the played speech 0.49 to 0.56.
- Voice processing: -58 to -60 dB with nobody talking; with the user talking over it the recording stays at -17 to -26 dB (the voice) and the correlation with the played speech is 0.07 (chance level).
- The app's own `AVFoundationAudioSource` with voice processing: -60 dB and lower, against -20 dB unprocessed right afterwards.
- Side effect: while a voice-processing engine runs, an unprocessed engine in the same process stops getting audio, and a fresh one gets a signal that is not the plain microphone. After voice processing is switched off and its engine released, a fresh unprocessed capture is normal again (one channel, speech at -19 dB).

Not measured: whether macOS lowers the call's volume while voice processing runs (ducking is set to the minimum), and how the user's voice sounds to a listener.

## Decisions

- `AVFoundationAudioSourceOptions.voiceProcessing` (default false): `setVoiceProcessingEnabled(true)` on the input node before the tap, other-audio ducking at the minimum, the first channel of the multichannel format taken as the microphone (`PCM16MonoConverter(firstChannelOnly:)`); switched off again in `stop()`.
- Setting `meeting.echoCancellation` (`ui-state.json`; absent: off). Settings → Meetings → Audio → **Remove speaker sound from the microphone**. Read when a recording starts.
- One microphone while such a recording runs: `MeetingSharedMicrophone` publishes the meeting's microphone audio (before the dictation mute of plan-064); a dictation session started meanwhile uses `SharedMicrophoneAudioSource` instead of its own engine (`UntypeRuntimeFactory.makeForUI(audioSource:)`), resampled when the session's rate differs.
- `MeetingRecorder.onSharedMicrophoneChanged` tells the model when the microphone becomes shared or free; `alignSessionMicrophone` recycles the warm push-to-talk session so that it runs with the right microphone (never during a turn; the session after a turn picks the right one by itself).
- A recording with echo cancellation is not started while a dictation turn or a manual session is in progress (notice in the overlay).
- With the switch off nothing changes: the meeting and push-to-talk each keep their own capture.

## Known limits

- A turn in progress when such a recording ends loses the rest of its audio.
- Naming an older meeting by voice while a recording with echo cancellation runs uses its own capture and may hear nothing.
- Dictation during such a recording gets the processed microphone (noise reduction, automatic gain).

## Verification

`swift build`, 412/412 tests (`MeetingEchoCancellationTests`), and the hardware runs above. On device still to do: a real call without headphones with the switch on (audio file, both transcripts, the call's volume, the voice quality), push-to-talk held and hands-free during and after the recording (`focused_input.ok=true`), Push-to-Act.
