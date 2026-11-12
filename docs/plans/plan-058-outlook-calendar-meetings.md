# Plan 058 — Meetings from the Outlook calendar: reminder and name

## Request
untype knows the user's meetings (the Outlook calendar, read through the `nbg-m365` CLI that the Claude Code M365 skills use). When a meeting starts, untype says so and offers to record it, as a reminder: not every meeting is joined, but any may be joined and recorded on demand. A recording made during a meeting, even one that runs longer, takes the meeting's refined name and lists its required participants, unless the user renames it.

## What the user sees
- **Settings → General → Meeting recording → Use my Outlook calendar.** On: the Calendar line shows "6 meetings today · next: HR check at 16:30", or what is wrong (CLI not found, not signed in).
- **Starting now.** At the start of a Teams meeting the user organizes or accepted, the overlay shows a card: a red dot, "Starting now · Teams · 6 people", the meeting's subject, **Record** and **Dismiss**. Record starts recording that meeting. The card stays for the whole meeting (its caption becomes "Started 12 min ago") until Record or Dismiss; Dismiss is final for that meeting (a meeting moved to another time reminds again), since not every meeting is joined.
- **The name.** When a recording made during a meeting stops, the overlay says "Naming it from your calendar…" and then shows the saved card with the meeting's title, e.g. "Accounting reconciliation · Athanasios Karamitsios, Georgios Fotopoulos" or "Power Platform team weekly · 17 people". Rename on the card works as before and wins.
- **The transcript** starts with what the meeting was: subject, calendar time, organizer, participants (required) and optional ones; `meeting.json` keeps the calendar entry.

## Decisions
- **One meeting at a time.** The user attends one meeting at a time. When two meetings qualify for a recording, the one it overlaps most is taken.
- **Which meetings count.** It is online (a Teams link) or someone else is invited, it is not cancelled, and the user organizes it or accepted it (tentatively too). Declined and unanswered invitations do not count; Focus time and other personal blocks have neither a Teams link nor anyone else invited.
- **Reminders for Teams meetings only**, from the start time to the end. A recording is matched to any meeting that counts (also in person).
- **Matching.** The recording starts within 10 minutes before the meeting's start and before its end; it may run past the end.
- **The CLI, not Graph directly.** The `nbg-m365` CLI keeps the Microsoft 365 sign-in and token; untype only runs it (`status`, `calendar list`, `calendar read`). The switch stores the CLI's path (`meeting.calendarCLI`); off (nil) means untype behaves as without a calendar — other users of untype are not affected.
- **Title.** The primary LLM makes it from the subject and the required participants (names in Latin letters, at most three, else a count); with no answer the cleaned subject and the names are used.
- **Push-to-talk first.** The card is shown only when the overlay is idle and the hotkey is up; pressing the hotkey replaces it and it comes back after the dictation.

## Build order
1. Pure rules and the CLI runner (`MeetingCalendar.swift`), unit tests, a live test against the real calendar (`UNTYPE_LIVE_CALENDAR_TEST=1`).
2. Model: calendar watch (15 s tick, refresh every 5 min), reminder queue, naming at stop.
3. Overlay reminder card; Settings switch.
4. Docs: functions (FR-64), design, configuration guide, issues.

## Checks
- `swift test` green; the live test lists today's meetings with the right local times and filters.
- On device: see `Issues - Pending Items.md`.
