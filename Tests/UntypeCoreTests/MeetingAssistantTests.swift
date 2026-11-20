import AppKit
import Foundation
import Testing
@testable import UntypeCore

// plan-078: the meeting assistant (the Swift side of the helper process).

@Test func theHelpersLinesBecomeEvents() {
    #expect(MeetingAssistantEvent.parse(#"{"type":"ready","provider":"azure","model":"gpt-5.1"}"#) == .ready(provider: "azure", model: "gpt-5.1"))
    #expect(MeetingAssistantEvent.parse(#"{"type":"run_start"}"#) == .runStart)
    #expect(MeetingAssistantEvent.parse(#"{"type":"tool","name":"read_transcript"}"#) == .tool("read_transcript"))
    #expect(MeetingAssistantEvent.parse(#"{"type":"text","delta":"Γειά"}"#) == .text(delta: "Γειά", reset: false))
    #expect(MeetingAssistantEvent.parse(#"{"type":"text","delta":"x","reset":true}"#) == .text(delta: "x", reset: true))
    #expect(MeetingAssistantEvent.parse(#"{"type":"run_end"}"#) == .runEnd(failure: nil))
    #expect(MeetingAssistantEvent.parse(#"{"type":"run_end","failure":"aborted"}"#) == .runEnd(failure: "aborted"))
    #expect(MeetingAssistantEvent.parse(#"{"type":"error","message":"no meeting is open"}"#) == .error("no meeting is open"))
    #expect(MeetingAssistantEvent.parse(#"{"type":"fatal","message":"UNTYPE_AGENT_HOME is not set"}"#) == .fatal("UNTYPE_AGENT_HOME is not set"))
    #expect(MeetingAssistantEvent.parse(#"{"type":"opened","key":"k","history":[{"role":"user","text":"q"},{"role":"assistant","text":"a"}]}"#)
        == .opened(key: "k", history: [AssistantMessage(id: 0, role: .user, text: "q"), AssistantMessage(id: 1, role: .assistant, text: "a")]))
    #expect(MeetingAssistantEvent.parse("not json") == nil)
    #expect(MeetingAssistantEvent.parse(#"{"type":"something else"}"#) == nil)
}

@Test func aMeetingKeepsItsConversationWhenItIsNamed() {
    let plain = URL(fileURLWithPath: "/r/recording-2026-11-20-16-48")
    let named = URL(fileURLWithPath: "/r/Budget-review-Mina-recording-2026-11-20-16-48")
    let second = URL(fileURLWithPath: "/r/recording-2026-11-20-16-48 (2)")
    #expect(MeetingAssistantSettings.key(for: plain) == "recording-2026-11-20-16-48")
    #expect(MeetingAssistantSettings.key(for: named) == MeetingAssistantSettings.key(for: plain))
    #expect(MeetingAssistantSettings.key(for: second) == "recording-2026-11-20-16-48 (2)")
    #expect(MeetingAssistantSettings.key(for: URL(fileURLWithPath: "/r/2026-11-01 10.00 – Old")) == "2026-11-01 10.00 – Old")
}

@Test func theAssistantsModelIsItsOwnSettingAndHasNoDefault() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("untype-assistant-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }

    var environment = try MeetingAssistantSettings.environment(shell: ["PATH": "/usr/bin", "SONIOX_API_KEY": "shell"], home: home)
    #expect(MeetingAssistantSettings.choice(in: environment) == nil)
    #expect(environment["UNTYPE_AGENT_HOME"] == home.appendingPathComponent(".tool-agents/untype/agent").path)

    try MeetingAssistantSettings.save(.init(provider: "azure", model: "gpt-5.1"), home: home)
    try DotenvEditor.upsert(["SONIOX_API_KEY": "from-file"], into: DotenvEditor.userEnvURL(home: home))
    environment = try MeetingAssistantSettings.environment(shell: ["PATH": "/usr/bin", "SONIOX_API_KEY": "shell"], home: home)
    #expect(MeetingAssistantSettings.choice(in: environment) == .init(provider: "azure", model: "gpt-5.1"))
    // The user's file comes before the app's environment, as everywhere in untype.
    #expect(environment["SONIOX_API_KEY"] == "from-file")
    #expect(environment["PATH"] == "/usr/bin")

    try MeetingAssistantSettings.save(.init(provider: "google", model: "gemini-3.5-flash"), home: home)
    environment = try MeetingAssistantSettings.environment(shell: [:], home: home)
    #expect(MeetingAssistantSettings.choice(in: environment) == .init(provider: "google", model: "gemini-3.5-flash"))
}

@Test func theCatalogOfModelsIsRead() throws {
    let json = #"{"providers":[{"id":"azure","name":"Azure","configured":true,"models":[{"id":"gpt-5.1","name":"GPT-5.1"}]},{"id":"xai","name":"xAI","configured":false,"models":[]}]}"#
    let catalog = try JSONDecoder().decode(MeetingAssistantCatalog.self, from: Data(json.utf8))
    #expect(catalog.providers.map(\.id) == ["azure", "xai"])
    #expect(catalog.providers[0].configured)
    #expect(catalog.providers[0].models == [.init(id: "gpt-5.1", name: "GPT-5.1")])
}

