import Foundation

/// One editable prompt file in `~/.tool-agents/untype/prompts/`.
public struct PromptFileDescriptor: Sendable, Equatable, Identifiable {
    public enum Group: String, Sendable, CaseIterable {
        case refinement = "Refinement"
        case translation = "Translation"
        case composite = "Refine + translate (one call)"
        case ask = "Ask (request to the model)"
        case transcription = "Transcription context"
    }

    public let name: String
    public let title: String
    public let group: Group
    public let summary: String
    public let defaultContent: String
    public let required: Bool
    /// Placeholders the file must contain; the runtime substitutes them.
    public let placeholders: [String]
    /// Upper bound on characters (`maxCharacters`) or on non-empty lines
    /// (`maxLines`, each at most `maxLineCharacters`), set by the STT provider.
    public let maxCharacters: Int?
    public let maxLines: Int?
    public let maxLineCharacters: Int?

    public var id: String { name }
}

/// Reads, validates and writes the prompt files. Validation mirrors
/// `ConfigResolver.resolvePromptConfig`, so a file saved here never makes a
/// session fail to start.
public struct PromptFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func userDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".tool-agents")
            .appendingPathComponent("untype")
            .appendingPathComponent("prompts")
    }

    public static let descriptors: [PromptFileDescriptor] = [
        PromptFileDescriptor(
            name: "001-refinement-system.txt",
            title: "Refinement — system prompt",
            group: .refinement,
            summary: "Cleans the transcript when only Refine is on.",
            defaultContent: UntypePromptDefaults.refinementSystemPrompt,
            required: true,
            placeholders: [],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "002-translation-system.txt",
            title: "Translation — system prompt",
            group: .translation,
            summary: "Translates the transcript when only Translate is on.",
            defaultContent: UntypePromptDefaults.translationSystemPrompt,
            required: true,
            placeholders: [],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "003-translation-user-template.txt",
            title: "Translation — user message template",
            group: .translation,
            summary: "The message sent with each translation request.",
            defaultContent: UntypePromptDefaults.translationUserPromptTemplate,
            required: true,
            placeholders: ["{target_language}", "{text}"],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "007-composite-refine-translate-system.txt",
            title: "Refine + translate — system prompt",
            group: .composite,
            summary: "Used when Refine and Translate are both on; must answer with the JSON shape it describes.",
            defaultContent: UntypePromptDefaults.compositeSystemPrompt,
            required: true,
            placeholders: [],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "008-composite-refinement-template.txt",
            title: "Refine + translate — refinement instruction",
            group: .composite,
            summary: "The refinement half of the combined request.",
            defaultContent: UntypePromptDefaults.compositeRefinementPromptTemplate,
            required: true,
            placeholders: ["{text}"],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "009-composite-translation-template.txt",
            title: "Refine + translate — translation instruction",
            group: .composite,
            summary: "The translation half of the combined request.",
            defaultContent: UntypePromptDefaults.compositeTranslationPromptTemplate,
            required: true,
            placeholders: ["{target_language}"],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "010-ask-system.txt",
            title: "Ask — system prompt",
            group: .ask,
            summary: "Used when Ask is on: the dictation is a request, and the model's answer replaces it.",
            defaultContent: UntypePromptDefaults.askSystemPrompt,
            required: true,
            placeholders: [],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "011-ask-user-template.txt",
            title: "Ask — request template",
            group: .ask,
            summary: "The message sent with each request when Translate is off.",
            defaultContent: UntypePromptDefaults.askUserPromptTemplate,
            required: true,
            placeholders: ["{text}"],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "012-ask-translated-user-template.txt",
            title: "Ask — request template (answer in the target language)",
            group: .ask,
            summary: "The message sent with each request when Translate is also on; the answer is written in the translation target language.",
            defaultContent: UntypePromptDefaults.askTranslatedUserPromptTemplate,
            required: true,
            placeholders: ["{target_language}", "{text}"],
            maxCharacters: nil, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "004-soniox-transcription-context.txt",
            title: "Soniox — transcription context",
            group: .transcription,
            summary: "Optional domain context sent to Soniox (names, terms).",
            defaultContent: "",
            required: false,
            placeholders: [],
            maxCharacters: 10_000, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "005-elevenlabs-previous-text.txt",
            title: "ElevenLabs — previous text",
            group: .transcription,
            summary: "Optional preceding text sent to ElevenLabs.",
            defaultContent: "",
            required: false,
            placeholders: [],
            maxCharacters: 50, maxLines: nil, maxLineCharacters: nil
        ),
        PromptFileDescriptor(
            name: "006-elevenlabs-keyterms.txt",
            title: "ElevenLabs — keyterms",
            group: .transcription,
            summary: "Optional keyterms for ElevenLabs, one per line.",
            defaultContent: "",
            required: false,
            placeholders: [],
            maxCharacters: nil, maxLines: 50, maxLineCharacters: 20
        )
    ]

    public static func descriptor(named name: String) -> PromptFileDescriptor? {
        descriptors.first { $0.name == name }
    }

    public func url(for descriptor: PromptFileDescriptor) -> URL {
        directory.appendingPathComponent(descriptor.name)
    }

    /// Writes the default of every missing file, as session start does.
    public func provisionMissing() throws {
        try ensureDirectory()
        for descriptor in Self.descriptors where !FileManager.default.fileExists(atPath: url(for: descriptor).path) {
            try writeFile(descriptor.defaultContent, to: url(for: descriptor))
        }
    }

    public func read(_ descriptor: PromptFileDescriptor) throws -> String {
        let fileURL = url(for: descriptor)
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw UntypeError.invalidConfiguration("Unable to read prompt file \(fileURL.path): \(error.localizedDescription)")
        }
    }

    /// Validates and writes the content (atomic, `0600`).
    public func write(_ content: String, for descriptor: PromptFileDescriptor) throws {
        if let problem = Self.validationError(content, for: descriptor) {
            throw UntypeError.invalidConfiguration(problem)
        }
        try ensureDirectory()
        try writeFile(content, to: url(for: descriptor))
    }

    /// `nil` when the content is valid for the file, else the reason it is not.
    public static func validationError(_ content: String, for descriptor: PromptFileDescriptor) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if descriptor.required && trimmed.isEmpty {
            return "\(descriptor.name) must not be empty."
        }
        let missing = descriptor.placeholders.filter { !content.contains($0) }
        if !missing.isEmpty {
            return "\(descriptor.name) must contain \(missing.joined(separator: " and "))."
        }
        // Counted untrimmed, as ConfigResolver does.
        if let maxCharacters = descriptor.maxCharacters, !trimmed.isEmpty, content.count > maxCharacters {
            return "\(descriptor.name) must be \(maxCharacters) characters or fewer (now \(content.count))."
        }
        if descriptor.maxLines != nil || descriptor.maxLineCharacters != nil {
            let lines = content
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let maxLines = descriptor.maxLines, lines.count > maxLines {
                return "\(descriptor.name) must contain \(maxLines) or fewer lines (now \(lines.count))."
            }
            if let maxLineCharacters = descriptor.maxLineCharacters,
               let long = lines.first(where: { $0.count > maxLineCharacters }) {
                return "'\(long)' in \(descriptor.name) must be \(maxLineCharacters) characters or fewer."
            }
        }
        return nil
    }

    /// Modification date and size of every prompt file; a change means a file
    /// was edited, added or removed.
    public func fingerprint() -> [String: String] {
        var result: [String: String] = [:]
        for descriptor in Self.descriptors {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: descriptor).path)
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? -1
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
            result[descriptor.name] = "\(modified)/\(size)"
        }
        return result
    }

    private func ensureDirectory() throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private func writeFile(_ content: String, to url: URL) throws {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw UntypeError.invalidConfiguration("Unable to write prompt file \(url.path): \(error.localizedDescription)")
        }
    }
}

/// Polls the prompt files once a second and reports the names of the files
/// that changed (saved from the Settings window or from any editor).
@MainActor
public final class PromptFileWatcher {
    private let store: PromptFileStore
    private let onChange: ([String]) -> Void
    private var last: [String: String]
    private var timer: Timer?

    public init(store: PromptFileStore, onChange: @escaping ([String]) -> Void) {
        self.store = store
        self.onChange = onChange
        last = store.fingerprint()
    }

    public func start(interval: TimeInterval = 1) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Compares against the previous fingerprint; exposed for tests.
    public func check() {
        let next = store.fingerprint()
        let changed = next.keys.filter { next[$0] != last[$0] }.sorted()
        last = next
        if !changed.isEmpty {
            onChange(changed)
        }
    }
}
