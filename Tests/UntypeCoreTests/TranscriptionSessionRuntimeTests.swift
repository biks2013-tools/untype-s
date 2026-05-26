import Foundation
import Testing
@testable import UntypeCore

private let runtimeMarkers = MarkerConfig(
    commandPhrase: "command",
    sectionEndPhrase: "command send",
    sectionEndAliases: ["τέλος εντολής"],
    sectionCancelPhrase: "command cancel",
    literalNextPhrase: "literal phrase"
)

@Test func sessionRuntimeStartsRoutesAudioAndTranscriptEventsThenStops() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    var sessionEvents: [TranscriptionSessionEvent] = []
    var savedSnapshot: ProtocolSettingsSnapshot?
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            emit: { sessionEvents.append($0) },
            saveProtocolSettings: { savedSnapshot = $0 }
        )
    )

    try await runtime.start()
    await audio.emitAudio(Data([0x00, 0x40, 0x00, 0x00]))
    transcriber.emitPartial("hel")
    await transcriber.emitFinal("hello command send")
    await runtime.stop(reason: "test")

    let events = try protocolEvents(protocolOutput.text)
    #expect(audio.started)
    #expect(audio.stopped)
    #expect(transcriber.started)
    #expect(transcriber.stopped)
    #expect(transcriber.pushedAudio == [Data([0x00, 0x40, 0x00, 0x00])])
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed",
        "session.ended"
    ])
    #expect(events[1]["raw_text"] as? String == "hello")
    #expect(events[2]["output_text"] as? String == "hello")
    #expect(savedSnapshot == ProtocolSettingsSnapshot(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    ))
    #expect(sessionEvents.contains(.stateChanged(.starting, reason: nil)))
    #expect(sessionEvents.contains(.diagnostic(message: "[untype] starting microphone capture", warning: false)))
    #expect(sessionEvents.contains(.diagnostic(message: "[untype] microphone capture started", warning: false)))
    #expect(sessionEvents.contains(.diagnostic(message: "[untype] connecting STT provider realtime stream", warning: false)))
    #expect(sessionEvents.contains(.diagnostic(message: "[untype] STT provider realtime stream connected", warning: false)))
    #expect(sessionEvents.contains(.stateChanged(.listening, reason: nil)))
    #expect(sessionEvents.contains(.ready(message: "[untype] Ready to listen. Press Control-C to stop the listening tool.")))
    #expect(sessionEvents.contains(.audioActivity(AudioActivitySnapshot(
        peak: 0.5,
        byteCount: 4,
        mutedByGate: false
    ))))
    #expect(sessionEvents.contains(.stateChanged(.stopped, reason: "test")))
    #expect(rendered.text.contains("hel\n"))
    #expect(rendered.text.contains("hello\n\n"))
}

@Test func sessionRuntimeSubmitPendingCommitsProviderAndSubmitsBufferedSection() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller
    )

    try await runtime.start()
    await transcriber.emitFinal("pending words")
    try await runtime.submitPending()

    let events = try protocolEvents(protocolOutput.text)
    #expect(transcriber.commitCount == 1)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed"
    ])
    #expect(events[1]["raw_text"] as? String == "pending words")
}

@Test func sessionRuntimeSubmitPendingWaitsForFinalTextFromProviderCommit() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    transcriber.finalAfterCommit = "fresh push to talk text"
    transcriber.finalAfterCommitDelayNanoseconds = 10_000_000
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(finalTranscriptWaitNanoseconds: 250_000_000)
    )

    try await runtime.start()
    try await runtime.submitPending()

    let events = try protocolEvents(protocolOutput.text)
    #expect(transcriber.commitCount == 1)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed"
    ])
    #expect(events[1]["raw_text"] as? String == "fresh push to talk text")
    #expect(rendered.text.contains("fresh push to talk text\n\n"))
}

@Test func sessionRuntimeStopWithSubmitPendingWaitsForFinalAndDoesNotCancelBufferedText() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    transcriber.finalAfterCommit = "released push to talk text"
    transcriber.finalAfterCommitDelayNanoseconds = 10_000_000
    let protocolOutput = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(finalTranscriptWaitNanoseconds: 250_000_000)
    )

    try await runtime.start()
    await runtime.stop(reason: "ui-hotkey-release", submitPending: true)

    let events = try protocolEvents(protocolOutput.text)
    #expect(audio.stopped)
    #expect(transcriber.stopped)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed",
        "session.ended"
    ])
    #expect(events[1]["raw_text"] as? String == "released push to talk text")
    #expect(events[3]["reason"] as? String == "ui-hotkey-release")
}