@MainActor
@Test func withoutItsProgramTheAssistantSaysSoAndKeepsTheQuestion() {
    let model = MeetingAssistantModel(installation: nil)
    #expect(!model.isAvailable)
    model.ask("anything")
    // No meeting: nothing is asked.
    #expect(model.messages.isEmpty)
    model.setMeeting(folder: URL(fileURLWithPath: "/r/recording-2026-11-20-16-48"), recording: true)
    #expect(model.hasMeeting)
    #expect(model.isRecording)
    model.ask("What was decided?")
    #expect(model.messages.map(\.text) == ["What was decided?"])
    #expect(model.problem == "The assistant is not part of this build of untype.")
    #expect(!model.isBusy)
    // The meeting was named: the same conversation, the new name.
    model.folderRenamed(from: URL(fileURLWithPath: "/r/recording-2026-11-20-16-48"), to: URL(fileURLWithPath: "/r/Budget-recording-2026-11-20-16-48"))
    #expect(model.meetingName == "Budget-recording-2026-11-20-16-48")
    #expect(model.messages.count == 1)
}

@Test func theLineBeingSpokenIsCutAtItsLastFullStop() {
    func token(_ text: String, _ start: Int) -> MeetingToken {
        MeetingToken(text: text, isFinal: true, speaker: "1", language: "en", startMs: start, endMs: start + 100)
    }
    var aggregator = MeetingTokenAggregator(side: .call, offsetMs: 1_000)
    // No sentence has ended: nothing is cut, nothing is lost.
    #expect(aggregator.add([token("The", 0), token(" price", 100)]).isEmpty)
    #expect(aggregator.flushThroughLastSentenceEnd() == nil)
    #expect(aggregator.inProgressText(with: []) == "The price")

    // "3.5" is not a sentence end; the last real one is "ready?".
    _ = aggregator.add([
        token(" is", 200), token(" 3", 300), token(".", 400), token("5", 500), token(" million", 600), token(".", 700),
        token(" Are", 800), token(" we", 900), token(" ready", 1_000), token("?", 1_100),
        token(" I", 1_200), token(" think", 1_300),
    ])
    let cut = aggregator.flushThroughLastSentenceEnd()
    #expect(cut?.text == "The price is 3.5 million. Are we ready?")
    #expect(cut?.startMs == 1_000)
    #expect(cut?.endMs == 2_200)
    #expect(cut?.speaker == "1")
    // The words after the full stop stay in progress and end normally.
    #expect(aggregator.inProgressText(with: []) == "I think")
    #expect(aggregator.flushThroughLastSentenceEnd() == nil)
    let rest = aggregator.add([token(" so", 1_400), token(".", 1_500), MeetingToken(text: "<end>", isFinal: true)])
    #expect(rest.map(\.text) == ["I think so."])
    #expect(rest.first?.startMs == 2_200)
}

@MainActor
@Test func theWindowAsksForTheCutOnlyWhileRecordingAndAQuestionAsksForItFirst() {
    let feed = MeetingTranscriptFeed()
    var cuts = 0
    feed.onCutRequest = { cuts += 1 }
    feed.cutAtLastSentenceEnd()
    #expect(cuts == 0)
    feed.begin(meetingName: "m")
    feed.cutAtLastSentenceEnd()
    #expect(cuts == 1)

    let model = MeetingAssistantModel(installation: nil)
    var order: [String] = []
    model.beforeAsk = { order.append("cut") }
    model.setMeeting(folder: URL(fileURLWithPath: "/r/recording-2026-11-20-16-48"), recording: true)
    model.ask("What now?")
    #expect(order == ["cut"])
    #expect(model.messages.map(\.text) == ["What now?"])
}

@Test func loudSoundIsLoweredForTheDictationAndPutBack() {
    var duck = OutputVolumeDuck()
    // Loud: lowered, and back afterwards.
    #expect(duck.begin(current: 0.7) == OutputVolumeDuck.quiet)
    #expect(duck.begin(current: OutputVolumeDuck.quiet) == nil)
    #expect(duck.end(current: OutputVolumeDuck.quiet) == 0.7)
    #expect(duck.previous == nil)
    // Already quiet, or an output without a volume: left alone.
    #expect(duck.begin(current: 0.1) == nil)
    #expect(duck.begin(current: nil) == nil)
    #expect(duck.end(current: 0.1) == nil)
    // The user changed the volume during the dictation: theirs stays.
    #expect(duck.begin(current: 0.9) == OutputVolumeDuck.quiet)
    #expect(duck.end(current: 0.5) == nil)
    #expect(duck.previous == nil)
}

