# Plan 064 - Dictation while a meeting is recorded

Date: 2026-11-14. Requirement: FR-70.

## Request

While a meeting is recorded the user must be able to dictate with the standard push-to-talk and Push-to-Act mechanisms, and decide with a switch in Settings whether the microphone that is recorded in the meeting is muted during the dictation.

## Findings

- Nothing blocked dictation during a recording: the meeting has its own microphone capture and Soniox sessions, and neither `startHotkeySession` nor `handleSelectionHotkey` looks at the meeting. The event log shows the warm push-to-talk session opening the microphone during recordings without errors, but no push-to-talk turn had ever been made during one.
- The meeting's microphone heard the dictation: it went into the transcript as the user's side, into the transcription window, into the saved microphone audio, and counted as speech for the stop after silence.

## Decisions

- `MeetingMicrophoneGate` (lock-protected flag, `filter(_:)`) sits in the meeting's microphone callback. Muted, the meeting gets silence of the same length, so the Soniox stream, the audio file and the transcript times stay aligned. The system audio is not touched.
- The gate is closed for the whole push-to-talk turn: `UntypeUIModel.hotkeyPressed` (true from the press to the end of the turn, hands-free included) drives `MeetingRecorder.setMicrophoneMuted` through `updateMeetingMicrophoneMute()`. One log line when it closes and one when it opens, only while recording.
- Setting `meeting.muteWhileDictating` (`ui-state.json`; absent: on). Settings → Meetings → "Dictation during a meeting" → **Mute the microphone while dictating**. A change applies at once.
- Push-to-Act records nothing, so it needs no gate.
- Push-to-talk itself is not changed: its session, audio gate, overlay and delivery are as before.
- Not covered: untype cannot mute the user in the call application; the other participants hear the dictation unless the user mutes there.

## Verification

`swift build`, 406/406 tests (`MeetingDictationMuteTests`: gate, default, stored switch, recorder). On device still to do: a push-to-talk turn (held and hands-free) and a Push-to-Act during a recording, with the switch on and off; `focused_input.ok=true`.