@Test func sessionRuntimeStopWithSubmitPendingWarnsWhenProviderReturnsNoFinalText() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let protocolOutput = MemoryOutput()
    var sessionEvents: [TranscriptionSessionEvent] = []
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            sttProviderLabel: "soniox",
            finalTranscriptWaitNanoseconds: 1_000_000,
            submissionDiagnosticsEnabled: true,
            emit: { sessionEvents.append($0) }
        )
    )

    try await runtime.start()
    await runtime.stop(reason: "ui-hotkey-release", submitPending: true)

    let events = try protocolEvents(protocolOutput.text)
    #expect(transcriber.commitCount == 1)
    #expect(eventTypes(events) == [
        "session.started",
        "session.ended"
    ])
    #expect(sessionEvents.contains(.diagnostic(
        message: "[untype] WARNING: push-to-talk release did not receive finalized transcript from soniox before timeout; no text was submitted.",
        warning: true
    )))
}

@Test func sessionRuntimeStopWithSubmitPendingFallsBackToLatestPartialWhenFinalNeverArrives() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let protocolOutput = MemoryOutput()
    let rendered = MemoryOutput()
    var sessionEvents: [TranscriptionSessionEvent] = []
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            sttProviderLabel: "soniox",
            finalTranscriptWaitNanoseconds: 1_000_000,
            submissionDiagnosticsEnabled: true,
            emit: { sessionEvents.append($0) }
        )
    )

    try await runtime.start()
    transcriber.emitPartial("latest visible words")
    await runtime.stop(reason: "ui-hotkey-release", submitPending: true)

    let events = try protocolEvents(protocolOutput.text)
    #expect(transcriber.commitCount == 1)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed",
        "session.ended"
    ])
    #expect(events[1]["raw_text"] as? String == "latest visible words")
    #expect(rendered.text.contains("latest visible words\n\n"))
    #expect(sessionEvents.contains(.diagnostic(
        message: "[untype] WARNING: push-to-talk release did not receive finalized transcript from soniox before timeout; submitting latest partial transcript.",
        warning: true
    )))
}

@Test func sessionRuntimeQuickCloseSubmitsLatestPartialWithoutFinalizationWait() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let protocolOutput = MemoryOutput()
    let rendered = MemoryOutput()
    var sessionEvents: [TranscriptionSessionEvent] = []
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            sttProviderLabel: "soniox",
            finalTranscriptWaitNanoseconds: 1_500_000_000,
            quickClose: true,
            submissionDiagnosticsEnabled: true,
            emit: { sessionEvents.append($0) }
        )
    )

    try await runtime.start()
    transcriber.emitPartial("quick close words")
    await runtime.stop(reason: "ui-hotkey-release", submitPending: true)

    let events = try protocolEvents(protocolOutput.text)
    #expect(transcriber.commitCount == 0)
    #expect(eventTypes(events) == [
        "session.started",
        "section.submitted",
        "section.processed",
        "session.ended"
    ])
    #expect(events[1]["raw_text"] as? String == "quick close words")
    #expect(rendered.text.contains("quick close words\n\n"))
    #expect(sessionEvents.contains(.diagnostic(
        message: "[untype] push-to-talk release: Quick Close submitting latest partial transcript",
        warning: false
    )))
}

@Test func sessionRuntimeWritesReleaseLatencyRecordForFocusedInputSuccessWithoutTranscriptText() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let logger = CapturingReleaseLatencyLogger()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: true),
        translationPolicy: .opposite,
        focusedInputWriter: { _ in
            FocusedInputDeliveryResult(
                ok: true,
                method: "ax-value",
                targetRole: "AXTextArea",
                accessibilityTrusted: true,
                focusedElementAvailable: true
            )
        }
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            sttProviderLabel: "soniox",
            releaseLatencyLogger: logger
        )
    )

    try await runtime.start()
    await transcriber.emitFinal("dictated secret words")
    try await runtime.submitPending()

    let records = logger.snapshot()
    #expect(records.count == 1)
    let record = try #require(records.first)
    #expect(record.textSource == "provider_final_already_available")
    #expect(record.outcome == "delivered_to_focused_input")
    #expect(record.sectionsProcessed == 1)
    #expect(record.focusedInput.attempted)
    #expect(record.focusedInput.ok == true)
    #expect(record.focusedInput.method == "ax-value")
    #expect(record.durationsMs.protocolSubmissionMs != nil)
    #expect(record.durationsMs.focusedInputMs != nil)

    let data = try JSONEncoder().encode(record)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("dictated secret words"))
    #expect(!json.contains("processed secret words"))
}

@Test func sessionRuntimeWritesReleaseLatencyRecordForFocusedInputFailure() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let logger = CapturingReleaseLatencyLogger()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: true),
        translationPolicy: .opposite,
        focusedInputWriter: { _ in
            throw FocusedInputDeliveryError(
                message: "Grant Accessibility permission.",
                code: "accessibility_not_trusted"
            )
        }
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            sttProviderLabel: "soniox",
            releaseLatencyLogger: logger
        )
    )

    try await runtime.start()
    await transcriber.emitFinal("private transcript")
    try await runtime.submitPending()

    let record = try #require(logger.snapshot().first)
    #expect(record.outcome == "focused_input_failed")
    #expect(record.focusedInput.attempted)
    #expect(record.focusedInput.ok == false)
    #expect(record.focusedInput.code == "accessibility_not_trusted")
    #expect(record.errorCode == nil)
}

