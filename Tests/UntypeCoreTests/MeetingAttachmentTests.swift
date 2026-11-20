import AppKit
import Foundation
import Testing
@testable import UntypeCore

// plan-077: the clipboard is attached to a moment of the meeting.

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("untype-attach-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func pngData(width: Int, height: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return bitmap.representation(using: .png, properties: [:])!
}

private func scratchPasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("untype-test-\(UUID().uuidString)"))
    pasteboard.clearContents()
    return pasteboard
}

@Test func textIsSavedWithTheMomentOfTheMeeting() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let names = MeetingFileNames(stem: "recording-2026-11-20-10-30")
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let store = MeetingAttachmentStore(folder: folder, names: names, start: start)

    let result = await store.add(MeetingClipboardContent(text: "Γειά σου"), offsetMs: 754_300, at: start.addingTimeInterval(754))

    #expect(result.failures.isEmpty)
    let attachment = try #require(result.added.first)
    #expect(attachment.id == 1)
    #expect(attachment.kind == .text)
    #expect(attachment.offsetMs == 754_300)
    #expect(attachment.time == "00:12:34")
    #expect(attachment.characters == 8)
    #expect(attachment.file == "attachments/001-00-12-34-text.txt")
    #expect(try String(contentsOf: folder.appendingPathComponent(attachment.file), encoding: .utf8) == "Γειά σου")

    let index = try MeetingAttachmentIndex.decode(Data(contentsOf: folder.appendingPathComponent("recording-2026-11-20-10-30.attachments.json")))
    #expect(index.recording == "recording-2026-11-20-10-30")
    #expect(index.startedAt == start)
    #expect(index.attachments == result.added)
}

@Test func anImageAndItsTextAreOneClipAndFilesKeepTheirNames() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: source) }
    let file = source.appendingPathComponent("notes: v2.pdf".replacingOccurrences(of: ":", with: ""))
    try Data([1, 2, 3]).write(to: file)
    let store = MeetingAttachmentStore(folder: folder, names: MeetingFileNames(stem: "recording-x"), start: Date())
    let image = try #require(MeetingClipboardContent.image(from: pngData(width: 4, height: 3), isPNG: true))

    let first = await store.add(MeetingClipboardContent(image: image, text: "caption"), offsetMs: 1_000)
    let second = await store.add(MeetingClipboardContent(files: [file, source.appendingPathComponent("missing.bin")]), offsetMs: 2_000)

    #expect(first.added.map(\.kind) == [.image, .text])
    #expect(Set(first.added.map(\.clip)) == [1])
    #expect(first.added[0].width == 4)
    #expect(first.added[0].height == 3)
    #expect(first.summary == "image (4×3), text (7 characters)")
    #expect(second.added.count == 1)
    #expect(second.failures.count == 1)
    #expect(second.added[0].id == 3)
    #expect(second.added[0].clip == 2)
    #expect(second.added[0].kind == .file)
    #expect(second.added[0].bytes == 3)
    #expect(second.added[0].originalName == "notes v2.pdf")
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(second.added[0].file).path))
    #expect(await store.count == 3)
}

@Test func nothingIsWrittenForAnEmptyClipboard() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MeetingAttachmentStore(folder: folder, names: MeetingFileNames(stem: "recording-x"), start: Date())
    let result = await store.add(MeetingClipboardContent(), offsetMs: 0)
    #expect(result.added.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
}

@Test func theClipboardIsReadAsFilesOrAsPictureAndText() throws {
    let empty = scratchPasteboard()
    defer { empty.releaseGlobally() }
    #expect(MeetingClipboardContent.read(empty).isEmpty)

    let text = scratchPasteboard()
    defer { text.releaseGlobally() }
    text.setString("  \n ", forType: .string)
    #expect(MeetingClipboardContent.read(text).isEmpty)
    text.clearContents()
    text.setString("hello", forType: .string)
    #expect(MeetingClipboardContent.read(text) == MeetingClipboardContent(text: "hello"))

    let picture = scratchPasteboard()
    defer { picture.releaseGlobally() }
    picture.setData(pngData(width: 2, height: 5), forType: .png)
    let read = MeetingClipboardContent.read(picture)
    #expect(read.image?.width == 2)
    #expect(read.image?.height == 5)
    #expect(read.text == nil)

    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.txt")
    try Data("x".utf8).write(to: file)
    let files = scratchPasteboard()
    defer { files.releaseGlobally() }
    files.writeObjects([file as NSURL])
    files.setString("a.txt", forType: .string)
    let copied = MeetingClipboardContent.read(files)
    #expect(copied.files.map(\.lastPathComponent) == ["a.txt"])
    #expect(copied.text == nil)
}

@MainActor
@Test func theWindowAsksToAttachOnlyWhileRecordingAndCountsWhatWasAttached() {
    let feed = MeetingTranscriptFeed()
    var requests = 0
    var dropped: [[String]] = []
    feed.onAttachRequest = { requests += 1 }
    feed.onAttachFilesRequest = { dropped.append($0.map(\.lastPathComponent)) }
    feed.attachClipboard()
    #expect(requests == 0)
    #expect(!feed.attachFiles([URL(fileURLWithPath: "/tmp/a.pdf")]))
    feed.begin(meetingName: "m")
    // Dropped or chosen files: only files, only while recording.
    #expect(feed.attachFiles([URL(fileURLWithPath: "/tmp/a.pdf"), URL(string: "https://example.com/x")!]))
    #expect(!feed.attachFiles([URL(string: "https://example.com/x")!]))
    #expect(dropped == [["a.pdf"]])
    feed.attachClipboard()
    #expect(requests == 1)
    func attachment(_ id: Int) -> MeetingAttachment {
        MeetingAttachment(id: id, clip: id, offsetMs: 0, time: "00:00:00", attachedAt: Date(), kind: .text, file: "attachments/\(id).txt")
    }
    func segment(_ side: MeetingSide) -> MeetingSegment {
        MeetingSegment(startMs: 0, endMs: 1, side: side, speaker: nil, language: nil, text: "t")
    }
    feed.setMeetingFolder(URL(fileURLWithPath: "/tmp/m"))
    feed.add(segment(.you))
    feed.noteAttach(added: [attachment(1)], note: "Attached")
    feed.add(segment(.call))
    feed.add(segment(.you))
    feed.noteAttach(added: [attachment(2)], note: "Attached")
    #expect(feed.attachmentCount == 2)
    #expect(feed.attachNote == "Attached")
    // At the place of the conversation, on every tab.
    #expect(feed.rows(for: .both).map(\.id) == ["line-0", "attachment-1", "line-1", "line-2", "attachment-2"])
    #expect(feed.rows(for: .microphone).map(\.id) == ["line-0", "attachment-1", "line-2", "attachment-2"])
    #expect(feed.url(of: attachment(1))?.path == "/tmp/m/attachments/1.txt")
    feed.folderRenamed(from: URL(fileURLWithPath: "/tmp/m"), to: URL(fileURLWithPath: "/tmp/named"))
    #expect(feed.url(of: attachment(1))?.path == "/tmp/named/attachments/1.txt")
    feed.clear()
    #expect(feed.rows(for: .both).isEmpty)
    feed.begin(meetingName: "n")
    #expect(feed.attachmentCount == 0)
    #expect(feed.attachNote == nil)
}
