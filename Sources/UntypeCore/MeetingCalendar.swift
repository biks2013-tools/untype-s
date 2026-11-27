#if os(macOS)
import Foundation

/// One person invited to a calendar meeting.
public struct CalendarAttendee: Codable, Sendable, Equatable {
    public var name: String
    public var address: String
    /// A required ("mandatory") attendee; false for optional ones and rooms.
    public var required: Bool
    /// Graph's response: `accepted`, `tentativelyAccepted`, `declined`,
    /// `none`, `notResponded`, `organizer`.
    public var response: String

    public init(name: String, address: String, required: Bool, response: String) {
        self.name = name
        self.address = address
        self.required = required
        self.response = response
    }
}

/// One event of the user's calendar.
public struct CalendarMeeting: Codable, Sendable, Equatable {
    public var id: String
    public var subject: String
    public var start: Date
    public var end: Date
    public var online: Bool
    public var organizerName: String
    public var organizerAddress: String
    public var attendees: [CalendarAttendee]
    /// The user's own answer as the calendar gives it (`organizer`,
    /// `accepted`, `tentativelyAccepted`, `declined`, `notResponded`, …);
    /// nil: worked out from the organizer and the attendees.
    public var myResponse: String?

    public init(
        id: String,
        subject: String,
        start: Date,
        end: Date,
        online: Bool,
        organizerName: String,
        organizerAddress: String,
        attendees: [CalendarAttendee],
        myResponse: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.start = start
        self.end = end
        self.online = online
        self.organizerName = organizerName
        self.organizerAddress = organizerAddress
        self.attendees = attendees
        self.myResponse = myResponse
    }
}

/// The rules that link meetings in the calendar to recordings and reminders.
public enum MeetingCalendar {
    /// A recording that starts up to this long before a meeting belongs to it.
    public static let earlyStart: TimeInterval = 10 * 60

    // MARK: Reading the calendar command's JSON

