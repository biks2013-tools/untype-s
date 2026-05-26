import Foundation
import Testing
@testable import UntypeCore

private let controllerMarkers = MarkerConfig(
    commandPhrase: "command",
    sectionEndPhrase: "command send",
    sectionEndAliases: ["τέλος εντολής"],
    sectionCancelPhrase: "command cancel",
    literalNextPhrase: "literal phrase"
)

private let allOperatorsOff = OperatorState(
    refine: false,
    translate: false,
    clipboard: false,
    input: false
)

@Test func protocolControllerAgentModeEmitsJsonlWithoutRenderingTranscript() async throws {
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: allOperatorsOff,
        translationPolicy: .opposite
    )

    try controller.startSession()
    controller.partial("draft partial")
    try await controller.final("hello command send")
    try await controller.endSession(reason: "test")

    let events = try protocolEvents(protocolOutput.text)
    #expect(rendered.text.isEmpty)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed",
        "session.ended"
    ])
    #expect(events[1]["raw_text"] as? String == "hello")
    #expect(events[2]["output_text"] as? String == "hello")
    #expect(events[0]["seq"] as? Int == 1)
    #expect(events[3]["seq"] as? Int == 4)
}

@Test func protocolControllerVisibleModeRendersStatusReport() async throws {
    let rendered = MemoryOutput()
    let diagnostics = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: true, input: false),
        translationPolicy: .toEnglish,
        verbose: true,
        diagnostics: ProtocolControllerDiagnostics(write: { line, _ in diagnostics.write(line + "\n") })
    )

    try controller.startSession()
    try await controller.final("command status")

    #expect(rendered.text == "[untype] status: refine=on, translate=off, clipboard=on, input=off, translation_policy=to-en, pending_section=no\n\n")
    #expect(diagnostics.text.contains("[untype] protocol status: refine=on"))
}

@Test func protocolControllerProcessesSectionBeforeClipboardAndInputDelivery() async throws {
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let refiner = MockRefiner { _ in "καθαρό κείμενο" }
    let translator = MockRefiner { prompt in
        #expect(prompt.contains("Translate the following text to English."))
        return "clean text"
    }
    var clipboardText: String?
    var inputText: String?
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: true, clipboard: true, input: true),
        translationPolicy: .opposite,
        refiner: refiner,
        translator: translator,
        clipboardWriter: { text in clipboardText = text },
        inputWriter: { text in inputText = text }
    )

    try controller.startSession()
    try await controller.final("γράψε αυτό command send")

    let events = try protocolEvents(protocolOutput.text)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed",
        "clipboard.copied",
        "input.sent"
    ])
    #expect(events[2]["raw_text"] as? String == "γράψε αυτό")
    #expect(events[2]["refined_text"] as? String == "καθαρό κείμενο")
    #expect(events[2]["source_language"] as? String == "el")
    #expect(events[2]["target_language"] as? String == "en")
    #expect(events[2]["output_text"] as? String == "clean text")
    #expect(clipboardText == "clean text")
    #expect(inputText == "clean text")
    #expect(rendered.text == "γράψε αυτό\n\nclean text\n\n")
}

@Test func protocolControllerUsesCompositeRefineTranslateWhenBothOperatorsAreEnabled() async throws {
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let refiner = MockRefiner { _ in
        Issue.record("Separate refiner should not be called when composite processing is configured")
        return "unexpected-refined"
    }
    let translator = MockRefiner { _ in
        Issue.record("Separate translator should not be called when composite processing is configured")
        return "unexpected-translated"
    }
    let composite = MockCompositeRefineTranslator { request in
        #expect(request.rawText == "γράψε αυτό")
        #expect(request.targetLanguageName == "English")
        return CompositeRefineTranslateResult(
            refinedText: "καθαρό κείμενο",
            translatedText: "clean text"
        )
    }
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: true, clipboard: false, input: false),
        translationPolicy: .opposite,
        refiner: refiner,
        translator: translator,
        compositeRefineTranslator: composite
    )

    try controller.startSession()
    try await controller.final("γράψε αυτό command send")

    let events = try protocolEvents(protocolOutput.text)
    #expect(events[2]["raw_text"] as? String == "γράψε αυτό")
    #expect(events[2]["refined_text"] as? String == "καθαρό κείμενο")
    #expect(events[2]["source_language"] as? String == "el")
    #expect(events[2]["target_language"] as? String == "en")
    #expect(events[2]["output_text"] as? String == "clean text")
    #expect(composite.requests.count == 1)
    #expect(refiner.calls.isEmpty)
    #expect(translator.calls.isEmpty)
    #expect(rendered.text == "γράψε αυτό\n\nclean text\n\n")
}