@Test func sessionRuntimeQuickCloseKeepsAlreadyAvailableFinalTextPreferred() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let protocolOutput = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            sttProviderLabel: "soniox",
            quickClose: true,
            submissionDiagnosticsEnabled: true
        )
    )

    try await runtime.start()
    transcriber.emitPartial("partial words")
    await transcriber.emitFinal("final words")
    await runtime.stop(reason: "ui-hotkey-release", submitPending: true)

    let events = try protocolEvents(protocolOutput.text)
    #expect(transcriber.commitCount == 1)
    #expect(events[1]["raw_text"] as? String == "final words")
}

@Test func sessionRuntimeQuickCloseSuppressesLateProviderTextAfterSubmission() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let protocolOutput = MemoryOutput()
    var sessionEvents: [TranscriptionSessionEvent] = []
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            sttProviderLabel: "soniox",
            quickClose: true,
            submissionDiagnosticsEnabled: true,
            emit: { sessionEvents.append($0) }
        )
    )

    try await runtime.start()
    transcriber.emitPartial("first quick close words")
    try await runtime.submitPending()
    transcriber.emitPartial("stale late partial")
    await transcriber.emitFinal("stale late final")
    await runtime.stop(reason: "test-stop", submitPending: false)

    let events = try protocolEvents(protocolOutput.text)
    let submittedText = events
        .filter { $0["type"] as? String == "section.submitted" }
        .compactMap { $0["raw_text"] as? String }
    #expect(submittedText == ["first quick close words"])
    #expect(!sessionEvents.contains(.diagnostic(message: "stale late partial", warning: false)))
}

@Test func sessionRuntimeSuppressesLatePartialsAfterFallbackSubmission() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    transcriber.partialAfterCommit = "stale late partial"
    transcriber.partialAfterCommitDelayNanoseconds = 5_000_000
    let rendered = MemoryOutput()
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            sttProviderLabel: "soniox",
            finalTranscriptWaitNanoseconds: 1_000_000,
            submissionDiagnosticsEnabled: true
        )
    )

    try await runtime.start()
    transcriber.emitPartial("latest visible words")
    await runtime.stop(reason: "ui-hotkey-release", submitPending: true)
    try await Task.sleep(nanoseconds: 10_000_000)

    #expect(rendered.text.contains("latest visible words\n\n"))
    #expect(!rendered.text.contains("stale late partial"))
}

@Test func sessionRuntimeCommitsProviderWhenPartialContainsVoiceCommand() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller
    )

    try await runtime.start()
    transcriber.emitPartial("draft words command send")
    await waitUntil { transcriber.commitCount == 1 }
    transcriber.emitPartial("draft words command send")
    try await Task.sleep(nanoseconds: 10_000_000)

    #expect(transcriber.commitCount == 1)
}

@Test func sessionRuntimeDoesNotCommitProviderForIncompleteStateCommandPartial() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller
    )

    try await runtime.start()
    transcriber.emitPartial("command")
    try await Task.sleep(nanoseconds: 10_000_000)

    #expect(transcriber.commitCount == 0)
}

@Test func sessionRuntimeSendsSilenceWhileAudioGateIsClosed() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let gate = MockAudioGate()
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: nil,
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(audioGate: gate)
    )

    try await runtime.start()
    gate.close()
    await audio.emitAudio(Data([0x01, 0x02, 0x03]))
    gate.open()
    await audio.emitAudio(Data([0x04, 0x05]))
    await runtime.stop(reason: "test")

    #expect(transcriber.pushedAudio == [
        Data([0x00, 0x00, 0x00]),
        Data([0x04, 0x05])
    ])
}

@Test func sessionRuntimeReportsMutedAudioActivityWhenGateIsClosed() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let gate = MockAudioGate()
    var sessionEvents: [TranscriptionSessionEvent] = []
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: nil,
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            audioGate: gate,
            emit: { sessionEvents.append($0) }
        )
    )

    try await runtime.start()
    gate.close()
    await audio.emitAudio(Data([0x00, 0x40]))

    #expect(sessionEvents.contains(.audioActivity(AudioActivitySnapshot(
        peak: 0.5,
        byteCount: 2,
        mutedByGate: true
    ))))
}

