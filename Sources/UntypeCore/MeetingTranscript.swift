import Foundation

/// Which side of a call a meeting segment comes from: the user's own
/// microphone, or the call's sound (system audio, every other app).
public enum MeetingSide: String, Codable, Sendable, Equatable {
    case you
    case call
}

/// One utterance of a meeting transcript.
public struct MeetingSegment: Codable, Sendable, Equatable {
    /// Milliseconds since the meeting started.
    public var startMs: Int
    public var endMs: Int
    public var side: MeetingSide
    /// Soniox diarization label of the call side ("1", "2", …); nil for the
    /// microphone.
    public var speaker: String?
    /// ISO 639-1 language Soniox identified ("el", "en", …); nil when unknown.
    public var language: String?
    /// The text as spoken.
    public var text: String
    /// The English text (filled after the meeting when the transcript
    /// language is English).
    public var english: String?

    public init(
        startMs: Int,
        endMs: Int,
        side: MeetingSide,
        speaker: String?,
        language: String?,
        text: String,
        english: String? = nil
    ) {
        self.startMs = startMs
        self.endMs = endMs
        self.side = side
        self.speaker = speaker
        self.language = language
        self.text = text
        self.english = english
    }
}

/// One Soniox token as the meeting streams use it.
public struct MeetingToken: Sendable, Equatable {
    public var text: String
    public var isFinal: Bool
    public var speaker: String?
    public var language: String?
    public var startMs: Int?
    public var endMs: Int?

    public init(text: String, isFinal: Bool, speaker: String? = nil, language: String? = nil, startMs: Int? = nil, endMs: Int? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.speaker = speaker
        self.language = language
        self.startMs = startMs
        self.endMs = endMs
    }

    /// Soniox's end-of-utterance (`<end>`) and finalize (`<fin>`) markers.
    public var isMarker: Bool {
        text == "<end>" || text == "<fin>"
    }

    /// Parses the `tokens` array of a Soniox result frame.
    public static func parse(_ tokens: [[String: Any]]) -> [MeetingToken] {
        tokens.compactMap { token in
            guard let text = token["text"] as? String else {
                return nil
            }
            return MeetingToken(
                text: text,
                isFinal: token["is_final"] as? Bool ?? false,
                speaker: (token["speaker"] as? String) ?? (token["speaker"] as? Int).map(String.init),
                language: token["language"] as? String,
                startMs: (token["start_ms"] as? NSNumber)?.intValue,
                endMs: (token["end_ms"] as? NSNumber)?.intValue
            )
        }
    }
}

/// The words heard so far on one Soniox stream, for showing them while the
/// user speaks: final tokens accumulate, the non-final ones are replaced by
/// every result frame.
public struct MeetingLiveText: Sendable, Equatable {
    private var finalText = ""
    public private(set) var text = ""

    public init() {}

    /// Adds the tokens of one result frame; returns the text heard so far.
    @discardableResult
    public mutating func add(_ tokens: [MeetingToken]) -> String {
        var pending = ""
        for token in tokens where !token.isMarker {
            if token.isFinal {
                finalText += token.text
            } else {
                pending += token.text
            }
        }
        text = (finalText + pending).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text
    }
}

/// Builds segments from the final tokens of one Soniox stream: a segment
/// ends at an end-of-utterance marker or when the speaker changes. Non-final
/// tokens are ignored (only what Soniox has settled is written).
public struct MeetingTokenAggregator: Sendable {
    public let side: MeetingSide
    /// Milliseconds between the meeting start and this stream's start, added
    /// to Soniox's stream-relative token times.
    public let offsetMs: Int
    private var pending: [MeetingToken] = []

    public init(side: MeetingSide, offsetMs: Int = 0) {
        self.side = side
        self.offsetMs = offsetMs
    }

    /// Adds the tokens of one result frame; returns the segments completed.
    public mutating func add(_ tokens: [MeetingToken]) -> [MeetingSegment] {
        var done: [MeetingSegment] = []
        for token in tokens where token.isFinal {
            if token.isMarker {
                if let segment = flush() {
                    done.append(segment)
                }
                continue
            }
            if side == .call, let last = pending.last, let speaker = token.speaker, let lastSpeaker = last.speaker, speaker != lastSpeaker {
                if let segment = flush() {
                    done.append(segment)
                }
            }
            pending.append(token)
        }
        return done
    }

