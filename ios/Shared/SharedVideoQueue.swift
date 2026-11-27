import Foundation
import UntypeCore

/// What the app and its share extension share (plan-080 step 4), through
/// the App Group: the videos folder the user picked (a bookmark) and the
/// requests the extension queued for the app — to make here, or to send to
/// the Mac when the extension could not reach the folder.
enum SharedVideoQueue {
    static let group = "group.com.biks2013.untype"
    static let bookmarkKey = "videos.libraryBookmark"

    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    /// A request the extension left for the app.
    struct Pending: Codable, Equatable {
        enum Place: String, Codable { case phone, mac }
        var id = UUID().uuidString
        var url: String
        var language: String?
        var docx: Bool
        var place: Place
        var queuedAt = Date()
    }

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("PendingVideos", isDirectory: true)
    }

    static func add(_ pending: Pending) throws {
        guard let folder else {
            throw QueueError("The app group is not available.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(pending).write(to: folder.appendingPathComponent("\(pending.id).json"), options: .atomic)
    }

    /// The queued requests, oldest first.
    static func all() -> [Pending] {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { try? decoder.decode(Pending.self, from: Data(contentsOf: folder.appendingPathComponent($0))) }
            .sorted { $0.queuedAt < $1.queuedAt }
    }

    static func remove(_ pending: Pending) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(pending.id).json"))
    }

    /// The videos folder the user picked in the app, with access.
    static func library() -> URL? {
        guard let data = defaults?.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }

    /// Writes a request for the Mac into the library's `Requests` folder.
    static func sendToMac(url: String, language: String?, docx: Bool) throws {
        guard let library = library() else {
            throw QueueError("Choose the videos folder in untype first (Videos tab).")
        }
        let access = library.startAccessingSecurityScopedResource()
        defer { if access { library.stopAccessingSecurityScopedResource() } }
        try VideoDigestInbox.send(VideoDigestInboxRequest(url: url, language: language, docx: docx, from: "iphone"), library: library)
    }
}

struct QueueError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
