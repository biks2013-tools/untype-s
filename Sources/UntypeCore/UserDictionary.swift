import Foundation

/// A word of the user's dictionary (plan-073): a name, an abbreviation or a
/// term, written the way it must be written, and the ways speech
/// recognition has been heard to write it instead.
public struct DictionaryEntry: Codable, Equatable, Sendable, Identifiable {
    public var term: String
    public var heardAs: [String]

    public var id: String { term }

    public init(term: String, heardAs: [String] = []) {
        self.term = term
        self.heardAs = heardAs
    }

    private enum CodingKeys: String, CodingKey {
        case term
        case heardAs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decode(String.self, forKey: .term)
        heardAs = try container.decodeIfPresent([String].self, forKey: .heardAs) ?? []
    }
}

/// The user's dictionary: the words speech recognition is told to expect,
/// and what is written in place of what it wrote wrongly.
public struct UserDictionary: Codable, Equatable, Sendable {
    public private(set) var entries: [DictionaryEntry]

    public static let empty = UserDictionary()
    /// Soniox takes about 10 000 characters of context in all.
    public static let maxEntries = 300
    public static let maxTermLength = 60

    public init(entries: [DictionaryEntry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// The words as they must be written, for the speech provider.
    public var terms: [String] {
        entries.map(\.term)
    }

    /// A word as typed by the user, ready to be stored: without surrounding
    /// spaces, inner runs of spaces as one.
    public static func cleaned(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// What was heard, ready to be stored: as `cleaned`, without the
    /// punctuation and quotes speech recognition puts around a lone word.
    public static func cleanedHeard(_ raw: String) -> String {
        cleaned(raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?…·\"'“”«»()[]").union(.whitespacesAndNewlines)))
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive]) == .orderedSame
    }

    /// Adds a word. Throws when it is empty, too long, already there, or
    /// the dictionary is full.
    public mutating func add(_ raw: String) throws {
        let term = Self.cleaned(raw)
        guard !term.isEmpty else {
            throw UntypeError.invalidConfiguration("Type the word first.")
        }
        guard term.count <= Self.maxTermLength else {
            throw UntypeError.invalidConfiguration("A dictionary word can have up to \(Self.maxTermLength) characters.")
        }
        guard !entries.contains(where: { Self.same($0.term, term) }) else {
            throw UntypeError.invalidConfiguration("“\(term)” is already in the dictionary.")
        }
        guard entries.count < Self.maxEntries else {
            throw UntypeError.invalidConfiguration("The dictionary is full (\(Self.maxEntries) words).")
        }
        entries.append(DictionaryEntry(term: term))
    }

    public mutating func remove(_ term: String) {
        entries.removeAll { $0.term == term }
    }

    public enum HeardResult: Equatable, Sendable {
        /// Speech recognition wrote the word itself (whatever the capitals).
        case correct
        /// A new way it is heard; it is stored.
        case added(String)
        /// Already stored for this word.
        case known(String)
        /// Stored for another word, which it keeps.
        case takenBy(String)
    }

    /// Records what speech recognition wrote when the user said `term`.
    public mutating func noteHeard(_ raw: String, for term: String) -> HeardResult {
        let heard = Self.cleanedHeard(raw)
        guard let index = entries.firstIndex(where: { $0.term == term }) else {
            return .correct
        }
        if heard.isEmpty || Self.same(heard, term) {
            return .correct
        }
        if entries[index].heardAs.contains(where: { Self.same($0, heard) }) {
            return .known(heard)
        }
        if let other = entries.first(where: { Self.same($0.term, heard) || $0.heardAs.contains(where: { Self.same($0, heard) }) }) {
            return .takenBy(other.term)
        }
        entries[index].heardAs.append(heard)
        return .added(heard)
    }

    public mutating func removeHeard(_ heard: String, for term: String) {
        guard let index = entries.firstIndex(where: { $0.term == term }) else {
            return
        }
        entries[index].heardAs.removeAll { $0 == heard }
    }
}

/// `~/.tool-agents/untype/dictionary.json`, readable by the user only.
public enum UserDictionaryStore {
    public static func path(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".tool-agents").appendingPathComponent("untype").appendingPathComponent("dictionary.json")
    }

    /// Empty when there is no file yet. Throws on a file that is not a
    /// dictionary, so it is never overwritten by mistake.
    public static func load(from url: URL = path()) throws -> UserDictionary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(UserDictionary.self, from: Data(contentsOf: url))
        } catch {
            throw UntypeError.invalidConfiguration("The dictionary file (\(url.path)) cannot be read: \(error.localizedDescription). Correct or delete it.")
        }
    }

    public static func save(_ dictionary: UserDictionary, to url: URL = path()) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(dictionary)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Rewrites recognised text with the dictionary: what a word was heard as
/// becomes the word, and the word itself gets its own capitals. Whole words
/// only, whatever the capitals of the recognised text.
public struct DictionaryCorrector: @unchecked Sendable {
    private let regex: NSRegularExpression?
    private let replacements: [String: String]

    public init(_ dictionary: UserDictionary) {
        var replacements: [String: String] = [:]
        for entry in dictionary.entries {
            // A word comes before what another word was heard as.
            replacements[Self.key(entry.term)] = entry.term
        }
        for entry in dictionary.entries {
            for heard in entry.heardAs where replacements[Self.key(heard)] == nil {
                replacements[Self.key(heard)] = entry.term
            }
        }
        self.replacements = replacements
        let alternatives = replacements.keys
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
            .map { key in
                key.split(separator: " ")
                    .map { NSRegularExpression.escapedPattern(for: String($0)) }
                    .joined(separator: "\\s+")
            }
        regex = alternatives.isEmpty ? nil : try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])(?:\(alternatives.joined(separator: "|")))(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive]
        )
    }

    public var isEmpty: Bool {
        regex == nil
    }

    private static func key(_ text: String) -> String {
        UserDictionary.cleaned(text).lowercased()
    }

    public func apply(_ text: String) -> String {
        guard let regex else {
            return text
        }
        let source = text as NSString
        var result = ""
        var position = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let found = source.substring(with: match.range)
            guard let replacement = replacements[Self.key(found)] else {
                continue
            }
            result += source.substring(with: NSRange(location: position, length: match.range.location - position))
            result += replacement
            position = match.range.location + match.range.length
        }
        return result + source.substring(from: position)
    }
}
