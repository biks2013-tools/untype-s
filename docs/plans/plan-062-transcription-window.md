# Plan 062 - Transcription window

Date: 2026-11-12. Requirement: FR-68.

"Transcription window" is the name of this window from now on.

## Request

A window that shows the transcription of the meeting being recorded, live, from the microphone, from the system, or from both. The user can keep it in sync with the recording, or out of sync: scrolled back to earlier text, which does not move while new text is still added at the end.

## Decisions

- Opened from the menu-bar dropdown: **Transcription window** (⌘3 while the dropdown is open). One window (`UntypeTranscriptionWindowController`), its frame remembered.
- **Channel** (segmented control): Both · Microphone · System. Remembered (`untype.transcriptionWindow.channel` in the app's defaults).
- **Follow** (switch): on = in sync, the view scrolls to the newest text whenever text is added or changes; off = out of sync, the view never scrolls by itself. Switching it on jumps to the newest text. Remembered (`untype.transcriptionWindow.follow`). The status bar says "In sync" / "Out of sync".
- Content: one row per finished segment (speaker, time from the meeting start, text) in the order the segments arrive, so a row never moves once shown and new rows only go at the end. Under them, per side, the sentence being spoken (grey italic), replaced as its words change and turned into a row when it is finished.
- Source: `MeetingTranscriptFeed` (main actor, observable), filled by `MeetingRecorder.onSegment` and `onInProgress`. `MeetingTokenAggregator.inProgressText(with:)` gives the words of the unfinished segment (settled tokens held so far plus the frame's unsettled ones); they are shown only, never written.
- The transcript stays in the window after the recording ends, until the next recording starts. The text is as spoken (the English translation is made at the end, in the files).
- The status bar shows a red dot and the meeting folder's name while recording.

## Additions (2026-11-12, second request)

- **Copy** button in the window: puts on the clipboard what has been transcribed so far on the chosen side (Both, Microphone or System), one finished sentence per line as `[00:00:07] Speaker 1: text` (`MeetingTranscriptFeed.text(for:)`). The sentence still being spoken is not copied. The button says "Copied" for a moment and is disabled while the side has no line.
- **Overlay tray icon**: a small captions icon in the hover tray, between Record and Settings, opens the transcription window (`UntypeOverlayController.transcriptionKey`, tooltip "Transcription window").
- **Translation direction in the tray**: the tray offers ⇄ (opposite: Greek becomes English, English becomes Greek) before EN and EL. ⇄ is offered when both Greek and English are among the languages (or with auto). The dropdown already had it; the tray had only EN and EL since plan-057.

## Clear (2026-11-12, third request)

- **Clear** button in the window: the lines shown so far are no longer shown (`MeetingTranscriptFeed.clear()` sets `clearedBefore`). The recording, the meeting's files and the sentence being spoken are not touched; text that comes after appears as usual. Copy copies what the window shows, so after a clear it copies only the later lines.
- The window is emptied whenever a new recording starts (`begin` resets the lines and `clearedBefore`); this was already the case and is now tested with Clear.

## Not covered

- The window does not open by itself when a recording starts.
- Scrolling by hand does not switch Follow off: with Follow on, the next text brings the view back to the end.
- No search or export.
- Push-to-talk dictation is not shown (meeting recordings only).

## Files

`TranscriptionWindow.swift` (new), `MeetingTranscript.swift` (`inProgressText`), `MeetingRecorder.swift` (`onSegment`, `onInProgress`), `NativeUntypeUILauncher.swift`, `UntypeMenuBarPanel.swift`; tests `TranscriptionWindowTests.swift`.
