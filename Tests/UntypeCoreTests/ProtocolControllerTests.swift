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

@Test func protocolControllerTreatsFocusedInputOkFalseAsFailure() async throws {
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let diagnostics = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: true),
        translationPolicy: .opposite,
        focusedInputWriter: { _ in
            FocusedInputDeliveryResult.failure(
                code: "focused_element_unavailable",
                message: "Could not read the focused UI element."
            )
        },
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
    #expect(events[3]["message"] as? String == "input operator failed: focused_element_unavailable: Could not read the focused UI element. Check that the target control is focused before command send completes, and grant Accessibility permission to the app running untype.")
    #expect(!protocolOutput.text.contains("input.sent"))
    #expect(diagnostics.text.contains("[untype] protocol input operator started"))
    #expect(diagnostics.text.contains("[untype] protocol warning: input operator failed"))
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

// MARK: - Streaming tests (Unit C / Phase-6)

/// Thread-safe accumulator for values emitted from a `@Sendable` closure in tests.
/// Using a reference type avoids the "mutation of captured var in concurrently-executing code"
/// error that arises under Swift 6's strict concurrency when a `var [T]` is captured by a
/// `@Sendable` closure. The `NSLock` makes appends safe across threads.
private final class SinkAccumulator<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [T] = []

    func append(_ value: T) {
        lock.withLock { _values.append(value) }
    }

    var values: [T] {
        lock.withLock { _values }
    }
}

/// A refiner that conforms to BOTH `TextRefining` and `StreamingTextRefining`.
/// When constructed with a non-nil `progressChunks`, it drives `onProgress` with the
/// successive accumulated strings before returning `finalResult`. When `progressChunks`
/// is nil it behaves identically to the plain `MockRefiner`.
private final class MockStreamingRefiner: TextRefining, StreamingTextRefining {
    private let finalResult: String
    /// Each element is one "accumulated so far" string, as the real refiners emit.
    private let progressChunks: [String]?
    private(set) var calls: [String] = []
    private(set) var streamingCalls: [String] = []

    init(finalResult: String, progressChunks: [String]? = nil) {
        self.finalResult = finalResult
        self.progressChunks = progressChunks
    }

    // TextRefining – one-shot path
    func refine(_ text: String) async throws -> String {
        calls.append(text)
        return finalResult
    }

    // StreamingTextRefining – streaming path
    func refine(_ text: String, onProgress: ((String) -> Void)?) async throws -> String {
        streamingCalls.append(text)
        if let chunks = progressChunks {
            for chunk in chunks {
                onProgress?(chunk)
            }
        }
        return finalResult
    }
}

/// A composite that conforms to `CompositeRefineTranslating` and drives streaming progress
/// on the `onProgress` overload, returning a strict final result from the plain result pair.
private final class MockStreamingComposite: CompositeRefineTranslating {
    private let result: CompositeRefineTranslateResult
    /// "Accumulated partial text" sequence emitted via onProgress before the result is
    /// returned. These are DISPLAY-ONLY values; the committed result is always `result`.
    private let progressChunks: [String]?
    private(set) var requests: [CompositeRefineTranslateRequest] = []

    init(result: CompositeRefineTranslateResult, progressChunks: [String]? = nil) {
        self.result = result
        self.progressChunks = progressChunks
    }

    func refineAndTranslate(
        _ request: CompositeRefineTranslateRequest,
        onProgress: ((String) -> Void)?
    ) async throws -> CompositeRefineTranslateResult {
        requests.append(request)
        if let chunks = progressChunks {
            for chunk in chunks {
                onProgress?(chunk)
            }
        }
        return result
    }
}

// MARK: streaming wiring tests

@Test func streamingProgressSinkReceivesAccumulatedChunksOnRefineOnlyPath() async throws {
    let protocolOutput = MemoryOutput()
    let chunks = ["Hello", "Hello,", "Hello, world"]
    let refiner = MockStreamingRefiner(finalResult: "Hello, world", progressChunks: chunks)
    let sink = SinkAccumulator<String>()
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(
            output: MemoryOutput(),
            mode: .append,
            isTTY: false
        ),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        translationPolicy: .toEnglish,
        refiner: refiner,
        streamingProgress: { accumulated in sink.append(accumulated) }
    )

    try controller.startSession()
    try await controller.final("draft text command send")

    // Sink must have been called once per progress chunk, with growing accumulated text.
    #expect(sink.values == chunks)
    // The streaming-capable overload must have been used (not the one-shot).
    #expect(refiner.streamingCalls.count == 1)
    #expect(refiner.calls.isEmpty)
}