@Test func sessionRuntimeThrottlesRepeatedAudioActivityButEmitsCategoryChanges() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let gate = MockAudioGate()
    let clock = ManualClock(Date(timeIntervalSince1970: 0))
    var sessionEvents: [TranscriptionSessionEvent] = []
    let controller = VoiceAgentProtocolController(
        mode: .dictation,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: nil,
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(
            audioGate: gate,
            audioActivityInterval: 1,
            audioActivityNow: { clock.current },
            emit: { sessionEvents.append($0) }
        )
    )

    try await runtime.start()
    await audio.emitAudio(Data([0x00, 0x40]))
    await audio.emitAudio(Data([0x00, 0x40]))
    clock.advance(by: 1.1)
    await audio.emitAudio(Data([0x00, 0x40]))
    gate.close()
    await audio.emitAudio(Data([0x00, 0x40]))

    let audioEvents = sessionEvents.compactMap { event -> AudioActivitySnapshot? in
        if case .audioActivity(let snapshot) = event {
            return snapshot
        }
        return nil
    }
    #expect(audioEvents == [
        AudioActivitySnapshot(peak: 0.5, byteCount: 2, mutedByGate: false),
        AudioActivitySnapshot(peak: 0.5, byteCount: 2, mutedByGate: false),
        AudioActivitySnapshot(peak: 0.5, byteCount: 2, mutedByGate: true)
    ])
}

@Test func sessionRuntimeRecordsAudioPushFailureAndStops() async throws {
    let audio = MockAudioSource()
    let transcriber = MockTranscriber()
    let rendered = MemoryOutput()
    let protocolOutput = MemoryOutput()
    var sessionEvents: [TranscriptionSessionEvent] = []
    transcriber.pushError = TestRuntimeError("push failed")
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: rendered, mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: runtimeMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let runtime = TranscriptionSessionRuntime(
        audioSource: audio,
        transcriber: transcriber,
        protocolController: controller,
        options: TranscriptionSessionRuntimeOptions(emit: { sessionEvents.append($0) })
    )

    try await runtime.start()
    await audio.emitAudio(Data([0x01]))

    #expect((runtime.recordedFailure() as? TestRuntimeError)?.message == "push failed")
    #expect(audio.stopped)
    #expect(transcriber.stopped)
    #expect(sessionEvents.contains(.stateChanged(.stopped, reason: "audio-push-error")))
}

private final class CapturingReleaseLatencyLogger: ReleaseLatencyLogWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [ReleaseLatencyLogRecord] = []

    func append(_ record: ReleaseLatencyLogRecord) throws {
        lock.lock()
        records.append(record)
        lock.unlock()
    }

    func snapshot() -> [ReleaseLatencyLogRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}

private final class MockAudioSource: RuntimeAudioSource {
    private var handlers: AudioSourceEventHandlers?
    var started = false
    var stopped = false

    func start(handlers: AudioSourceEventHandlers) async throws {
        self.handlers = handlers
        started = true
    }

    func stop() async throws {
        stopped = true
    }

    func emitAudio(_ data: Data) async {
        await handlers?.audio(data)
    }
}

private final class MockTranscriber: RuntimeTranscriber, @unchecked Sendable {
    private var handlers: TranscriberEventHandlers?
    var started = false
    var stopped = false
    var commitCount = 0
    var pushedAudio: [Data] = []
    var pushError: Error?
    var finalAfterCommit: String?
    var finalAfterCommitDelayNanoseconds: UInt64 = 0
    var partialAfterCommit: String?
    var partialAfterCommitDelayNanoseconds: UInt64 = 0

    func setHandlers(_ handlers: TranscriberEventHandlers) {
        self.handlers = handlers
    }

    func start() async throws {
        started = true
    }

    func pushAudio(_ pcm: Data) async throws {
        if let pushError {
            throw pushError
        }
        pushedAudio.append(pcm)
    }

    func commit() async throws {
        commitCount += 1
        if let finalAfterCommit {
            let delay = finalAfterCommitDelayNanoseconds
            Task { [weak self] in
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                await self?.emitFinal(finalAfterCommit)
            }
        }
        if let partialAfterCommit {
            let delay = partialAfterCommitDelayNanoseconds
            Task { [weak self] in
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                self?.emitPartial(partialAfterCommit)
            }
        }
    }

    func stop() async throws {
        stopped = true
    }

    func emitPartial(_ text: String) {
        handlers?.partial(text)
    }

    func emitFinal(_ text: String) async {
        await handlers?.final(text)
    }
}

private final class MockAudioGate: RuntimeAudioGate, @unchecked Sendable {
    private let lock = NSLock()
    private var openState = true

    func isOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return openState
    }

    func open() {
        lock.lock()
        openState = true
        lock.unlock()
    }

    func close() {
        lock.lock()
        openState = false
        lock.unlock()
    }
}

private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var current: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private struct TestRuntimeError: Error, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
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

private func waitUntil(
    timeoutNanoseconds: UInt64 = 250_000_000,
    _ condition: @escaping () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}
