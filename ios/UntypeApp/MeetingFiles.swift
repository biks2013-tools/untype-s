@preconcurrency import AVFoundation
import Foundation
import UntypeCore

/// The files of one meeting recorded on the iPhone or iPad, in the layout of
/// the Mac's meeting recorder, so untype studio opens the folder as a
/// recording:
///
///     recording-2026-11-26-10-30/
///       recording-2026-11-26-10-30.m4a                       the audio
///       recording-2026-11-26-10-30.transcript.txt            `[00:00:05] Speaker 1 [el]: …`
///       recording-2026-11-26-10-30.transcript.original.txt   the same (as spoken)
///       recording-2026-11-26-10-30.segments.jsonl            untype's segments
///       recording-2026-11-26-10-30.system.transcript.jsonl   ntakker's format
///       recording-2026-11-26-10-30.studio.json               when the audio started
///
/// The phone's microphone hears the whole room, so its lines are those of
/// the Mac's call side (speakers numbered, `system` transcript); the audio
/// is one mixed track. The transcript files exist only when a transcript
/// was made. Lines are appended as they are heard (they survive a crash)
/// and written again in time order at the end.
final class MeetingFolderWriter {
    let folder: URL
    let names: MeetingFileNames
    let start: Date
    private var handles: [String: FileHandle] = [:]
    private let encoder: JSONEncoder

    var audioURL: URL { folder.appendingPathComponent(names.mixedAudio) }

    init(root: URL, start: Date) throws {
        self.start = start
        names = MeetingFileNames(start: start)
        let base = names.stem
        var folder = root.appendingPathComponent(base, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = root.appendingPathComponent("\(base) (\(counter))", isDirectory: true)
            counter += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try Self.studioMetadata(audioStart: start)
            .write(to: folder.appendingPathComponent(names.studioMetadata), options: .atomic)
    }

    /// `<stem>.studio.json` as untype studio reads it.
    static func studioMetadata(audioStart: Date) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let object: [String: Any] = [
            "version": 1,
            "audioStart": formatter.string(from: audioStart)
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private var transcriptFiles: [String] {
        [names.originalTranscript, names.mainTranscript, names.systemTranscript, names.segments]
    }

    func append(_ segment: MeetingSegment) {
        let line = MeetingTranscriptFormat.originalLine(segment)
        write(line, to: names.originalTranscript)
        // No English pass on the phone: the main transcript is as spoken.
        write(line, to: names.mainTranscript)
        if let data = try? encoder.encode(MeetingSidecarLine(segment: segment, meetingStart: start)) {
            write(String(decoding: data, as: UTF8.self), to: names.systemTranscript)
        }
        if let data = try? encoder.encode(segment) {
            write(String(decoding: data, as: UTF8.self), to: names.segments)
        }
    }

    /// Closes the files and writes the transcript again in time order.
    func finish(_ segments: [MeetingSegment]) throws {
        for handle in handles.values {
            try? handle.close()
        }
        handles = [:]
        guard !segments.isEmpty else {
            return
        }
        let ordered = MeetingTranscriptFormat.ordered(segments)
        let text = ordered.map(MeetingTranscriptFormat.originalLine).joined(separator: "\n") + "\n"
        let jsonl = ordered.compactMap { try? encoder.encode($0) }
            .map { String(decoding: $0, as: UTF8.self) }
            .joined(separator: "\n") + "\n"
        try text.write(to: url(names.originalTranscript), atomically: true, encoding: .utf8)
        try text.write(to: url(names.mainTranscript), atomically: true, encoding: .utf8)
        try jsonl.write(to: url(names.segments), atomically: true, encoding: .utf8)
        try MeetingSidecarLine.file(ordered, side: .call, meetingStart: start)
            .write(to: url(names.systemTranscript), atomically: true, encoding: .utf8)
    }

    private func url(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    private func write(_ line: String, to name: String) {
        let handle: FileHandle
        if let open = handles[name] {
            handle = open
        } else {
            FileManager.default.createFile(atPath: url(name).path, contents: nil)
            guard let made = try? FileHandle(forWritingTo: url(name)) else {
                return
            }
            handles[name] = made
            handle = made
        }
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}

/// A meeting saved on this device.
struct SavedMeeting: Identifiable, Hashable {
    let folder: URL
    var id: String { folder.path }
    var name: String { folder.lastPathComponent }
    var title: String? { MeetingNaming.title(of: name) }
    var friendlyDate: String { MeetingNaming.friendlyDate(of: name) ?? name }
    var stem: String? {
        MeetingNaming.stem(of: name)
    }

    private func file(_ suffix: String) -> URL? {
        guard let stem else {
            return nil
        }
        let url = folder.appendingPathComponent(stem + suffix)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var audio: URL? { file(".m4a") }

    /// The transcript lines (empty when no transcript was made).
    func segments() -> [MeetingSegment] {
        guard let url = file(".segments.jsonl"), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(MeetingSegment.self, from: Data($0.utf8)) }
    }

    func duration() async -> TimeInterval? {
        guard let audio else {
            return nil
        }
        guard let time = try? await AVURLAsset(url: audio).load(.duration) else {
            return nil
        }
        let seconds = time.seconds
        return seconds.isFinite ? seconds : nil
    }

    /// The transcript as text, `[00:00:05] Speaker 1 [el]: …` per line.
    func transcriptText() -> String {
        MeetingTranscriptFormat.ordered(segments()).map(MeetingTranscriptFormat.originalLine).joined(separator: "\n")
    }

    /// The folder as a `.zip` in the temporary folder, for sharing.
    func zipped() throws -> URL {
        var made: URL?
        var copyError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zip in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".zip")
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: zip, to: target)
                made = target
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            throw error
        }
        guard let made else {
            throw AppError("The ZIP file could not be made.")
        }
        return made
    }
}

/// The meetings saved on this device, newest first, in
/// `Documents/Meetings` (visible in the Files app: On My iPhone → untype).
@MainActor
final class MeetingLibrary: ObservableObject {
    @Published private(set) var meetings: [SavedMeeting] = []
    @Published var problem: String?

    static var root: URL {
        get throws {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let root = documents.appendingPathComponent("Meetings", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }
    }

    func reload() {
        do {
            let folders = try FileManager.default.contentsOfDirectory(
                at: Self.root,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
            meetings = folders
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map(SavedMeeting.init(folder:))
                .sorted { ($0.stem ?? $0.name) > ($1.stem ?? $1.name) }
        } catch {
            problem = error.localizedDescription
        }
    }

    func delete(_ meeting: SavedMeeting) {
        do {
            try FileManager.default.removeItem(at: meeting.folder)
        } catch {
            problem = error.localizedDescription
        }
        reload()
    }

    /// Renames the folder to `<title>-recording-…` (the files keep their
    /// names, as on the Mac); returns the renamed meeting.
    func rename(_ meeting: SavedMeeting, to title: String) -> SavedMeeting? {
        do {
            let renamed = try MeetingNaming.rename(folder: meeting.folder, title: title)
            reload()
            return SavedMeeting(folder: renamed)
        } catch {
            problem = error.localizedDescription
            return nil
        }
    }
}