@Test func aLineAndAnAttachmentCanBeTakenOutOfTheMeeting() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("untype-delete-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let names = MeetingFileNames(stem: "recording-2026-11-20-10-30")
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    // The files written during the meeting are written again without the line.
    let files = try MeetingLiveFiles(folder: folder, names: names, start: start, language: .original)
    let keep = MeetingSegment(startMs: 0, endMs: 900, side: .you, speaker: nil, language: "en", text: "keep this")
    let drop = MeetingSegment(startMs: 1_000, endMs: 1_900, side: .call, speaker: "1", language: "en", text: "drop this")
    files.append(keep)
    files.append(drop)
    files.rewrite([keep])
    files.close()
    for name in [names.mainTranscript, names.originalTranscript, names.segments, names.systemTranscript, names.microphoneTranscript] {
        let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        #expect(!text.contains("drop this"))
    }
    #expect(try String(contentsOf: folder.appendingPathComponent(names.mainTranscript), encoding: .utf8).contains("keep this"))

    // An attachment: its file and its entry go; its number is not used again.
    let store = MeetingAttachmentStore(folder: folder, names: names, start: start)
    let first = await store.add(MeetingClipboardContent(text: "one"), offsetMs: 1_000)
    let file = folder.appendingPathComponent(try #require(first.added.first).file)
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(try await store.remove(id: 1))
    #expect(try await !store.remove(id: 1))
    #expect(!FileManager.default.fileExists(atPath: file.path))
    let second = await store.add(MeetingClipboardContent(text: "two"), offsetMs: 2_000)
    #expect(second.added.first?.id == 2)
    let index = try MeetingAttachmentIndex.decode(Data(contentsOf: folder.appendingPathComponent(names.attachments)))
    #expect(index.attachments.map(\.id) == [2])
}

@MainActor
@Test func aDeletedRowLeavesTheWindowOnlyWhenTheRecorderSaysSo() {
    let feed = MeetingTranscriptFeed()
    var asked: [String] = []
    feed.onDeleteRequest = { asked.append($0.id) }
    feed.begin(meetingName: "m")
    feed.add(MeetingSegment(startMs: 0, endMs: 1, side: .you, speaker: nil, language: nil, text: "a"))
    feed.add(MeetingSegment(startMs: 2, endMs: 3, side: .call, speaker: "1", language: nil, text: "b"))
    feed.noteAttach(added: [MeetingAttachment(id: 1, clip: 1, offsetMs: 3, time: "00:00:00", attachedAt: Date(), kind: .text, file: "attachments/1.txt")], note: "x")
    let rows = feed.rows(for: .both)
    #expect(rows.map(\.id) == ["line-0", "line-1", "attachment-1"])
    feed.delete(rows[0])
    #expect(asked == ["line-0"])
    // Still shown until the recorder has taken it out.
    #expect(feed.rows(for: .both).count == 3)
    feed.removed(rows[0])
    feed.removed(rows[2])
    #expect(feed.rows(for: .both).map(\.id) == ["line-1"])
    #expect(feed.attachmentCount == 0)
    feed.end()
    feed.delete(rows[1])
    #expect(asked == ["line-0"])
}

@Test func theHelperAsksUntypeForTheTextOfADocument() {
    #expect(MeetingAssistantEvent.parse(#"{"type":"extract","id":"x1","path":"/r/m/attachments/001-a.pdf"}"#) == .extract(id: "x1", path: "/r/m/attachments/001-a.pdf"))
    #expect(MeetingAssistantEvent.parse(#"{"type":"extract","id":"x1"}"#) == nil)
}

@MainActor
@Test func aPDFAndARichTextFileGiveTheirText() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("untype-documents-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    // A two-page PDF drawn here.
    let pdf = folder.appendingPathComponent("report.pdf")
    var box = CGRect(x: 0, y: 0, width: 400, height: 300)
    let context = try #require(CGContext(pdf as CFURL, mediaBox: &box, nil))
    for words in ["Quarterly budget", "Ξεχωριστή σελίδα"] {
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (words as NSString).draw(at: CGPoint(x: 40, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
    let text = try MeetingDocumentText.extract(pdf)
    #expect(text.contains("--- Page 1 of 2 ---"))
    #expect(text.contains("Quarterly budget"))
    #expect(text.contains("--- Page 2 of 2 ---"))
    #expect(text.contains("Ξεχωριστή σελίδα"))

    let rtf = folder.appendingPathComponent("note.rtf")
    let written = NSAttributedString(string: "Agreed: ship on Friday")
    try written.data(from: NSRange(location: 0, length: written.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: rtf)
    #expect(try MeetingDocumentText.extract(rtf) == "Agreed: ship on Friday")

    #expect(throws: (any Error).self) { try MeetingDocumentText.extract(folder.appendingPathComponent("archive.zip")) }
    try Data("not a pdf".utf8).write(to: folder.appendingPathComponent("broken.pdf"))
    #expect(throws: (any Error).self) { try MeetingDocumentText.extract(folder.appendingPathComponent("broken.pdf")) }
}
