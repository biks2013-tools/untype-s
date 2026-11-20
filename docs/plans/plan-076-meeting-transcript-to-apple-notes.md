# Plan 076 - The meeting transcript also goes to Apple Notes

Date: 2026-11-20. Status: implemented on macOS, not installed; Notes itself was not called.

## Request

A switch so that untype uses Apple Notes for the transcription, instead of saving it only to a file.

Read as: the transcript of a meeting recording (the one thing untype saves to files). The files stay; the note is in addition.

## Behaviour

- Settings → Meetings → Files → **Also save the transcript to Apple Notes** (`meeting.appleNotes`, off until the user sets it).
- When a recording ends and its name is settled (at once, or after the name from the calendar), the main transcript (`<stem>.transcript.txt`, with the calendar header when there is one) is written as one note in the folder **untype** of Notes (made when missing, in the default account). First line: the meeting's name and date ("Budget review · Today 10:00"), or "Meeting · <date>" when it has no name.
- A failure is a warning in Events and a notice on the overlay; the files are not affected.
- A meeting renamed later from the saved card keeps the note's first title. Nothing is written while the meeting runs.

## How

- `AppleNotesHTML.body(title:transcript:)`: the note's body as HTML, text escaped, one `<div>` per line.
- `AppleNotesWriter.createNote(html:folder:)` (macOS only): an AppleScript handler (`make new note at folder … with properties {body: …}`) called in-process with the folder and the body as parameters (`NSAppleScript.executeAppleEvent`), on its own queue, one call at a time. Error -1743 is reported as "allow it in System Settings → Privacy & Security → Automation".
- `NativeUntypeUILauncher.saveToAppleNotes(_:)`, called at the four ends of `meetingFinished` / `nameFromCalendar`.
- Packaging: the entitlement `com.apple.security.automation.apple-events` (hardened runtime) and `NSAppleEventsUsageDescription` in the Info.plist. The signature's identity (bundle identifier, team) does not change, so the Accessibility and Input Monitoring grants should stay; to be confirmed after the install.

## Verified

`swift build`, 519/519 tests: the HTML, the switch's default and round trip, the handler call with a 60 000-character parameter and a script error, on scripts that touch no app. `UntypeCore` still builds for iOS.

## Not verified

- Notes itself: the permission prompt, the folder, the note, a long transcript, an iCloud and an "On My Mac" account.
- That the grants survive the new entitlement.

## Limits

- macOS only. iOS has no way for an app to write into Notes (only the share sheet, which the iPhone app has).
- Dictation is not written to Notes.