@Test func protocolControllerCompositeFailureIsFailOpenWithoutSequentialFallback() async throws {
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let diagnostics = MemoryOutput()
    let refiner = MockRefiner { _ in
        Issue.record("Separate refiner should not be called after composite failure")
        return "unexpected-refined"
    }
    let translator = MockRefiner { _ in
        Issue.record("Separate translator should not be called after composite failure")
        return "unexpected-translated"
    }
    let composite = MockCompositeRefineTranslator { _ in
        throw LLMRefinementError("bad composite shape", kind: .shape)
    }
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: true, clipboard: false, input: false),
        translationPolicy: .opposite,
        refiner: refiner,
        translator: translator,
        compositeRefineTranslator: composite,
        diagnostics: ProtocolControllerDiagnostics(write: { line, _ in diagnostics.write(line + "\n") }),
        visibleOperatorDiagnostics: true
    )

    try controller.startSession()
    try await controller.final("γράψε αυτό command send")

    let events = try protocolEvents(protocolOutput.text)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "protocol.warning",
        "protocol.warning",
        "section.processed"
    ])
    #expect(events[4]["raw_text"] as? String == "γράψε αυτό")
    #expect(events[4]["source_language"] as? String == "el")
    #expect(events[4]["target_language"] as? String == "en")
    #expect(events[4]["output_text"] as? String == "γράψε αυτό")
    #expect(events[4]["refined_text"] == nil)
    #expect(composite.requests.count == 1)
    #expect(refiner.calls.isEmpty)
    #expect(translator.calls.isEmpty)
    #expect(diagnostics.text.contains("refine operator failed: bad composite shape"))
    #expect(diagnostics.text.contains("translate operator failed: bad composite shape"))
}

@Test func protocolControllerUsesConfiguredTranslationUserPromptTemplate() async throws {
    let rendered = MemoryOutput()
    var capturedPrompt: String?
    let translator = MockRefiner { prompt in
        capturedPrompt = prompt
        return "translated"
    }
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: false, translate: true, clipboard: false, input: false),
        translationPolicy: .toEnglish,
        translationUserPromptTemplate: "TARGET={target_language}\nBODY={text}",
        translator: translator
    )

    try controller.startSession()
    try await controller.final("γράψε αυτό command send")

    #expect(capturedPrompt == "TARGET=English\nBODY=γράψε αυτό")
    #expect(rendered.text == "γράψε αυτό\n\ntranslated\n\n")
}

@Test func protocolControllerWarningsAreFailOpenWhenRefinerIsMissing() async throws {
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let diagnostics = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite,
        diagnostics: ProtocolControllerDiagnostics(write: { line, _ in diagnostics.write(line + "\n") })
    )

    try controller.startSession()
    try await controller.final("raw words command send")

    let events = try protocolEvents(protocolOutput.text)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "protocol.warning",
        "section.processed"
    ])
    #expect(events[2]["message"] as? String == "Refine operator is enabled, but no LLM refiner is configured.")
    #expect(events[3]["output_text"] as? String == "raw words")
    #expect(rendered.text == "raw words\n\nraw words\n\n")
    #expect(diagnostics.text.contains("[untype] protocol warning: Refine operator is enabled"))
}

@Test func protocolControllerVisibleOperatorDiagnosticsReportClipboardFailureWithoutVerbose() async throws {
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let diagnostics = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: true, input: false),
        translationPolicy: .opposite,
        verbose: false,
        clipboardWriter: { _ in throw VisibleOperatorFailure("clipboard unavailable") },
        diagnostics: ProtocolControllerDiagnostics(write: { line, _ in diagnostics.write(line + "\n") }),
        visibleOperatorDiagnostics: true
    )

    try controller.startSession()
    try await controller.final("raw words command send")

    let events = try protocolEvents(protocolOutput.text)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed",
        "protocol.warning"
    ])
    #expect(events[3]["message"] as? String == "clipboard operator failed: clipboard unavailable")
    #expect(diagnostics.text.contains("[untype] protocol clipboard operator started"))
    #expect(diagnostics.text.contains("[untype] protocol warning: clipboard operator failed: clipboard unavailable"))
    #expect(rendered.text == "raw words\n\nraw words\n\n")
}

@Test func protocolControllerPersistsLatestOperatorSettingsSnapshot() async throws {
    let rendered = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        markers: controllerMarkers,
        initialOperators: allOperatorsOff,
        translationPolicy: .toGreek
    )

    try await controller.toggleOperator(.clipboard)
    try await controller.toggleOperator(.input)

    #expect(controller.settingsSnapshot() == ProtocolSettingsSnapshot(
        operators: OperatorState(refine: false, translate: false, clipboard: true, input: true),
        translationPolicy: .toGreek
    ))
}

private final class MockRefiner: TextRefining {
    private let handler: (String) async throws -> String
    private(set) var calls: [String] = []

    init(handler: @escaping (String) async throws -> String) {
        self.handler = handler
    }

    func refine(_ text: String) async throws -> String {
        calls.append(text)
        return try await handler(text)
    }
}

private final class MockCompositeRefineTranslator: CompositeRefineTranslating {
    private let handler: (CompositeRefineTranslateRequest) async throws -> CompositeRefineTranslateResult
    private(set) var requests: [CompositeRefineTranslateRequest] = []

    init(
        handler: @escaping (CompositeRefineTranslateRequest) async throws -> CompositeRefineTranslateResult
    ) {
        self.handler = handler
    }

    func refineAndTranslate(
        _ request: CompositeRefineTranslateRequest
    ) async throws -> CompositeRefineTranslateResult {
        requests.append(request)
        return try await handler(request)
    }
}

private struct VisibleOperatorFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private func protocolEvents(_ text: String) throws -> [[String: Any]] {
    try text.split(separator: "\n").map { line in
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        return object as? [String: Any] ?? [:]
    }
}

private func eventTypes(_ events: [[String: Any]]) -> [String] {
    events.compactMap { $0["type"] as? String }
}
