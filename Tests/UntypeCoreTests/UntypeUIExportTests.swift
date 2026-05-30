import Foundation
import Testing
@testable import UntypeCore

@Test func uiExportBuildsEventsDocumentInChronologicalOrder() {
    let document = UntypeUIExportDocument.events(
        from: [
            "session.state: starting",
            "transcript.final: Hello.",
            "session.state: stopped"
        ],
        generatedAt: Date(timeIntervalSince1970: 0)
    )

    #expect(document?.kind == .events)
    #expect(document?.text == """
    session.state: starting
    transcript.final: Hello.
    session.state: stopped
    """)
    #expect(document?.suggestedFileName.hasPrefix("untype-events-") == true)
    #expect(document?.suggestedFileName.hasSuffix(".txt") == true)
}

@Test func uiExportDoesNotBuildEmptyEventsDocument() {
    #expect(UntypeUIExportDocument.events(from: []) == nil)
    #expect(UntypeUIExportDocument.events(from: ["  ", "\n"]) == nil)
}

@Test func uiExportActionRouterCopiesAndSavesSelectedDocument() throws {
    let document = UntypeUIExportDocument(
        kind: .transcript,
        text: "Turn 1 | 10:00:00 | closed\n[Dictated text | en]\nHello."
    )
    var copiedText: String?
    var savedDocument: UntypeUIExportDocument?
    let router = UntypeUIExportActionRouter(
        copyText: { copiedText = $0 },
        saveDocument: { savedDocument = $0 }
    )

    let copied = try router.copy(document)
    let saved = try router.save(document)

    #expect(copied.kind == .transcript)
    #expect(saved.kind == .transcript)
    #expect(copiedText == document.text)
    #expect(savedDocument == document)
}

@Test func uiTranscriptSectionCopyPayloadPreservesExactNonEmptyText() {
    let raw = UntypeUITranscriptSectionCopyPayload(
        kind: .raw,
        text: "  dictated words\n"
    )
    let processed = UntypeUITranscriptSectionCopyPayload(
        kind: .processed,
        text: "Refined words."
    )

    #expect(raw?.kind == .raw)
    #expect(raw?.text == "  dictated words\n")
    #expect(raw?.kind.displayName == "raw")
    #expect(processed?.kind == .processed)
    #expect(processed?.text == "Refined words.")
    #expect(processed?.kind.eventName == "processed")
}

@Test func uiTranscriptSectionCopyPayloadRejectsEmptyText() {
    #expect(UntypeUITranscriptSectionCopyPayload(kind: .raw, text: " \n") == nil)
    #expect(UntypeUITranscriptSectionCopyPayload(kind: .processed, text: "") == nil)
}

@Test func uiExportActionRouterRejectsEmptyContent() {
    let router = UntypeUIExportActionRouter(
        copyText: { _ in Issue.record("copy should not run for empty content") },
        saveDocument: { _ in Issue.record("save should not run for empty content") }
    )
    let empty = UntypeUIExportDocument(kind: .events, text: " \n")

    #expect(throws: UntypeUIExportActionError.emptyContent) {
        try router.copy(empty)
    }
    #expect(throws: UntypeUIExportActionError.emptyContent) {
        try router.save(empty)
    }
    #expect(throws: UntypeUIExportActionError.emptyContent) {
        try router.copy(nil)
    }
    #expect(throws: UntypeUIExportActionError.emptyContent) {
        try router.save(nil)
    }
}
