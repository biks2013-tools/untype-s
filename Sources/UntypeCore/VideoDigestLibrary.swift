import Foundation

// Shared by the Mac and the iPhone (plan-080): the library's request inbox
// in iCloud and the list of digests.

/// A request for a digest left in the library's `Requests` folder (iCloud)
/// by the iPhone, for the Mac to do (plan-080).
public struct VideoDigestInboxRequest: Codable, Sendable, Equatable {
    public var id: String
    public var url: String
    /// nil: the language spoken in the video.
    public var language: String?
    public var docx: Bool
    public var requestedAt: Date
    /// "iphone", for the log.
    public var from: String
    /// Set by the Mac in `Requests/done/` and `Requests/failed/`.
    public var folder: String?
    public var error: String?

    public init(id: String = UUID().uuidString, url: String, language: String?, docx: Bool, requestedAt: Date = Date(), from: String) {
        self.id = id
        self.url = url
        self.language = language
        self.docx = docx
        self.requestedAt = requestedAt
        self.from = from
    }
}

/// The request folders of a library: `Requests/*.json` waiting,
/// `Requests/claimed/` being done, `Requests/done/` and `Requests/failed/`.
public enum VideoDigestInbox {
    public static func folder(_ library: URL) -> URL { library.appendingPathComponent("Requests", isDirectory: true) }

    /// Waiting requests, oldest first; iCloud placeholders are asked to
    /// download and come in a later look.
    public static func waiting(_ library: URL) -> [URL] {
        let folder = folder(library)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(".") && name.hasSuffix(".json.icloud") {
            try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(name))
        }
        return names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted().map { folder.appendingPathComponent($0) }
    }

    /// Moves the request to `claimed/` (only one Mac gets it) and reads it.
    public static func claim(_ file: URL) -> (VideoDigestInboxRequest, URL)? {
        let claimed = file.deletingLastPathComponent().appendingPathComponent("claimed", isDirectory: true)
        try? FileManager.default.createDirectory(at: claimed, withIntermediateDirectories: true)
        let target = claimed.appendingPathComponent(file.lastPathComponent)
        guard (try? FileManager.default.moveItem(at: file, to: target)) != nil,
              let data = try? Data(contentsOf: target),
              let request = try? decoder.decode(VideoDigestInboxRequest.self, from: data) else {
            return nil
        }
        return (request, target)
    }

    /// Ends a claimed request in `done/` or `failed/`, with the result.
    public static func finish(_ request: VideoDigestInboxRequest, claimed: URL, folder: URL?, error: String?) {
        var result = request
        result.folder = folder?.lastPathComponent
        result.error = error
        let destination = claimed.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(error == nil ? "done" : "failed", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if let data = try? encoder.encode(result) {
            try? data.write(to: destination.appendingPathComponent(claimed.lastPathComponent), options: .atomic)
        }
        try? FileManager.default.removeItem(at: claimed)
    }

    /// Writes a request for the Mac (atomically: never half a file).
    public static func send(_ request: VideoDigestInboxRequest, library: URL) throws {
        let folder = folder(library)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(request).write(to: folder.appendingPathComponent("\(request.id).json"), options: .atomic)
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// A digest in the library, for the list.
public struct VideoDigestEntry: Identifiable, Equatable {
    public let folder: URL
    public let title: String
    public let stage: VideoDigestJob.Stage
    public let error: String?
    public let updated: Date
    public let html: URL?
    public var id: String { folder.path }

    public static func all(in library: URL) -> [VideoDigestEntry] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { url -> VideoDigestEntry? in
            guard let folder = try? VideoDigestFolder(url: url) else {
                return nil
            }
            // A folder synced by iCloud but not downloaded yet: ask for its state file.
            let placeholder = folder.url.appendingPathComponent("." + folder.job.lastPathComponent + ".icloud")
            if FileManager.default.fileExists(atPath: placeholder.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: folder.job)
            }
            guard let job = try? VideoDigestPipeline.job(folder) else {
                return nil
            }
            return VideoDigestEntry(
                folder: url,
                title: job.video?.title ?? job.request.url,
                stage: job.stage,
                error: job.error,
                updated: job.updated,
                html: FileManager.default.fileExists(atPath: folder.html.path) ? folder.html : nil
            )
        }
        .sorted { $0.updated > $1.updated }
    }
}

