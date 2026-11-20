# Plan 077 - Attach the clipboard to a moment of the meeting

Date: 2026-11-20. Status: implemented on macOS, not installed; not yet run in a recording.

## Request

While a meeting is recorded, attach to the current moment of the conversation what the clipboard holds: text, a screenshot, or a whole file. untype looks at what the clipboard has at that moment, saves it in the recording's folder and writes it in a JSON file with the moment, so that it can be combined with the recording afterwards.

## Behaviour

- **Attach** (paperclip), only while a meeting is recorded: in the transcription window, in the overlay's tray (next to Stop) and in the menu-bar dropdown (Meeting row).
- What is taken from the clipboard:
  - copied files or folders (Finder): each of them is copied, and nothing else is taken (the clipboard's text and picture are then only their names and icons);
  - otherwise the picture (PNG, TIFF, JPEG, HEIC, GIF, BMP; saved as PNG) and the plain text, whichever are there, both when both are.
- The clipboard is not changed. An empty clipboard, or one with nothing of the above, says so and writes nothing.
- The moment is the time since the recording started when the button was pressed, on the clock of the transcript (`startMs` of `<stem>.segments.jsonl`) and of the audio files.
- The user is told what was attached (kind and size, with the time) on the overlay and in the status line of the transcription window, which also counts the attachments of the meeting.

## In the transcription window (added the same day, user request)

Every attachment is a row of the transcript at the place of the conversation it was attached (after the lines that were there), on every tab: a paperclip, its kind and time, and a thumbnail — the picture itself, the first lines of the text, or the file's icon and name. A click opens it in its application; the context menu has Open and Show in Finder. Clear removes the rows from the window like the lines. The rows follow the meeting folder when the meeting is named (`MeetingTranscriptFeed.meetingFolder` / `folderRenamed` / `rows(for:)`, `TranscriptionAttachmentRow`).

## Files by drop and by dialog (added the same day, user request)

While a meeting is recorded, files and folders dropped on the transcript of the transcription window are attached to that moment (a dashed frame shows while they are over it), and **Attach a file** (next to Attach) opens the file dialog, several files or folders at once; the moment is when the dialog is confirmed. Both go the way of copied files: `MeetingTranscriptFeed.attachFiles` / `onAttachFilesRequest`, `NativeUntypeUILauncher.attachToMeeting(_:source:)`. The originals are not moved.

## Files

In the meeting folder:

- `attachments/NNN-HH-MM-SS-<name>`: `001-00-12-34-image.png`, `002-00-12-40-text.txt`, `003-00-15-02-<the file's own name>`. Made at the first attachment.
- `<stem>.attachments.json`, rewritten after every attachment (on disk during the meeting):

```json
{
  "attachments": [
    {
      "attachedAt": "2026-11-20T10:42:46Z",
      "bytes": 345120,
      "clip": 1,
      "file": "attachments/001-00-12-34-image.png",
      "height": 900,
      "id": 1,
      "kind": "image",
      "offsetMs": 754300,
      "time": "00:12:34",
      "width": 1440
    }
  ],
  "recording": "recording-2026-11-20-10-30",
  "startedAt": "2026-11-20T10:30:12Z",
  "version": 1
}
```

`kind` is `text`, `image`, `file` or `folder`. `clip` is the attach action (several files, or a picture and its text, share it). Text has `characters`; a file or folder has `originalName`; a folder has no `bytes`. `file` is relative to the meeting folder, so renaming the meeting keeps it valid.

## How

- `MeetingAttachments.swift` (macOS only): `MeetingClipboardContent.read(_:)` (what the pasteboard holds), `MeetingAttachmentStore` (an actor: copies and writes off the main thread, one attachment at a time, the index after each), `MeetingAttachment`, `MeetingAttachmentIndex`, `MeetingAttachmentResult.summary`.
- `MeetingRecorder.attach(_:)`: the offset from `startUptime`, the store made at the start of the recording and dropped at its end. `MeetingFileNames.attachments`.
- `MeetingTranscriptFeed.attachClipboard()` / `onAttachRequest` / `noteAttach` / `attachmentCount` / `attachNote`; the button and the status line in `UntypeTranscriptionView`.
- `NativeUntypeUILauncher.attachClipboardToMeeting()`; the tray button (`attachKey`) and the dropdown button.
- Events get the kind, the sizes and the time only, never the text or a file name.

## Verified

`swift build`, 524/524 tests (5 new: text with its moment and the index file, a picture with its text as one clip, copied files with a missing one reported, an empty clipboard, reading files / picture / text from a scratch pasteboard, the window's request and count).

## Not verified

- In a recording: the three buttons, a screenshot taken to the clipboard, text, a file copied in Finder, a large file.
- The tray's width with the extra button.

## Limits

- No global shortcut: the buttons need a click. A shortcut would be a new setting and a change in the hotkey monitor.
- The transcripts do not mention the attachments; the JSON file is the link.
- A large file is copied whole into the meeting folder.
- Nothing can be attached after the recording stops.