@Test func sectionProcessedContainsFinalResultNotPartialTextOnRefineOnlyPath() async throws {
    let protocolOutput = MemoryOutput()
    let refiner = MockStreamingRefiner(
        finalResult: "final refined",
        progressChunks: ["partial", "partial fin"]
    )
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        translationPolicy: .toEnglish,
        refiner: refiner,
        streamingProgress: { _ in }
    )

    try controller.startSession()
    try await controller.final("source text command send")

    let events = try protocolEvents(protocolOutput.text)
    let processed = events.first { $0["type"] as? String == "section.processed" }
    // Committed output_text must be the strict final result, NEVER the partial progress text.
    #expect(processed?["output_text"] as? String == "final refined")
    #expect(processed?["refined_text"] as? String == "final refined")
}

@Test func streamingProgressEventsAreEmittedToProtocolWriterOnRefineOnlyPath() async throws {
    let protocolOutput = MemoryOutput()
    let refiner = MockStreamingRefiner(
        finalResult: "final text",
        progressChunks: ["tok1", "tok1 tok2", "tok1 tok2 tok3"]
    )
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        translationPolicy: .toEnglish,
        refiner: refiner,
        streamingProgress: { _ in }
    )

    try controller.startSession()
    try await controller.final("source command send")

    let events = try protocolEvents(protocolOutput.text)
    let progressEvents = events.filter { $0["type"] as? String == "streaming.progress" }
    // One streaming.progress event per progress callback.
    #expect(progressEvents.count == 3)
    #expect(progressEvents[0]["accumulated_text"] as? String == "tok1")
    #expect(progressEvents[1]["accumulated_text"] as? String == "tok1 tok2")
    #expect(progressEvents[2]["accumulated_text"] as? String == "tok1 tok2 tok3")
    // section_id must be consistent across progress events.
    let ids = progressEvents.compactMap { $0["section_id"] as? String }
    #expect(Set(ids).count == 1)
    // sectionProcessed still fires exactly once, AFTER the progress events.
    let processedEvents = events.filter { $0["type"] as? String == "section.processed" }
    #expect(processedEvents.count == 1)
}

@Test func streamingProgressSinkReceivesAccumulatedChunksOnTranslateOnlyPath() async throws {
    let chunks = ["Hola", "Hola,", "Hola, mundo"]
    let translator = MockStreamingRefiner(finalResult: "Hola, mundo", progressChunks: chunks)
    let sink = SinkAccumulator<String>()
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: false, translate: true, clipboard: false, input: false),
        translationPolicy: .toEnglish,
        translator: translator,
        streamingProgress: { accumulated in sink.append(accumulated) }
    )

    try controller.startSession()
    try await controller.final("source text command send")

    #expect(sink.values == chunks)
    #expect(translator.streamingCalls.count == 1)
}

@Test func sectionProcessedContainsFinalTranslatedTextNotPartialOnTranslateOnlyPath() async throws {
    let protocolOutput = MemoryOutput()
    let translator = MockStreamingRefiner(
        finalResult: "final translation",
        progressChunks: ["partial translation"]
    )
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: false, translate: true, clipboard: false, input: false),
        translationPolicy: .toEnglish,
        translator: translator,
        streamingProgress: { _ in }
    )

    try controller.startSession()
    try await controller.final("source text command send")

    let events = try protocolEvents(protocolOutput.text)
    let processed = events.first { $0["type"] as? String == "section.processed" }
    #expect(processed?["output_text"] as? String == "final translation")
}

@Test func streamingProgressSinkReceivesPartialDisplayTextOnCompositePath() async throws {
    let partialChunks = ["partial refined", "partial refined text"]
    let finalResult = CompositeRefineTranslateResult(
        refinedText: "strictly refined",
        translatedText: "strictly translated"
    )
    let composite = MockStreamingComposite(result: finalResult, progressChunks: partialChunks)
    let sink = SinkAccumulator<String>()
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: true, clipboard: false, input: false),
        translationPolicy: .opposite,
        compositeRefineTranslator: composite,
        streamingProgress: { accumulated in sink.append(accumulated) }
    )

    try controller.startSession()
    try await controller.final("γράψε αυτό command send")

    // The sink must have received the partial display-only text from composite.
    #expect(sink.values == partialChunks)
    #expect(composite.requests.count == 1)
}

