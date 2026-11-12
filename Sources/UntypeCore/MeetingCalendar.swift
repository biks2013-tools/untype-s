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

/// One event of the user's Outlook calendar.
public struct CalendarMeeting: Codable, Sendable, Equatable {
    public var id: String
    public var subject: String
    public var start: Date
    public var end: Date
    public var online: Bool
    public var organizerName: String
    public var organizerAddress: String
    public var attendees: [CalendarAttendee]

    public init(
        id: String,
        subject: String,
        start: Date,
        end: Date,
        online: Bool,
        organizerName: String,
        organizerAddress: String,
        attendees: [CalendarAttendee]
    ) {
        self.id = id
        self.subject = subject
        self.start = start
        self.end = end
        self.online = online
        self.organizerName = organizerName
        self.organizerAddress = organizerAddress
        self.attendees = attendees
    }
}

/// The rules that link meetings in the calendar to recordings and reminders.
public enum MeetingCalendar {
    /// A recording that starts up to this long before a meeting belongs to it.
    public static let earlyStart: TimeInterval = 10 * 60

    // MARK: Reading the CLI's JSON

    /// The event ids of `calendar list --json` (`{ "data": [ { "id": … } ] }`).
    public static func listedIDs(_ data: Data) throws -> [String] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = object["data"] as? [[String: Any]] else {
            throw UntypeError.invalidConfiguration("The calendar list is not in the expected format ({\"data\": [...]}).")
        }
        return events.compactMap { $0["id"] as? String }
    }

    /// One event of `calendar read <id> --json` (Graph's event, under `data`).
    public static func parseEvent(_ data: Data) throws -> CalendarMeeting {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["data"] as? [String: Any],
              let id = event["id"] as? String else {
            throw UntypeError.invalidConfiguration("The calendar event is not in the expected format ({\"data\": {\"id\": …}}).")
        }
        guard let start = date(event["start"]), let end = date(event["end"]) else {
            throw UntypeError.invalidConfiguration("The calendar event \(id) has no readable start or end.")
        }
        let organizer = (event["organizer"] as? [String: Any])?["emailAddress"] as? [String: Any]
        let attendees: [CalendarAttendee] = (event["attendees"] as? [[String: Any]] ?? []).compactMap { attendee in
            guard let email = attendee["emailAddress"] as? [String: Any],
                  let address = email["address"] as? String else {
                return nil
            }
            return CalendarAttendee(
                name: email["name"] as? String ?? address,
                address: address,
                required: (attendee["type"] as? String) == "required",
                response: ((attendee["status"] as? [String: Any])?["response"] as? String) ?? "none"
            )
        }
        return CalendarMeeting(
            id: id,
            subject: event["subject"] as? String ?? "",
            start: start,
            end: end,
            online: event["isOnlineMeeting"] as? Bool ?? false,
            organizerName: organizer?["name"] as? String ?? "",
            organizerAddress: organizer?["address"] as? String ?? "",
            attendees: attendees
        )
    }

    /// `--start` / `--end` for `calendar list`: exact UTC instants
    /// (`2026-11-11T22:00:00Z`), never bare dates, which the CLI takes as
    /// midnight UTC.
    public static func listRange(from start: Date, to end: Date) -> [String] {
        let format = ISO8601DateFormatter()
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.formatOptions = [.withInternetDateTime]
        return ["--start", format.string(from: start), "--end", format.string(from: end)]
    }

    /// The signed-in user's address from `status --json`.
    public static func signedInAddress(_ data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["data"] as? [String: Any],
              let email = status["email"] as? String, !email.isEmpty else {
            throw UntypeError.invalidConfiguration("The calendar CLI did not report the signed-in user's email.")
        }
        return email
    }

    /// Graph's `{ "dateTime": "2026-11-11T10:00:00.0000000", "timeZone": "Europe/Athens" }`.
    static func date(_ value: Any?) -> Date? {
        guard let value = value as? [String: Any],
              let text = value["dateTime"] as? String,
              let zoneName = value["timeZone"] as? String,
              let zone = TimeZone(identifier: zoneName) ?? (zoneName == "UTC" ? TimeZone(secondsFromGMT: 0) : nil) else {
            return nil
        }
        let whole = text.split(separator: ".").first.map(String.init) ?? text
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = zone
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return parser.date(from: whole)
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

    /// The user's answer to the invitation: `organizer` for their own
    /// meetings, else their entry among the attendees (`none` when missing).
    public static func myResponse(_ meeting: CalendarMeeting, me: String) -> String {
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

    /// A calendar name as people write it: "ΚΑΡΑΜΗΤΣΙΟΣ ΑΘΑΝΑΣΙΟΣ" becomes
    /// "Καραμητσιος Αθανασιος"; names already in mixed case stay as they are.
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
    /// "📊 ACCOUNTING RECONCILIATION | internal call" →
    /// "Accounting reconciliation | internal call".
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
    Format: "<topic> · <people>", for example "Accounting reconciliation · Athanasios Karamitsios, Georgios Fotopoulos" or "Power Platform team weekly · 17 people".
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

/// Reads today's meetings with the `nbg-m365` CLI (its own sign-in and
/// token cache; untype never sees the token).
public struct OutlookCalendarCLI: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// The `nbg-m365` binary installed with the Claude Code plugin, newest
    /// version first; nil when it is not installed.
    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let cache = home.appendingPathComponent(".claude/plugins/cache", isDirectory: true)
        let fm = FileManager.default
        var found: [URL] = []
        for marketplace in (try? fm.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? [] {
            let plugin = marketplace.appendingPathComponent("nbg-m365", isDirectory: true)
            for version in (try? fm.contentsOfDirectory(at: plugin, includingPropertiesForKeys: nil)) ?? [] {
                let binary = version.appendingPathComponent("bin/nbg-m365-mac-arm64")
                if fm.fileExists(atPath: binary.path) {
                    found.append(binary)
                }
            }
        }
        // The version folder decides (not the marketplace's name).
        func version(_ binary: URL) -> String {
            binary.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        }
        return found.max { version($0).compare(version($1), options: .numeric) == .orderedAscending }
    }

    /// The signed-in user's address.
    public func signedInAddress() async throws -> String {
        try MeetingCalendar.signedInAddress(try await run(["status", "--json"]))
    }

    /// The events of the day `day` (local), with their attendees.
    public func meetings(on day: Date, calendar: Calendar = .current) async throws -> [CalendarMeeting] {
        let start = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        // The CLI reads a bare date as midnight UTC, so the local day's
        // bounds are given as exact UTC instants.
        let ids = try MeetingCalendar.listedIDs(try await run(
            ["calendar", "list"] + MeetingCalendar.listRange(from: start, to: next) + ["--top", "100", "--json"]
        ))
        var meetings: [CalendarMeeting] = []
        for id in ids {
            meetings.append(try MeetingCalendar.parseEvent(try await run(["calendar", "read", id, "--json"])))
        }
        return meetings
    }

    private func run(_ arguments: [String]) async throws -> Data {
        let executable = executable
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: UntypeError.invalidConfiguration("The calendar CLI at \(executable.path) could not run: \(error.localizedDescription)"))
                    return
                }
                let timeout = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: timeout)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                timeout.cancel()
                switch process.terminationStatus {
                case 0:
                    continuation.resume(returning: data)
                case 2:
                    continuation.resume(throwing: UntypeError.invalidConfiguration("The calendar CLI is not signed in: run `\(executable.path) login` in a terminal."))
                default:
                    let detail = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: UntypeError.invalidConfiguration("The calendar CLI failed (\(arguments.prefix(2).joined(separator: " ")), exit \(process.terminationStatus)): \(detail.prefix(300))"))
                }
            }
        }
    }
}
