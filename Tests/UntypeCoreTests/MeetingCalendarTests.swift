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
    others: [CalendarAttendee] = [CalendarAttendee(name: "ΠΑΠΑΔΟΠΟΥΛΟΣ ΓΙΑΝΝΗΣ", address: "k@example.com", required: true, response: "accepted")]
) -> CalendarMeeting {
    var attendees = others
    if let myResponse {
        attendees.append(CalendarAttendee(name: "ALEX DOE", address: me, required: true, response: myResponse))
    }
    return CalendarMeeting(id: id, subject: subject, start: start, end: end, online: online, organizerName: "BOSS", organizerAddress: organizer, attendees: attendees)
}

@Test func parsesAGraphEventFromTheCLI() throws {
    let json = """
    {"data":{"id":"A1","subject":"📊 QUARTERLY PLANNING | internal call","isOnlineMeeting":true,
     "start":{"dateTime":"2026-11-11T10:00:00.0000000","timeZone":"Europe/Athens"},
     "end":{"dateTime":"2026-11-11T11:00:00.0000000","timeZone":"Europe/Athens"},
     "organizer":{"emailAddress":{"name":"ALEX DOE","address":"alex.doe@example.com"}},
     "attendees":[{"type":"optional","status":{"response":"none"},"emailAddress":{"name":"Jane Smith","address":"j@partner.example"}},
                  {"type":"required","status":{"response":"accepted"},"emailAddress":{"name":"ΠΑΠΑΔΟΠΟΥΛΟΣ ΓΙΑΝΝΗΣ","address":"k@example.com"}}]}}
    """
    let event = try MeetingCalendar.parseEvent(Data(json.utf8))
    #expect(event.id == "A1")
    #expect(event.online)
    #expect(event.start == at(10))
    #expect(event.end == at(11))
    #expect(event.attendees.map(\.required) == [false, true])
    #expect(MeetingCalendar.myResponse(event, me: me) == "organizer")
    #expect(MeetingCalendar.participants(event, me: me) == ["Παπαδοπουλος Γιαννης"])
    #expect(try MeetingCalendar.listedIDs(Data(#"{"data":[{"id":"A1"},{"id":"B2"}]}"#.utf8)) == ["A1", "B2"])
    #expect(try MeetingCalendar.signedInAddress(Data(#"{"data":{"email":"x@example.com","status":"authenticated"}}"#.utf8)) == "x@example.com")
}

@Test func theCalendarIsAskedForTheLocalDayInExactInstants() {
    var athens = Calendar(identifier: .gregorian)
    athens.timeZone = TimeZone(identifier: "Europe/Athens")!
    let start = athens.startOfDay(for: at(0, 10))
    let next = athens.date(byAdding: .day, value: 1, to: start)!
    #expect(MeetingCalendar.listRange(from: start, to: next) == ["--start", "2026-11-10T22:00:00Z", "--end", "2026-11-11T22:00:00Z"])
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

/// Reads today's real calendar with the installed m365-calendar CLI
/// (`UNTYPE_LIVE_CALENDAR_TEST=1`).
@Test(.enabled(if: ProcessInfo.processInfo.environment["UNTYPE_LIVE_CALENDAR_TEST"] == "1"))
func liveCalendarReadsTodaysMeetings() async throws {
    let executable = try #require(OutlookCalendarCLI.discover())
    let cli = OutlookCalendarCLI(executable: executable)
    let address = try await cli.signedInAddress()
    let meetings = try await cli.meetings(on: Date())
    for meeting in meetings.sorted(by: { $0.start < $1.start }) {
        let attended = MeetingCalendar.isAttended(meeting, me: address)
        print("[live] \(meeting.start) attended=\(attended) online=\(meeting.online) \(MeetingCalendar.plainTitle(meeting, me: address)) | \(MeetingCalendar.reminderDetail(meeting, me: address))")
    }
    #expect(!address.isEmpty)
}