@Test func compositePathNeverCommitsPartialTextAsOutputText() async throws {
    // Risk #1: partial JSON from composite must NEVER reach the committed outputText.
    let protocolOutput = MemoryOutput()
    let partialChunks = [
        #"{"refined_text": "partial"#,   // intentionally incomplete JSON fragment
        #"{"refined_text": "partial refined", "translated"#  // still incomplete
    ]
    let finalResult = CompositeRefineTranslateResult(
        refinedText: "final refined",
        translatedText: "final translated"
    )
    let composite = MockStreamingComposite(result: finalResult, progressChunks: partialChunks)
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: true, clipboard: false, input: false),
        translationPolicy: .opposite,
        compositeRefineTranslator: composite,
        streamingProgress: { _ in }
    )

    try controller.startSession()
    try await controller.final("γράψε αυτό command send")

    let events = try protocolEvents(protocolOutput.text)
    let processed = events.first { $0["type"] as? String == "section.processed" }
    // Committed output_text must be the strict final translatedText, not any partial chunk.
    #expect(processed?["output_text"] as? String == "final translated")
    #expect(processed?["refined_text"] as? String == "final refined")
    // Partial chunks must NOT appear as output_text under any circumstance.
    for partialChunk in partialChunks {
        #expect(processed?["output_text"] as? String != partialChunk)
    }
}

@Test func streamingProgressSinkIsNeverInvokedWhenRefinerDoesNotConformToStreamingTextRefining() async throws {
    // Silently-inert path: plain MockRefiner does not conform to StreamingTextRefining.
    let protocolOutput = MemoryOutput()
    let sink = SinkAccumulator<String>()
    let refiner = MockRefiner { _ in "refined text" }
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        translationPolicy: .toEnglish,
        refiner: refiner,
        streamingProgress: { accumulated in sink.append(accumulated) }
    )

    try controller.startSession()
    try await controller.final("some text command send")

    // Sink must never fire — the refiner is not a StreamingTextRefining conformer.
    #expect(sink.values.isEmpty)
    // No streaming.progress events must appear in the protocol output.
    let events = try protocolEvents(protocolOutput.text)
    let progressEvents = events.filter { $0["type"] as? String == "streaming.progress" }
    #expect(progressEvents.isEmpty)
    // Normal processing still completes correctly.
    let processed = events.first { $0["type"] as? String == "section.processed" }
    #expect(processed?["output_text"] as? String == "refined text")
}

@Test func constructingControllerWithNilStreamingProgressLeavesExistingBehaviorUnchanged() async throws {
    // Regression guard: default nil parameter must not break anything.
    let protocolOutput = MemoryOutput()
    let refiner = MockStreamingRefiner(
        finalResult: "processed output",
        progressChunks: ["partial", "partial output"]
    )
    // No streamingProgress parameter — uses the default nil.
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        translationPolicy: .toEnglish,
        refiner: refiner
    )

    try controller.startSession()
    try await controller.final("text command send")

    let events = try protocolEvents(protocolOutput.text)
    // Streaming progress events are still emitted to the protocol stream even with nil sink
    // (the sink is nil but the protocol writer still records them per C5).
    let progressEvents = events.filter { $0["type"] as? String == "streaming.progress" }
    // The streaming-capable refiner was used, so protocol events were emitted.
    #expect(progressEvents.count == 2)
    // sectionProcessed fires with the final result.
    let processed = events.first { $0["type"] as? String == "section.processed" }
    #expect(processed?["output_text"] as? String == "processed output")
}

@Test func streamingProgressSinkIsNeverInvokedWhenNoStreamingProgressParamAndCompositeIsPlain() async throws {
    // Silently-inert composite path: MockCompositeRefineTranslator does not override
    // the streaming overload, so its default extension routes back to the base method.
    // The sink (even when non-nil) must not be invoked since no onProgress is called.
    let protocolOutput = MemoryOutput()
    let sink = SinkAccumulator<String>()
    let composite = MockCompositeRefineTranslator { request in
        CompositeRefineTranslateResult(refinedText: "refined", translatedText: "translated")
    }
    let controller = VoiceAgentProtocolController(
        mode: .agentProtocol,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: controllerMarkers,
        initialOperators: OperatorState(refine: true, translate: true, clipboard: false, input: false),
        translationPolicy: .opposite,
        compositeRefineTranslator: composite,
        streamingProgress: { accumulated in sink.append(accumulated) }
    )

    try controller.startSession()
    try await controller.final("γράψε αυτό command send")

    // Plain composite (implements only base method) never calls onProgress.
    #expect(sink.values.isEmpty)
    let events = try protocolEvents(protocolOutput.text)
    let progressEvents = events.filter { $0["type"] as? String == "streaming.progress" }
    #expect(progressEvents.isEmpty)
    // Normal result still committed.
    let processed = events.first { $0["type"] as? String == "section.processed" }
    #expect(processed?["output_text"] as? String == "translated")
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
