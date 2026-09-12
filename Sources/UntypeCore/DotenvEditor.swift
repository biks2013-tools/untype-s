import Foundation

/// Read-modify-write access to the user-level `~/.tool-agents/untype/.env`.
/// Edits are line-based and preserve everything else in the file: comments,
/// ordering, blank lines, and variables that are not being changed. A
/// missing file is created from `UntypeEnvTemplate.content`, so an activated
/// key replaces its own commented `# KEY=` line and keeps the description
/// above it.
public enum DotenvEditor {
    /// The variables the native UI credentials editor manages.
    public static let editableKeys: [String] = [
        "SONIOX_API_KEY",
        "ELEVENLABS_API_KEY",
        "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_ENDPOINT",
        "AZURE_OPENAI_DEPLOYMENT",
        "AZURE_OPENAI_API_VERSION",
        "GOOGLE_API_KEY"
    ]

    public static func userEnvURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".tool-agents")
            .appendingPathComponent("untype")
            .appendingPathComponent(UntypeEnvTemplate.fileName)
    }

    /// Parsed active values of the file (empty when the file does not exist).
    public static func read(_ url: URL) throws -> [String: String] {
        try Dotenv.readIfExists(url)
    }

    /// Sets every key in `values` in the file at `url`. An empty (or
    /// whitespace-only) value unsets the key by turning its line back into
    /// `# KEY=`. Creates the parent folders (0700) and the file (0600) when
    /// missing, starting from `template`.
    public static func upsert(
        _ values: [String: String],
        into url: URL,
        template: String = UntypeEnvTemplate.content
    ) throws {
        let fileManager = FileManager.default
        let existing: String?
        if fileManager.fileExists(atPath: url.path) {
            do {
                existing = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw UntypeError.invalidConfiguration(
                    "Unable to read \(displayPath(url)): \(error.localizedDescription)"
                )
            }
        } else {
            existing = nil
        }

        let updated = apply(values, to: existing ?? template)

        do {
            let directory = url.deletingLastPathComponent()
            var ancestors: [URL] = []
            var cursor = directory
            while !fileManager.fileExists(atPath: cursor.path), cursor.path != "/" {
                ancestors.insert(cursor, at: 0)
                cursor = cursor.deletingLastPathComponent()
            }
            for folder in ancestors {
                try fileManager.createDirectory(
                    at: folder,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            try updated.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw UntypeError.invalidConfiguration(
                "Unable to write \(displayPath(url)): \(error.localizedDescription)"
            )
        }
    }

    /// Pure text transformation behind `upsert`, exposed for tests.
    static func apply(_ values: [String: String], to contents: String) -> String {
        let hadTrailingNewline = contents.hasSuffix("\n")
        var lines = contents.components(separatedBy: "\n")
        if hadTrailingNewline {
            lines.removeLast()
        }

        for key in values.keys.sorted() {
            let value = values[key]!.trimmingCharacters(in: .whitespacesAndNewlines)
            let activeIndexes = lines.indices.filter { isActiveAssignment(lines[$0], key: key) }
            let commentedIndex = lines.firstIndex { isCommentedAssignment($0, key: key) }

            if value.isEmpty {
                // Unset: turn the first active line into a commented placeholder,
                // drop any duplicates, leave the file untouched otherwise.
                guard let first = activeIndexes.first else { continue }
                lines[first] = "# \(key)="
                for index in activeIndexes.dropFirst().reversed() {
                    lines.remove(at: index)
                }
                continue
            }

            let assignment = format(key: key, value: value)
            if let first = activeIndexes.first {
                lines[first] = assignment
                // Remove later duplicates so a stale last-wins entry cannot shadow the new value.
                for index in activeIndexes.dropFirst().reversed() {
                    lines.remove(at: index)
                }
            } else if let commentedIndex {
                lines[commentedIndex] = assignment
            } else {
                if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append("")
                }
                lines.append(assignment)
            }
        }

        var result = lines.joined(separator: "\n")
        if hadTrailingNewline || contents.isEmpty {
            result += "\n"
        }
        return result
    }

    static func format(key: String, value: String) -> String {
        let needsQuotes = value.contains("#")
            || value.first?.isWhitespace == true
            || value.last?.isWhitespace == true
            || value.hasPrefix("\"")
            || value.hasPrefix("'")
        guard needsQuotes else {
            return "\(key)=\(value)"
        }
        if !value.contains("\"") {
            return "\(key)=\"\(value)\""
        }
        return "\(key)='\(value)'"
    }

    private static func isActiveAssignment(_ line: String, key: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { return false }
        if text.hasPrefix("export ") {
            text.removeFirst("export ".count)
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return assignmentKey(of: text) == key
    }

    private static func isCommentedAssignment(_ line: String, key: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return false }
        text.removeFirst()
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("export ") {
            text.removeFirst("export ".count)
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return assignmentKey(of: text) == key
    }

    private static func assignmentKey(of text: String) -> String? {
        guard let equals = text.firstIndex(of: "="), equals != text.startIndex else { return nil }
        return String(text[..<equals]).trimmingCharacters(in: .whitespaces)
    }

    private static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }
}