    /// The calendar document the calendar command prints — the format of
    /// `m365mail calendar export`:
    ///
    ///     { "owner": { "name": …, "address": "me@example.com" },
    ///       "events": [ { "id", "subject", "start", "end", "allDay",
    ///                     "myResponse", "onlineMeeting": { "joinUrl" },
    ///                     "teamsMeeting", "organizer": { "name", "address" },
    ///                     "attendees": [ { "name", "address",
    ///                                      "type", "response" } ] } ] }
    ///
    /// `owner.address` (the user) and each event's `start` and `end` (ISO
    /// 8601 with an offset) are required; all-day events are left out
    /// (never a meeting to record); unknown fields are ignored.
    public static func parseDocument(_ data: Data) throws -> (me: String, meetings: [CalendarMeeting]) {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            let head = String(decoding: data.prefix(120), as: UTF8.self)
            throw UntypeError.invalidConfiguration("The calendar command did not print JSON: \(head.isEmpty ? "empty output" : head)")
        }
        guard let object = root as? [String: Any], let events = object["events"] as? [Any] else {
            throw UntypeError.invalidConfiguration("The calendar command's JSON has no \"events\" list ({\"owner\": …, \"events\": [...]}).")
        }
        guard let owner = object["owner"] as? [String: Any],
              let me = owner["address"] as? String, !me.isEmpty else {
            throw UntypeError.invalidConfiguration("The calendar command's JSON does not say whose calendar it is (\"owner\": {\"address\": …}).")
        }
        var meetings: [CalendarMeeting] = []
        for (index, item) in events.enumerated() {
            guard let event = item as? [String: Any] else {
                throw UntypeError.invalidConfiguration("Calendar event \(index + 1) is not an object.")
            }
            if event["allDay"] as? Bool == true {
                continue
            }
            meetings.append(try parseEvent(event, index: index))
        }
        return (me, meetings)
    }

    static func parseEvent(_ event: [String: Any], index: Int) throws -> CalendarMeeting {
        func text(_ value: Any?) -> String? {
            guard let value = value as? String, !value.isEmpty else {
                return nil
            }
            return value
        }
        let subject = text(event["subject"]) ?? ""
        guard let start = text(event["start"]).flatMap(date), let end = text(event["end"]).flatMap(date) else {
            throw UntypeError.invalidConfiguration("Calendar event \(index + 1) (\(subject)) has no readable start or end (ISO 8601 with an offset).")
        }
        let organizer = event["organizer"] as? [String: Any]
        let attendees: [CalendarAttendee] = (event["attendees"] as? [[String: Any]] ?? []).compactMap { attendee in
            guard let address = text(attendee["address"]) else {
                return nil
            }
            return CalendarAttendee(
                name: text(attendee["name"]) ?? address,
                address: address,
                required: (attendee["type"] as? String) == "required",
                response: text(attendee["response"]) ?? "none"
            )
        }
        let joinURL = text((event["onlineMeeting"] as? [String: Any])?["joinUrl"])
        return CalendarMeeting(
            id: text(event["id"]) ?? text(event["iCalUId"]) ?? "\(subject)@\(Int(start.timeIntervalSince1970))",
            subject: subject,
            start: start,
            end: end,
            online: joinURL != nil || event["teamsMeeting"] as? Bool == true,
            organizerName: text(organizer?["name"]) ?? "",
            organizerAddress: text(organizer?["address"]) ?? "",
            attendees: attendees,
            myResponse: text(event["myResponse"])
        )
    }

    /// `2026-11-11T10:00:00+02:00`, with or without fractional seconds.
    static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    // MARK: Which meetings count

    /// Outlook's prefix on a meeting the organizer cancelled.
    public static func isCancelled(_ meeting: CalendarMeeting) -> Bool {
        let subject = meeting.subject.lowercased()
        return ["canceled:", "cancelled:", "ακυρώθηκε:", "ακυρωμένη:"].contains { subject.hasPrefix($0) }
    }

    /// The user organizes the meeting.
    public static func isOrganizer(_ meeting: CalendarMeeting, me: String) -> Bool {
        meeting.organizerAddress.caseInsensitiveCompare(me) == .orderedSame
    }

    /// The user's answer to the invitation: the calendar's own when it
    /// gives one; else `organizer` for their own meetings, else their entry
    /// among the attendees (`none` when missing).
    public static func myResponse(_ meeting: CalendarMeeting, me: String) -> String {
        if let answer = meeting.myResponse {
            return answer
        }
        if isOrganizer(meeting, me: me) {
            return "organizer"
        }
        return meeting.attendees.first { $0.address.caseInsensitiveCompare(me) == .orderedSame }?.response ?? "none"
    }

    /// Everyone invited except the user (and the organizer when it is not
    /// the user).
    public static func others(_ meeting: CalendarMeeting, me: String) -> [CalendarAttendee] {
        var people = meeting.attendees.filter { $0.address.caseInsensitiveCompare(me) != .orderedSame }
        if !isOrganizer(meeting, me: me), !meeting.organizerAddress.isEmpty,
           !people.contains(where: { $0.address.caseInsensitiveCompare(meeting.organizerAddress) == .orderedSame }) {
            people.insert(CalendarAttendee(name: meeting.organizerName, address: meeting.organizerAddress, required: true, response: "organizer"), at: 0)
        }
        return people
    }

    /// A meeting the user attends: it is online (a Teams link) or someone
    /// else is invited, it is not cancelled, and the user organizes it or
    /// accepted it (tentatively too). Declined and unanswered invitations do
    /// not count; personal blocks such as Focus time have neither.
    public static func isAttended(_ meeting: CalendarMeeting, me: String) -> Bool {
        guard !isCancelled(meeting), meeting.online || !others(meeting, me: me).isEmpty else {
            return false
        }
        return ["organizer", "accepted", "tentativelyAccepted"].contains(myResponse(meeting, me: me))
    }

    /// The meeting a recording belongs to: an attended meeting the recording
    /// starts in (or up to `earlyStart` before); when several qualify, the
    /// one it overlaps most. The recording may run past the meeting's end.
    public static func meeting(forRecordingFrom start: Date, to end: Date, in meetings: [CalendarMeeting], me: String) -> CalendarMeeting? {
        let candidates = meetings.filter { meeting in
            isAttended(meeting, me: me)
                && start >= meeting.start.addingTimeInterval(-earlyStart)
                && start < meeting.end
        }
        func overlap(_ meeting: CalendarMeeting) -> TimeInterval {
            max(0, min(end, meeting.end).timeIntervalSince(max(start, meeting.start)))
        }
        return candidates.max { left, right in
            overlap(left) == overlap(right) ? left.start > right.start : overlap(left) < overlap(right)
        }
    }

    // MARK: Names and participants

    /// A calendar name as people write it: "ΠΑΠΑΔΟΠΟΥΛΟΣ ΓΙΑΝΝΗΣ" becomes
    /// "Παπαδοπουλος Γιαννης"; names already in mixed case stay as they are.
    public static func displayName(_ name: String) -> String {
        let trimmed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard trimmed == trimmed.uppercased(), trimmed != trimmed.lowercased() else {
            return trimmed
        }
        return trimmed.lowercased().split(separator: " ").map { word in
            // Greek: a word ends with the final sigma.
            let word = word.hasSuffix("σ") ? word.dropLast() + "ς" : word
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// The required participants (the organizer first), without the user.
    public static func participants(_ meeting: CalendarMeeting, me: String) -> [String] {
        others(meeting, me: me).filter(\.required).map { displayName($0.name) }
    }

    /// The subject without emoji, decorations and Outlook prefixes, in
    /// sentence case when it was written in capitals:
    /// "📊 QUARTERLY PLANNING | internal call" →
    /// "Quarterly planning | internal call".
    public static func cleanSubject(_ subject: String) -> String {
        var text = String(subject.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C) || scalar.value == 0xFE0F || scalar.value == 0x200D)
        }.map(Character.init))
        for prefix in ["fw:", "fwd:", "re:"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " -–—|·:"))
        // Words in capitals (longer than an acronym) are lowered; the first
        // letter of the subject stays a capital.
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let letters = word.filter(\.isLetter)
            if letters.count > 4, String(letters) == letters.uppercased(), String(letters) != letters.lowercased() {
                return word.lowercased()
            }
            return String(word)
        }
        text = words.joined(separator: " ")
        guard let first = text.first else {
            return text
        }
        return first.uppercased() + text.dropFirst()
    }

    /// The meeting's title when the model cannot make one: the clean
    /// subject, then up to three participants or how many people were there.
    public static func plainTitle(_ meeting: CalendarMeeting, me: String) -> String {
        let topic = cleanSubject(meeting.subject)
        let people = participants(meeting, me: me)
        let who: String
        switch people.count {
        case 0: who = ""
        case 1...3: who = people.joined(separator: ", ")
        default: who = "\(people.count) people"
        }
        let title = who.isEmpty ? topic : "\(topic) · \(who)"
        return MeetingNaming.sanitize(title)
    }

    /// What the title model is given.
    public static func titleRequest(_ meeting: CalendarMeeting, me: String) -> String {
        let people = participants(meeting, me: me)
        return """
        Calendar subject: \(meeting.subject)
        Required participants (\(people.count)): \(people.isEmpty ? "none" : people.joined(separator: ", "))
        """
    }

    public static let titlePrompt = """
    You turn a calendar meeting into the title of its recording, written in English.
    Format: "<topic> · <people>", for example "Quarterly planning · Jane Doe, John Smith" or "Design team weekly · 17 people".
    Topic: the calendar subject in 2 to 8 words, sentence case (keep acronyms and product names), without emoji, decorations, "FW:"/"RE:" prefixes or labels like "internal call"; translate Greek into English.
    People: when there are 1 to 3 required participants, their names in Latin letters with normal capitalization, given name first when you can tell, separated by commas; when there are more, write "<count> people"; when there are none, write only the topic.
    No date, no quotes, no trailing period, no slashes or colons. Output only the title.
    """

    /// A short header that says what the meeting was, placed above the
    /// transcript lines.
    public static func transcriptHeader(_ meeting: CalendarMeeting, me: String, calendar: Calendar = .current) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.dateFormat = "EEE d MMM yyyy HH:mm"
        let time = DateFormatter()
        time.locale = day.locale
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"
        var lines = [
            "Meeting: \(meeting.subject)",
            "Calendar: \(day.string(from: meeting.start))–\(time.string(from: meeting.end))\(meeting.online ? " · online" : "")",
            "Organizer: \(displayName(meeting.organizerName))"
        ]
        let required = meeting.attendees.filter(\.required).map { displayName($0.name) }
        let optional = meeting.attendees.filter { !$0.required }.map { displayName($0.name) }
        lines.append("Participants: \(required.isEmpty ? "none" : required.joined(separator: ", "))")
        if !optional.isEmpty {
            lines.append("Optional: \(optional.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n") + "\n\n"
    }

    /// The reminder card's caption: "Starting now" in the first two
    /// minutes, then "Started 12 min ago".
    public static func reminderCaption(_ meeting: CalendarMeeting, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(meeting.start) / 60)
        return minutes < 2 ? "Starting now" : "Started \(minutes) min ago"
    }

    /// The reminder card's second line: "Teams · 6 people".
    public static func reminderDetail(_ meeting: CalendarMeeting, me: String) -> String {
        let count = others(meeting, me: me).count
        let place = meeting.online ? "Teams" : "In person"
        return "\(place) · \(count == 1 ? "1 person" : "\(count) people")"
    }
}

