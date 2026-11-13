# Plan 063 - Settings organization and layout

Date: 2026-11-13. Requirement: FR-69.

## Request

Improve the organization and the layout of the Settings window.

## What was wrong

- General had become a catch-all: appearance, the overlay, the whole of meeting recording (eight rows under one footer of some 150 words) and the session state.
- Operators mixed the experimental switch in between Processing and Delivery, and kept "Selected text is" (which only matters to the experimental Selection operator) in a generic "Options" section.
- Nothing said what a pane is for; the Screen & System Audio Recording permission was not shown anywhere; the two stepper rows put their value next to the label instead of at the right.
- The main window's "Change…" (push-to-talk hotkey) opened General instead of Push-to-Talk.

## Decisions

- New pane **Meetings** (`UntypeSettingsPane.meetings`, id `meetings`), in the sidebar group of the ways of using untype: Push-to-Talk, Push-to-Act, Meetings. Sections, each with its own short footer: Transcript (language, a button that opens the transcription window), Audio (save audio, audio files), Files (folder), Ending (stop after silence), Calendar (Outlook), Permission (Screen & System Audio Recording, with a button to System Settings when missing).
- General keeps Appearance, Dictation overlay, Current session.
- Operators order: Processing, Delivery, Translation (direction), Experimental last. "Selected text is" shows inside Experimental, only while the switch is on.
- Every pane has a one-line summary under its title (`UntypeSettingsPane.summary`). The "locked while a session is active" note shows only on the panes that have such settings (`locksWhileSessionActive`).
- Permissions & Keys lists Screen & System Audio Recording with the other macOS permissions.
- Stepper rows (sample rate, stop after silence): value and stepper together at the right edge.
- No setting changed its meaning, its stored key or its default.

## Verification

`swift build`, 401/401 tests, and off-screen renders of the General, Meetings, Operators, Speech and Permissions panes. Not yet looked at in the installed app.
