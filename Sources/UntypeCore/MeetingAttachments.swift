#if os(macOS)
import AppKit
import Foundation

// plan-077: what the clipboard holds is attached to the meeting being
// recorded, at the moment of the conversation the user asks for it.

public enum MeetingAttachmentKind: String, Codable, Sendable, Equatable {
    case text
    case image
    case file
    case folder
}

/// One thing attached to a meeting: a file in the meeting folder and the
/// moment of the recording it belongs to.
public struct MeetingAttachment: Codable, Sendable, Equatable {
    /// 1, 2, … in the order they were attached.
    public var id: Int
    /// The attach action it came from: everything attached with one press
    /// (several files, or an image and its text) has the same number.
    public var clip: Int
    /// Milliseconds since the meeting started, on the clock of the
    /// transcript's `startMs` and of the audio files.
    public var offsetMs: Int
    /// `offsetMs` as the transcript writes it (`00:12:34`).
    public var time: String
    public var attachedAt: Date
    public var kind: MeetingAttachmentKind
    /// Where it was saved, relative to the meeting folder.
    public var file: String
    public var bytes: Int?
    /// The name of the copied file or folder.
    public var originalName: String?
    /// Text: how many characters.
    public var characters: Int?
    /// Image: its size in pixels.
    public var width: Int?
    public var height: Int?
}

/// `<stem>.attachments.json`: every attachment of a meeting.
public struct MeetingAttachmentIndex: Codable, Sendable, Equatable {
    public var version = 1
    /// The stem of the recording's files (`recording-yyyy-MM-dd-HH-mm`).
    public var recording: String
    /// When the recording started (offset 0).
    public var startedAt: Date
    public var attachments: [MeetingAttachment] = []

    public static func decode(_ data: Data) throws -> MeetingAttachmentIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MeetingAttachmentIndex.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// What the clipboard holds that can be attached. Copied files come alone
/// (the clipboard's text and picture are then only their names and icons);
/// otherwise the picture and the text, whichever are there.
public struct MeetingClipboardContent: Sendable, Equatable {
    public struct Image: Sendable, Equatable {
        public var png: Data
        public var width: Int
        public var height: Int
    }

    public var files: [URL] = []
    public var image: Image?
    public var text: String?

    public init(files: [URL] = [], image: Image? = nil, text: String? = nil) {
        self.files = files
        self.image = image
        self.text = text
    }

    public var isEmpty: Bool {
        files.isEmpty && image == nil && text == nil
    }

    /// Pictures as applications put them on the clipboard (a screenshot is
    /// PNG or TIFF). Not PDF: office applications add one to copied text.
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("com.microsoft.bmp"),
    ]

    public static func read(_ pasteboard: NSPasteboard = .general) -> MeetingClipboardContent {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !files.isEmpty {
            return MeetingClipboardContent(files: files)
        }
        var content = MeetingClipboardContent()
        if let type = pasteboard.availableType(from: imageTypes), let data = pasteboard.data(forType: type) {
            content.image = image(from: data, isPNG: type == .png)
        }
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content.text = text
        }
        return content
    }

    /// The picture as PNG, with its size in pixels (nil when the data is
    /// not a picture).
    public static func image(from data: Data, isPNG: Bool) -> Image? {
        guard let bitmap = NSBitmapImageRep(data: data) else {
            return nil
        }
        guard let png = isPNG ? data : bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return Image(png: png, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }
}

/// What one attach action saved, and what it could not.
public struct MeetingAttachmentResult: Sendable, Equatable {
    public var added: [MeetingAttachment] = []
    public var failures: [String] = []
}

/// Saves the attachments of one meeting: the files under `attachments/` of
/// the meeting folder, and `<stem>.attachments.json` rewritten after every
/// one of them, so what was attached is on disk during the meeting.
public actor MeetingAttachmentStore {
    public static let folderName = "attachments"

    private let folder: URL
    private let indexURL: URL
    private var index: MeetingAttachmentIndex
    private var clips = 0

    public init(folder: URL, names: MeetingFileNames, start: Date) {
        self.folder = folder
        indexURL = folder.appendingPathComponent(names.attachments)
        index = MeetingAttachmentIndex(recording: names.stem, startedAt: start)
    }

    public var count: Int {
        index.attachments.count
    }

    public func add(_ content: MeetingClipboardContent, offsetMs: Int, at date: Date = Date()) -> MeetingAttachmentResult {
        var result = MeetingAttachmentResult()
        guard !content.isEmpty else {
            return result
        }
        let directory = folder.appendingPathComponent(Self.folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            result.failures.append(error.localizedDescription)
            return result
        }
        clips += 1
        let clip = clips
        let time = MeetingTranscriptFormat.timestamp(offsetMs)

        func save(kind: MeetingAttachmentKind, name: String, write: (URL) throws -> Void, fill: (inout MeetingAttachment) -> Void) {
            let id = (index.attachments.last?.id ?? 0) + 1
            let fileName = Self.fileName(id: id, time: time, name: name)
            let target = directory.appendingPathComponent(fileName)
            do {
                try write(target)
                var attachment = MeetingAttachment(
                    id: id,
                    clip: clip,
                    offsetMs: max(0, offsetMs),
                    time: time,
                    attachedAt: date,
                    kind: kind,
                    file: Self.folderName + "/" + fileName
                )
                fill(&attachment)
                index.attachments.append(attachment)
                try index.encoded().write(to: indexURL, options: .atomic)
                result.added.append(attachment)
            } catch {
                result.failures.append(error.localizedDescription)
            }
        }

        for file in content.files {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            save(
                kind: isDirectory.boolValue ? .folder : .file,
                name: file.lastPathComponent,
                write: { try FileManager.default.copyItem(at: file, to: $0) },
                fill: {
                    $0.originalName = file.lastPathComponent
                    $0.bytes = isDirectory.boolValue ? nil : size
                }
            )
        }
        if let image = content.image {
            save(kind: .image, name: "image.png", write: { try image.png.write(to: $0, options: .atomic) }, fill: {
                $0.bytes = image.png.count
                $0.width = image.width
                $0.height = image.height
            })
        }
        if let text = content.text {
            let data = Data(text.utf8)
            save(kind: .text, name: "text.txt", write: { try data.write(to: $0, options: .atomic) }, fill: {
                $0.bytes = data.count
                $0.characters = text.count
            })
        }
        return result
    }

    /// `003-00-12-34-<name>`: in order, with the moment of the meeting.
    static func fileName(id: Int, time: String, name: String) -> String {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return String(format: "%03d", id) + "-" + time.replacingOccurrences(of: ":", with: "-") + "-" + safe
    }
}

public extension MeetingAttachmentResult {
    /// What was attached, for the user and the log: kinds and sizes only,
    /// never names or text.
    var summary: String {
        added.map { attachment in
            switch attachment.kind {
            case .text: return "text (\(attachment.characters ?? 0) characters)"
            case .image: return "image (\(attachment.width ?? 0)×\(attachment.height ?? 0))"
            case .file: return "file"
            case .folder: return "folder"
            }
        }.joined(separator: ", ")
    }
}
#endif