/// Which meeting the reminder card shows: an attended online meeting, for
/// its whole duration, until the user records it or dismisses the card.
public struct MeetingReminderQueue: Sendable {
    private var handled: Set<String> = []

    public init() {}

    /// The meeting to show now (nil: none). Nothing is shown while a
    /// meeting is being recorded.
    public mutating func current(now: Date, meetings: [CalendarMeeting], me: String, recording: Bool) -> CalendarMeeting? {
        guard !recording else {
            return nil
        }
        let due = meetings
            .filter { meeting in
                meeting.online
                    && MeetingCalendar.isAttended(meeting, me: me)
                    && !handled.contains(Self.key(meeting))
                    && now >= meeting.start
                    && now < meeting.end
            }
            .sorted { $0.start == $1.start ? $0.subject < $1.subject : $0.start > $1.start }
        return due.first
    }

    /// Recorded or dismissed: not shown again — unless the meeting is
    /// moved to another time, which makes it a new reminder.
    public mutating func handle(_ meeting: CalendarMeeting) {
        handled.insert(Self.key(meeting))
    }

    private static func key(_ meeting: CalendarMeeting) -> String {
        "\(meeting.id)@\(Int(meeting.start.timeIntervalSince1970))"
    }
}

/// The calendar command (Settings → Meetings → Calendar, FR-87): a shell
/// command line in which `{from}` and `{to}` are replaced by the first and
/// last day (YYYY-MM-DD, local time, both included) and which prints the
/// calendar as JSON (`MeetingCalendar.parseDocument`), e.g.
///
///     /full/path/m365mail calendar export --from {from} --to {to} --no-description
///
/// It runs through `/bin/sh -c`; untype never sees a sign-in or a token.
/// Apps started from the Dock have a short PATH, so the program is given
/// with its full path.
public struct CalendarCommand: Sendable {
    /// Longest one run may take.
    public static let timeoutSeconds: TimeInterval = 45

