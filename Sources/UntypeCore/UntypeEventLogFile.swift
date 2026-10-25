import Foundation

/// Appends the native UI's session and diagnostic events to
/// `~/.tool-agents/untype/events.log`, so a failure can be traced after the
/// app was quit or relaunched (the in-app Events list lives in memory only).
/// Only lines without dictated text are persisted: `session.*`,
/// `diagnostic.*`, `prompts.*` and `ready:`; transcripts and protocol events
/// never reach the file. The file rotates to `events.log.1` past 1 MB.
public final class UntypeEventLogFile: @unchecked Sendable {
    public static let persistedPrefixes = ["session.", "diagnostic.", "prompts.", "ready:"]
    public static let maxBytes = 1_000_000

    public let url: URL
    private let queue = DispatchQueue(label: "untype.events-log")
    private let fileManager = FileManager.default
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(url: URL) {
        self.url = url
    }

    public static func userFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".tool-agents")
            .appendingPathComponent("untype")
            .appendingPathComponent("events.log")
    }

    public static func shouldPersist(_ line: String) -> Bool {
        persistedPrefixes.contains { line.hasPrefix($0) }
    }

    public func append(_ line: String, at date: Date = Date()) {
        guard Self.shouldPersist(line) else {
            return
        }
        let entry = "\(formatter.string(from: date)) \(line.replacingOccurrences(of: "\n", with: " "))\n"
        queue.async { [self] in
            try? write(entry)
        }
    }

    /// Waits for pending writes (tests, quit).
    public func flush() {
        queue.sync {}
    }

    private func write(_ entry: String) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
           size.intValue + entry.utf8.count > Self.maxBytes {
            let rotated = URL(fileURLWithPath: url.path + ".1")
            try? fileManager.removeItem(at: rotated)
            try fileManager.moveItem(at: url, to: rotated)
        }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(entry.utf8))
    }
}
