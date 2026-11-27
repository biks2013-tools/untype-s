import Foundation
import Testing
@testable import UntypeCore

private let me = "alex.doe@example.com"

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    var parts = DateComponents()
    parts.year = 2026
    parts.month = 11
    parts.day = 11
    parts.hour = hour
    parts.minute = minute
    parts.timeZone = TimeZone(identifier: "Europe/Athens")
    return Calendar(identifier: .gregorian).date(from: parts)!
}

private func meeting(
    _ id: String,
    _ subject: String = "Weekly",
    from start: Date,
    to end: Date,
    online: Bool = true,
    organizer: String = "boss@example.com",
    myResponse: String? = "accepted",
    others: [CalendarAttendee] = [CalendarAttendee(name: "ΠΑΠΑΔΟΠΟΥΛΟΣ ΓΙΑΝΝΗΣ", address: "g@example.com", required: true, response: "accepted")]
) -> CalendarMeeting {
    var attendees = others
    if let myResponse {
        attendees.append(CalendarAttendee(name: "ALEX DOE", address: me, required: true, response: myResponse))
    }
    return CalendarMeeting(id: id, subject: subject, start: start, end: end, online: online, organizerName: "BOSS", organizerAddress: organizer, attendees: attendees)
}

@Test func parsesTheCalendarCommandsDocument() throws {
    let json = """
    {"owner":{"name":"Alex Doe","address":"alex.doe@example.com"},"timeZone":"Europe/Athens",
     "events":[
      {"id":"A1","subject":"📊 QUARTERLY PLANNING | internal call","allDay":false,
       "start":"2026-11-11T10:00:00+02:00","end":"2026-11-11T11:00:00+02:00",
       "myResponse":"organizer","onlineMeeting":{"joinUrl":"https://teams.example.com/j/1"},"teamsMeeting":true,
       "organizer":{"name":"ALEX DOE","address":"alex.doe@example.com"},
       "attendees":[{"type":"optional","response":"none","name":"Jane Smith","address":"j@partner.example"},
                    {"type":"required","response":"accepted","name":"ΠΑΠΑΔΟΠΟΥΛΟΣ ΓΙΑΝΝΗΣ","address":"g@example.com"}]},
      {"id":"H1","subject":"Holiday","allDay":true,"start":"2026-11-11","end":"2026-11-12"},
      {"subject":"In the room","start":"2026-11-11T12:00:00.000+02:00","end":"2026-11-11T12:30:00.000+02:00",
       "myResponse":"tentativelyAccepted","teamsMeeting":false,"attendees":[]}]}
    """
    let document = try MeetingCalendar.parseDocument(Data(json.utf8))
    #expect(document.me == me)
    #expect(document.meetings.map(\.subject) == ["📊 QUARTERLY PLANNING | internal call", "In the room"])
    let event = document.meetings[0]
    #expect(event.id == "A1")
    #expect(event.online)
    #expect(event.start == at(10))
    #expect(event.end == at(11))
    #expect(event.attendees.map(\.required) == [false, true])
    #expect(MeetingCalendar.myResponse(event, me: me) == "organizer")
    #expect(MeetingCalendar.participants(event, me: me) == ["Παπαδοπουλος Γιαννης"])
    let room = document.meetings[1]
    #expect(!room.online)
    #expect(room.start == at(12))
    #expect(room.id == "In the room@\(Int(at(12).timeIntervalSince1970))")
    #expect(MeetingCalendar.myResponse(room, me: me) == "tentativelyAccepted")
}