    public let template: String

    public init(template: String) throws {
        let line = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            throw UntypeError.invalidConfiguration("No calendar command is set (Settings → Meetings → Calendar).")
        }
        guard line.contains("{from}"), line.contains("{to}") else {
            throw UntypeError.invalidConfiguration("The calendar command must contain {from} and {to}; they are replaced by the first and last day (YYYY-MM-DD).")
        }
        self.template = line
    }

    /// The command line for the days `from`…`to`.
    public func commandLine(from: Date, to: Date, calendar: Calendar = .current) -> String {
        template
            .replacingOccurrences(of: "{from}", with: Self.day(from, calendar))
            .replacingOccurrences(of: "{to}", with: Self.day(to, calendar))
    }

    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The user's address and the meetings of the day `day` (local).
    public func meetings(on day: Date, calendar: Calendar = .current) async throws -> (me: String, meetings: [CalendarMeeting]) {
        let data = try await Self.run(commandLine(from: day, to: day, calendar: calendar), timeout: Self.timeoutSeconds)
        return try MeetingCalendar.parseDocument(data)
    }

    /// Runs `line` with `/bin/sh -c` and returns what it printed. Both
    /// pipes are read while it runs (a large calendar cannot stall it). On
    /// the timeout the shell is stopped and the run fails at once, without
    /// waiting for the pipes, which a child of the shell may still hold.
    static func run(_ line: String, timeout: TimeInterval) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", line]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        let run = CalendarCommandRun()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                run.finishOutput()
            } else {
                run.appendOutput(chunk)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                run.appendErrors(chunk)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            run.continuation = continuation
            process.terminationHandler = { process in
                run.finishProcess(status: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                run.fail(UntypeError.invalidConfiguration("The calendar command could not be started: \(error.localizedDescription)"))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
                run.fail(UntypeError.invalidConfiguration("The calendar command did not finish within \(Int(timeout)) s."))
            }
        }
    }
}

/// One run of the calendar command: its output, and the continuation
/// resumed once — when the process has ended and its output is complete,
/// or on a failure.
private final class CalendarCommandRun: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var errors = Data()
    private var outputDone = false
    private var status: Int32?
    private var resumed = false
    var continuation: CheckedContinuation<Data, Error>?

    func appendOutput(_ chunk: Data) {
        lock.lock(); output.append(chunk); lock.unlock()
    }

    func appendErrors(_ chunk: Data) {
        lock.lock(); errors.append(chunk); lock.unlock()
    }

    func finishOutput() {
        lock.lock(); outputDone = true; lock.unlock()
        complete()
    }

    func finishProcess(status: Int32) {
        lock.lock(); self.status = status; lock.unlock()
        complete()
    }

    func fail(_ error: Error) {
        lock.lock()
        guard !resumed, let continuation else {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        continuation.resume(throwing: error)
    }

    private func complete() {
        lock.lock()
        guard !resumed, outputDone, let status, let continuation else {
            lock.unlock()
            return
        }
        resumed = true
        let output = output
        let detail = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        if status == 0 {
            continuation.resume(returning: output)
        } else {
            continuation.resume(throwing: UntypeError.invalidConfiguration(
                "The calendar command failed (exit \(status))" + (detail.isEmpty ? "." : ": \(detail.prefix(300))")
            ))
        }
    }
}
#endif