    /// Ends the current segment (stream closed).
    public mutating func flush() -> MeetingSegment? {
        defer { pending.removeAll() }
        let text = pending.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        let start = pending.compactMap(\.startMs).min() ?? 0
        let end = pending.compactMap(\.endMs).max() ?? start
        return MeetingSegment(
            startMs: start + offsetMs,
            endMs: end + offsetMs,
            side: side,
            speaker: side == .call ? Self.majority(pending.compactMap(\.speaker)) : nil,
            language: Self.majority(pending.compactMap(\.language)),
            text: text
        )
    }

    private static func majority(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }
}

/// The transcript language of a finished meeting.
public enum MeetingTranscriptLanguage: String, Codable, Sendable, CaseIterable {
    /// Translated to English; lines already in English stay as spoken.
    case english = "en"
    /// As spoken (Greek and English mixed).
    case original

    public var title: String {
        switch self {
        case .english: return "English"
        case .original: return "As spoken"
        }
    }
}

/// Text formats of a meeting transcript.
public enum MeetingTranscriptFormat {
    /// "You" for the microphone, "Speaker N" for the people on the call.
    public static func speakerLabel(_ segment: MeetingSegment) -> String {
        switch segment.side {
        case .you:
            return "You"
        case .call:
            guard let speaker = segment.speaker, !speaker.isEmpty else {
                return "Call"
            }
            let number = speaker.hasPrefix("spk:") ? String(speaker.dropFirst(4)) : speaker
            return "Speaker \(number)"
        }
    }

    /// `HH:MM:SS` from the meeting start.
    public static func timestamp(_ ms: Int) -> String {
        let seconds = max(0, ms / 1000)
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    /// `[00:12:15] Speaker 3 [el]: text` (the language tag only when known).
    public static func originalLine(_ segment: MeetingSegment) -> String {
        let language = segment.language.map { " [\($0)]" } ?? ""
        return "[\(timestamp(segment.startMs))] \(speakerLabel(segment))\(language): \(segment.text)"
    }

    /// `[00:12:15] Speaker 3: text`, with the English text when there is one.
    public static func englishLine(_ segment: MeetingSegment) -> String {
        "[\(timestamp(segment.startMs))] \(speakerLabel(segment)): \(segment.english ?? segment.text)"
    }

    /// Segments of both streams in time order.
    public static func ordered(_ segments: [MeetingSegment]) -> [MeetingSegment] {
        segments.enumerated()
            .sorted { $0.element.startMs == $1.element.startMs ? $0.offset < $1.offset : $0.element.startMs < $1.element.startMs }
            .map(\.element)
    }

    /// The meeting folder name: `2026-11-11 14.30`.
    public static func folderName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d.%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }
}

/// Stops a meeting after a stretch without speech on either side.
public struct MeetingSilenceMonitor: Sendable {
    public let limit: TimeInterval
    public private(set) var lastSpeech: TimeInterval

    /// `limit` seconds (0: never stops); `start` is the meeting start time.
    public init(limit: TimeInterval, start: TimeInterval) {
        self.limit = limit
        self.lastSpeech = start
    }

    public mutating func speechHeard(at time: TimeInterval) {
        lastSpeech = max(lastSpeech, time)
    }

    public func shouldStop(at time: TimeInterval) -> Bool {
        limit > 0 && time - lastSpeech >= limit
    }
}

/// Splits transcript lines into chunks for the English pass, so each LLM
/// call stays well under the output-token cap.
public enum MeetingTranslationChunks {
    public static func chunks(_ lines: [String], maxCharacters: Int = 2_500, maxLines: Int = 40) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var size = 0
        for line in lines {
            if !current.isEmpty, current.count >= maxLines || size + line.count > maxCharacters {
                result.append(current)
                current = []
                size = 0
            }
            current.append(line)
            size += line.count
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// Numbered lines sent to the model: `1|text`.
    public static func request(_ texts: [String]) -> String {
        texts.enumerated().map { "\($0.offset + 1)|\($0.element.replacingOccurrences(of: "\n", with: " "))" }.joined(separator: "\n")
    }

    /// The model's numbered answer back to one text per input line; nil when
    /// a line is missing (the chunk then keeps its original text).
    public static func parse(_ answer: String, count: Int) -> [String]? {
        var texts = [String?](repeating: nil, count: count)
        for line in answer.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let number = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  (1...count).contains(number) else {
                continue
            }
            texts[number - 1] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        let filled = texts.compactMap { $0 }
        return filled.count == count ? filled : nil
    }

    public static let systemPrompt = """
    You translate meeting transcript lines into English.
    Each input line is "N|text". Answer with exactly one line per input line, in the same order, as "N|English text".
    Translate Greek (or any other language) into natural English. Keep lines that are already English unchanged.
    Keep names, numbers and technical terms. Never merge, split, drop, explain or summarize lines. Output nothing else.
    """
}

/// Naming a saved meeting: the folder (and its main transcript) becomes
/// `<date time> – <title>`, the title made from what the user said.
public enum MeetingNaming {
    public static let separator = " – "

