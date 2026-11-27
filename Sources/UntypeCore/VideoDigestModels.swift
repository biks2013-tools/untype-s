import Foundation

/// A video to digest (plan-080): what is known of it before its words.
public struct VideoInfo: Codable, Sendable, Equatable {
    public var id: String
    public var url: String
    public var title: String
    public var channel: String
    public var durationSeconds: Int
    public var description: String
    public var chapters: [VideoChapter]
    public var thumbnailURL: String
    /// The language of the video's own audio (not of a dubbed track), when
    /// YouTube says it.
    public var spokenLanguage: String?

    public init(id: String, url: String, title: String, channel: String, durationSeconds: Int, description: String, chapters: [VideoChapter], thumbnailURL: String, spokenLanguage: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.channel = channel
        self.durationSeconds = durationSeconds
        self.description = description
        self.chapters = chapters
        self.thumbnailURL = thumbnailURL
        self.spokenLanguage = spokenLanguage
    }

    /// Chapters written in the description as `0:00 Title` / `1:02:03 Title`
    /// lines (YouTube's own convention: the first one at 0:00).
    public static func chapters(in description: String) -> [VideoChapter] {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*[\[(]?((?:\d{1,2}:)?\d{1,2}:\d{2})[\])]?\s*[-–—:|]?\s*(.+?)\s*$"#) else {
            return []
        }
        let found = description.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> VideoChapter? in
            let text = String(line)
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let time = Range(match.range(at: 1), in: text),
                  let title = Range(match.range(at: 2), in: text),
                  let seconds = VideoDigestTime.seconds(String(text[time])) else {
                return nil
            }
            return VideoChapter(title: String(text[title]), start: seconds)
        }
        guard found.count >= 2, found[0].start == 0 else {
            return []
        }
        return found
    }

    /// Links of the description, without sponsor, affiliate and tracking ones.
    public var links: [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let blocked = ["utm_", "fpr=", "ref=", "affiliate", "cutt.ly", "bit.ly", "patreon.com", "buymeacoffee", "ko-fi.com",
                       "instagram.com", "tiktok.com", "facebook.com", "twitter.com/intent", "merch", "sponsor", "amzn.to", "geni.us"]
        var seen = Set<String>()
        return detector.matches(in: description, range: NSRange(description.startIndex..., in: description)).compactMap { match in
            guard let url = match.url?.absoluteString, url.hasPrefix("http") else {
                return nil
            }
            let lower = url.lowercased()
            guard !blocked.contains(where: { lower.contains($0) }), seen.insert(url).inserted else {
                return nil
            }
            return url
        }
    }
}

public struct VideoChapter: Codable, Sendable, Equatable {
    public var title: String
    public var start: Int
}

/// `h:mm:ss` / `m:ss` both ways.
public enum VideoDigestTime {
    public static func seconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":").map { Int($0) }
        guard parts.count >= 2, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else {
            return nil
        }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    public static func label(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// What the user asked for.
public struct VideoDigestRequest: Codable, Sendable, Equatable {
    /// The address the user gave.
    public var url: String
    /// The digest's language as a name the model understands ("Greek",
    /// "English"); nil: the language spoken in the video.
    public var language: String?
    /// Also a Word document.
    public var docx: Bool

    public init(url: String, language: String?, docx: Bool) {
        self.url = url
        self.language = language
        self.docx = docx
    }
}

/// Where the transcript came from, said in the digest (machine transcripts
/// get names and numbers wrong).
public enum VideoTranscriptSource: String, Codable, Sendable {
    case captions
    case automaticCaptions
    case soniox

    public var description: String {
        switch self {
        case .captions: return "the video's captions"
        case .automaticCaptions: return "YouTube's automatic captions"
        case .soniox: return "a Soniox transcription of the audio"
        }
    }
}

/// The model's reading of the video.
public struct VideoDigestAnalysis: Codable, Sendable, Equatable {
    public struct KeyPoint: Codable, Sendable, Equatable {
        public var lead: String
        public var text: String
        public var time: Int?
    }

    public struct Delivery: Codable, Sendable, Equatable {
        /// How it is said, in a paragraph.
        public var summary: String
        public var tone: String
        public var structure: String
        public var techniques: [String]
        public var evidence: String
    }

    public struct Section: Codable, Sendable, Equatable {
        public var title: String
        public var start: Int
        public var paragraphs: [String]
    }

    public struct Quote: Codable, Sendable, Equatable {
        /// As said, in the video's language.
        public var text: String
        public var time: Int
        public var speaker: String?
        /// In the digest's language, when that is another one.
        public var translation: String?
    }

    /// A moment worth a screenshot: a slide, a diagram, a demo, a claim to cite.
    public struct Moment: Codable, Sendable, Equatable {
        public var time: Int
        public var title: String
        public var why: String
        /// `screenshots/…`, once taken.
        public var screenshot: String?
    }

    public struct Resource: Codable, Sendable, Equatable {
        public var title: String
        public var url: String
    }

    public var title: String
    public var standfirst: String
    public var language: String
    public var speakers: [String]
    public var keyPoints: [KeyPoint]
    public var delivery: Delivery
    public var sections: [Section]
    public var quotes: [Quote]
    public var moments: [Moment]
    public var resources: [Resource]
}

public enum VideoDigestError: LocalizedError, Equatable {
    case notAVideo(String)
    case source(String)
    case captionsBlocked(Int)
    case noTranscript(String)
    case configuration(String)
    case transcription(String)
    case analysis(String)
    case output(String)

    public var errorDescription: String? {
        switch self {
        case .notAVideo(let text): return "This is not a YouTube address: \(text)"
        case .source(let message): return message
        case .captionsBlocked(let status): return "YouTube refused the captions (HTTP \(status)). It does that for some hours after many caption reads from one place; the audio can still be transcribed."
        case .noTranscript(let message): return message
        case .configuration(let message): return message
        case .transcription(let message): return "The transcription failed: \(message)"
        case .analysis(let message): return "The digest could not be written: \(message)"
        case .output(let message): return "The files could not be written: \(message)"
        }
    }
}
