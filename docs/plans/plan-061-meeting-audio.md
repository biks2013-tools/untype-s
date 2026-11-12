# Plan 061 - Save the audio of a meeting

Date: 2026-11-12. Requirement: FR-67.

## Request

A meeting recording keeps the audio as well as the transcript. In Settings the user chooses whether the microphone and the system audio are saved separately or mixed, and whether both are saved or only one. The audio is saved next to the transcript.

## Decisions

- Two settings in `MeetingPreferences` (Settings → General → Meeting recording):
  - `meeting.audioSources`: `both` (default, also when the key is missing; changed 2026-11-12 on the user's request, it was `none`), `none`, `microphone`, `system`.
  - `meeting.audioLayout`: `separate` (default) or `mixed`; used only with `both`.
- Files in the meeting folder: `<stem>.mic.m4a`, `<stem>.system.m4a`, or `<stem>.m4a` when mixed (see "File names" below).
- Format: AAC in `.m4a`, mono, 16 kHz, 32 kbit/s (about 15 MB per hour per file). It is the audio the recorder already has for transcription (PCM16 mono 16 kHz), so the quality is speech quality, not music quality.
- The settings choose what is saved as audio only. The transcript still covers both sides.
- Timing: each side is placed on the meeting's clock (`MeetingAudioTimeline`): the time before its first chunk, and a hole of half a second or more, become silence. So the files line up with each other and with the transcript times.
- Mixing (`MeetingAudioMixer`): samples of the two sides are added at their place and clamped; a sample is written once both sides have passed it, or when one side is two seconds behind.
- A write error stops the audio with one warning; the meeting and its transcript continue. A file that cannot be created stops the recording from starting.
- An unknown value of either setting is an error when a recording starts.

## File names (2026-11-12)

The user asked for the names the ntakker recorder and ntakker-studio use (read from `~/aiwork/tools/ntakker`: `FilenameGenerator`, `SegmentNamer`, `SidecarPathBuilder`, `Recording.swift`). `MeetingFileNames` holds them; the stem is `recording-yyyy-MM-dd-HH-mm` (local start time).

| File | Name | Before |
|---|---|---|
| Microphone audio | `<stem>.mic.m4a` | `audio.microphone.m4a` |
| System audio | `<stem>.system.m4a` | `audio.system.m4a` |
| Mixed audio | `<stem>.m4a` | `audio.m4a` |
| Microphone transcript, ntakker JSONL | `<stem>.microphone.transcript.jsonl` | new |
| System transcript, ntakker JSONL | `<stem>.system.transcript.jsonl` | new |
| Transcript for reading | `<stem>.transcript.txt` | `transcript.txt` |
| Transcript as spoken | `<stem>.transcript.original.txt` | `transcript.original.txt` |
| Both sides with untype's fields | `<stem>.segments.jsonl` | `transcript.jsonl` |

- The per-side JSONL files use ntakker's line format (`id`, `timestamp`, `source`, `text`, `model`, `durationSec`, `language`, `speaker`), so ntakker-studio can read them. untype's own JSONL does not end in `.transcript.jsonl`, so the studio does not take it for a transcript.
- Naming a meeting renames only the folder; the files keep the stem (as in ntakker). Meetings recorded before this keep working: `MeetingNaming.mainTranscript` still finds `<folder>.txt` and `transcript.txt`.
- The folder name is unchanged (`2026-11-11 14.30`, then `2026-11-11 14.30 – <title>`); ntakker's bundle folders are `<title>-recording-<date>`.
- Not checked: opening an untype meeting folder in ntakker-studio.

## Not covered

- No format or quality setting; no stereo file with one side per channel.
- If untype is killed mid-meeting, the `.m4a` files are not finished and may not play.

## Files

`MeetingAudio.swift` (new), `MeetingRecorder.swift`, `UntypeUISettings.swift` (`MeetingPreferences`), `NativeUntypeUILauncher.swift` (`meetingOptions`), `UntypeSettingsWindow.swift`; tests `MeetingAudioTests.swift`.