    /// The leading `yyyy-MM-dd HH.mm` of a meeting folder name (nil when the
    /// name does not start with one).
    public static func datePrefix(of folderName: String) -> String? {
        guard let range = folderName.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}\.\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return String(folderName[range])
    }

    /// The date of a folder name as people say it: "Today 22:38",
    /// "Yesterday 09:05", "11 Nov 22:38" (nil when the name has no date).
    public static func friendlyDate(of folderName: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let prefix = datePrefix(of: folderName) else {
            return nil
        }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd HH.mm"
        guard let date = parser.date(from: prefix) else {
            return nil
        }
        let printer = DateFormatter()
        printer.locale = Locale(identifier: "en_US_POSIX")
        printer.calendar = calendar
        printer.timeZone = calendar.timeZone
        printer.dateFormat = "HH:mm"
        let time = printer.string(from: date)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
        if days == 0 {
            return "Today \(time)"
        }
        if days == 1 {
            return "Yesterday \(time)"
        }
        printer.dateFormat = "d MMM HH:mm"
        return printer.string(from: date)
    }

    /// A title safe as a file name: no path or reserved characters, no
    /// quotes or trailing period, single spaces, at most `maxLength`.
    public static func sanitize(_ title: String, maxLength: Int = 100) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\u{201C}\u{201D}\u{2018}\u{2019}`").union(.newlines).union(.controlCharacters)
        var cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        cleaned = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " .'-–—"))
        if cleaned.count > maxLength {
            cleaned = String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }

    /// `<date time> – <title>`; the date comes from the current name (the
    /// whole current name when it has no date).
    public static func folderName(current: String, title: String) -> String {
        let base = datePrefix(of: current) ?? current
        let clean = sanitize(title)
        return clean.isEmpty ? base : base + separator + clean
    }

    /// The meeting's main transcript: `<folder name>.txt` once named,
    /// `transcript.txt` before.
    public static func mainTranscript(in folder: URL) -> URL {
        let named = folder.appendingPathComponent(folder.lastPathComponent + ".txt")
        if FileManager.default.fileExists(atPath: named.path) {
            return named
        }
        return folder.appendingPathComponent("transcript.txt")
    }

    /// Renames the folder to `<date time> – <title>` (adding " (2)", … when
    /// taken) and its main transcript to `<new folder name>.txt`.
    public static func rename(folder: URL, title: String) throws -> URL {
        let wanted = folderName(current: folder.lastPathComponent, title: title)
        let parent = folder.deletingLastPathComponent()
        var target = parent.appendingPathComponent(wanted, isDirectory: true)
        var counter = 2
        while target.standardizedFileURL != folder.standardizedFileURL, FileManager.default.fileExists(atPath: target.path) {
            target = parent.appendingPathComponent("\(wanted) (\(counter))", isDirectory: true)
            counter += 1
        }
        let oldMain = mainTranscript(in: folder).lastPathComponent
        if target.standardizedFileURL != folder.standardizedFileURL {
            try FileManager.default.moveItem(at: folder, to: target)
        }
        let from = target.appendingPathComponent(oldMain)
        let to = target.appendingPathComponent(target.lastPathComponent + ".txt")
        if from.path != to.path, FileManager.default.fileExists(atPath: from.path) {
            try FileManager.default.moveItem(at: from, to: to)
        }
        return target
    }

    public static let titlePrompt = """
    You turn the user's spoken description of a meeting (Greek or English) into the meeting's title, written in English.
    Format: "<topic> · <people>", for example "HR training skills · Mina" or "Production procedure · George, Kyriaki, Nikos Repas".
    Topic: 2 to 8 words in sentence case, keeping the user's own words and the details they gave (subject, decisions, points); drop filler words and false starts, fix grammar, translate Greek into English.
    People: the names the user mentioned, as they said them, separated by commas, without "with" or "and". When no person or team is mentioned, write only the topic.
    Every title names a meeting, so never use words that only say it was one (meeting, discussion, call, chat, talk, conversation, sync, catch-up, get-together) or linking words like "about", "on", "regarding".
    No date, no quotes, no trailing period, no slashes or colons. Output only the title.
    """
}