@Test func aCalendarDocumentWithoutItsOwnerOrDatesIsAnError() {
    #expect(throws: UntypeError.self) {
        try MeetingCalendar.parseDocument(Data(#"{"events":[]}"#.utf8))
    }
    #expect(throws: UntypeError.self) {
        try MeetingCalendar.parseDocument(Data(#"[{"subject":"x"}]"#.utf8))
    }
    #expect(throws: UntypeError.self) {
        try MeetingCalendar.parseDocument(Data(#"{"owner":{"address":"a@b.c"},"events":[{"subject":"x","start":"tomorrow","end":"later"}]}"#.utf8))
    }
    #expect(throws: UntypeError.self) {
        try MeetingCalendar.parseDocument(Data("not json".utf8))
    }
}

@Test func theCalendarCommandNeedsBothDaysAndIsAskedForTheLocalDay() throws {
    #expect(throws: UntypeError.self) { try CalendarCommand(template: "  ") }
    #expect(throws: UntypeError.self) { try CalendarCommand(template: "cal --from {from}") }
    var athens = Calendar(identifier: .gregorian)
    athens.timeZone = TimeZone(identifier: "Europe/Athens")!
    let command = try CalendarCommand(template: " /bin/cal export --from {from} --to {to} ")
    // 00:10 in Athens is still the previous day in UTC: the local day is asked.
    #expect(command.commandLine(from: at(0, 10), to: at(0, 10), calendar: athens)
        == "/bin/cal export --from 2026-11-11 --to 2026-11-11")
}

@Test func theCalendarCommandRunsThroughTheShell() async throws {
    let json = #"{"owner":{"address":"alex.doe@example.com"},"events":[{"subject":"S","start":"2026-11-11T10:00:00+02:00","end":"2026-11-11T11:00:00+02:00"}]}"#
    let command = try CalendarCommand(template: "printf '%s' '\(json)' # {from} {to}")
    let day = try await command.meetings(on: at(10))
    #expect(day.me == me)
    #expect(day.meetings.map(\.subject) == ["S"])

    await #expect(throws: UntypeError.self) {
        _ = try await CalendarCommand.run("echo oops >&2; exit 3", timeout: 10)
    }
    let started = Date()
    await #expect(throws: UntypeError.self) {
        _ = try await CalendarCommand.run("sleep 5 | cat", timeout: 0.5)
    }
    #expect(Date().timeIntervalSince(started) < 3)
}

@Test func onlyAcceptedOrOwnMeetingsWithOtherPeopleCount() {
    #expect(MeetingCalendar.isAttended(meeting("a", from: at(10), to: at(11)), me: me))
    #expect(MeetingCalendar.isAttended(meeting("t", from: at(10), to: at(11), myResponse: "tentativelyAccepted"), me: me))
    #expect(MeetingCalendar.isAttended(meeting("o", from: at(10), to: at(11), organizer: me, myResponse: nil), me: me))
    #expect(!MeetingCalendar.isAttended(meeting("d", from: at(10), to: at(11), myResponse: "declined"), me: me))
    #expect(!MeetingCalendar.isAttended(meeting("n", from: at(10), to: at(11), myResponse: "none"), me: me))
    #expect(!MeetingCalendar.isAttended(meeting("c", "Canceled: Weekly", from: at(10), to: at(11)), me: me))
    #expect(!MeetingCalendar.isAttended(meeting("f", "Focus time", from: at(8), to: at(10), online: false, organizer: me, myResponse: nil, others: []), me: me))
    // A Teams meeting the user set up counts even before anyone is invited.
    #expect(MeetingCalendar.isAttended(meeting("solo", "test", from: at(23, 30), to: at(23, 59), organizer: me, myResponse: nil, others: []), me: me))
}

@Test func aRecordingBelongsToTheMeetingItStartsIn() {
    let first = meeting("first", from: at(10), to: at(11))
    let second = meeting("second", from: at(11), to: at(12))
    let declined = meeting("declined", from: at(10), to: at(11), myResponse: "declined")
    let all = [declined, first, second]
    // Started a little early, ran past the end.
    #expect(MeetingCalendar.meeting(forRecordingFrom: at(9, 55), to: at(11, 20), in: all, me: me)?.id == "first")
    // Started in the next meeting's early window but overlapping the first more.
    #expect(MeetingCalendar.meeting(forRecordingFrom: at(10, 52), to: at(11, 5), in: all, me: me)?.id == "first")
    #expect(MeetingCalendar.meeting(forRecordingFrom: at(10, 55), to: at(11, 50), in: all, me: me)?.id == "second")
    // Too early, or after every meeting.
    #expect(MeetingCalendar.meeting(forRecordingFrom: at(9, 40), to: at(9, 45), in: all, me: me) == nil)
    #expect(MeetingCalendar.meeting(forRecordingFrom: at(12, 5), to: at(12, 30), in: all, me: me) == nil)
}

@Test func theReminderStaysForTheWholeOnlineMeetingUntilAnswered() {
    var queue = MeetingReminderQueue()
    let teams = meeting("teams", from: at(14), to: at(15))
    let inPerson = meeting("room", from: at(14), to: at(15), online: false)
    let unanswered = meeting("none", from: at(14), to: at(15), myResponse: "none")
    let all = [teams, inPerson, unanswered]
    #expect(queue.current(now: at(13, 59), meetings: all, me: me, recording: false) == nil)
    #expect(queue.current(now: at(14), meetings: all, me: me, recording: false)?.id == "teams")
    #expect(queue.current(now: at(14, 1), meetings: all, me: me, recording: true) == nil)
    #expect(queue.current(now: at(14, 2), meetings: all, me: me, recording: false)?.id == "teams")
    // Unanswered, it stays until the meeting ends.
    #expect(queue.current(now: at(14, 59), meetings: all, me: me, recording: false)?.id == "teams")
    #expect(queue.current(now: at(15), meetings: all, me: me, recording: false) == nil)
    #expect(MeetingCalendar.reminderCaption(teams, now: at(14, 1)) == "Starting now")
    #expect(MeetingCalendar.reminderCaption(teams, now: at(14, 12)) == "Started 12 min ago")

    var dismissed = MeetingReminderQueue()
    #expect(dismissed.current(now: at(14, 3), meetings: all, me: me, recording: false)?.id == "teams")
    dismissed.handle(teams)
    #expect(dismissed.current(now: at(14, 4), meetings: all, me: me, recording: false) == nil)
    // Moved to a later time, the same meeting reminds again.
    let moved = meeting("teams", from: at(16), to: at(16, 30))
    #expect(dismissed.current(now: at(16, 1), meetings: [moved], me: me, recording: false)?.id == "teams")
    // untype started late: still shown while the meeting is on.
    var late = MeetingReminderQueue()
    #expect(late.current(now: at(14, 40), meetings: all, me: me, recording: false)?.id == "teams")
}

@Test func subjectsAndTitlesReadCleanly() {
    #expect(MeetingCalendar.cleanSubject("📊 QUARTERLY PLANNING | internal call") == "Quarterly planning | internal call")
    #expect(MeetingCalendar.cleanSubject("FW: Design Team Weekly") == "Design Team Weekly")
    #expect(MeetingCalendar.cleanSubject("HR check") == "HR check")
    #expect(MeetingCalendar.displayName("ALEX DOE") == "Alex Doe")
    #expect(MeetingCalendar.displayName("Jane Smith") == "Jane Smith")

    let small = meeting("s", "HR check", from: at(16), to: at(17), others: [
        CalendarAttendee(name: "MARIA LOPEZ", address: "m@example.com", required: true, response: "accepted"),
        CalendarAttendee(name: "Room 4", address: "room@example.com", required: false, response: "accepted")
    ])
    #expect(MeetingCalendar.plainTitle(small, me: me) == "HR check · Boss, Maria Lopez")
    let crowd = (1...6).map { CalendarAttendee(name: "P\($0)", address: "p\($0)@example.com", required: true, response: "accepted") }
    #expect(MeetingCalendar.plainTitle(meeting("c", "Team weekly", from: at(14), to: at(15), others: crowd), me: me) == "Team weekly · 7 people")

    var athens = Calendar(identifier: .gregorian)
    athens.timeZone = TimeZone(identifier: "Europe/Athens")!
    let header = MeetingCalendar.transcriptHeader(small, me: me, calendar: athens)
    #expect(header.hasPrefix("Meeting: HR check\nCalendar: Wed 11 Nov 2026 16:00–17:00 · online\nOrganizer: Boss\nParticipants: Maria Lopez, Alex Doe\nOptional: Room 4\n\n"))
    #expect(MeetingCalendar.reminderDetail(small, me: me) == "Teams · 3 people")
}

/// Runs the calendar command given in `UNTYPE_LIVE_CALENDAR_COMMAND` for
/// today (opt-in; prints counts only, no meeting text).
@Test(.enabled(if: ProcessInfo.processInfo.environment["UNTYPE_LIVE_CALENDAR_COMMAND"] != nil))
func liveCalendarReadsTodaysMeetings() async throws {
    let line = try #require(ProcessInfo.processInfo.environment["UNTYPE_LIVE_CALENDAR_COMMAND"])
    let day = try await CalendarCommand(template: line).meetings(on: Date())
    let attended = day.meetings.filter { MeetingCalendar.isAttended($0, me: day.me) }
    print("[live] \(day.meetings.count) events today, \(attended.count) attended, \(attended.filter(\.online).count) online")
    #expect(!day.me.isEmpty)
}
