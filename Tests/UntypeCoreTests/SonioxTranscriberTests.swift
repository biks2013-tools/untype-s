import Foundation
import Testing
@testable import UntypeCore

@Test func sonioxTranscriberStartSendsConfigFrameWithLanguageHints() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket, languages: ["el", "en"])

    try await transcriber.start()

    #expect(socket.connected)
    #expect(socket.sentTexts.count == 1)
    let config = try jsonObject(socket.sentTexts[0])
    #expect(config["api_key"] as? String == "test-key")
    #expect(config["model"] as? String == "stt-rt-v4")
    #expect(config["audio_format"] as? String == "pcm_s16le")
    #expect(config["sample_rate"] as? Int == 16_000)
    #expect(config["num_channels"] as? Int == 1)
    #expect(config["enable_endpoint_detection"] as? Bool == true)
    #expect(config["language_hints"] as? [String] == ["el", "en"])
    #expect(config["enable_language_identification"] == nil)
}

@Test func sonioxTranscriberStartSendsLanguageIdentificationForAutoLanguage() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket, languages: ["auto"])

    try await transcriber.start()

    let config = try jsonObject(socket.sentTexts[0])
    #expect(config["enable_language_identification"] as? Bool == true)
    #expect(config["language_hints"] == nil)
}

@Test func sonioxTranscriberStartSendsConfiguredContextText() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(
        socket: socket,
        transcriptionContext: "This session is about Swift package maintenance."
    )

    try await transcriber.start()

    let config = try jsonObject(socket.sentTexts[0])
    let context = try #require(config["context"] as? [String: Any])
    #expect(context["text"] as? String == "This session is about Swift package maintenance.")
}

@Test func sonioxTranscriberConvenienceInitializerRejectsInvalidEndpoint() {
    #expect(throws: UntypeError.self) {
        _ = try SonioxTranscriber(options: SonioxTranscriberOptions(
            apiKey: "test-key",
            model: "stt-rt-v4",
            endpoint: "https://example.com",
            languages: ["en"],
            sampleRate: 16_000,
            enableEndpointDetection: true
        ))
    }
}

@Test func sonioxTranscriberPushAudioOnlyWhenConnected() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket)

    try await transcriber.pushAudio(Data([0x00]))
    try await transcriber.start()
    try await transcriber.pushAudio(Data([0x01, 0x02]))

    #expect(socket.sentBinaries == [Data([0x01, 0x02])])
}

@Test func sonioxTranscriberFiltersMarkerTokens() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket)
    var partials: [String] = []
    var finals: [String] = []
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { partials.append($0) },
        final: { finals.append($0) },
        error: { _ in }
    ))

    try await transcriber.start()
    await transcriber.handleTextFrame(#"{"tokens":[{"text":"<end>","is_final":true},{"text":"<fin>","is_final":false}]}"#)
    await transcriber.handleTextFrame(#"{"type":"endpoint"}"#)

    #expect(partials.isEmpty)
    #expect(finals.isEmpty)
}

@Test func sonioxTranscriberAccumulatesPartialsAndCommitsOnEndpoint() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket)
    var partials: [String] = []
    var finals: [String] = []
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { partials.append($0) },
        final: { finals.append($0) },
        error: { _ in }
    ))

    try await transcriber.start()
    await transcriber.handleTextFrame(#"{"tokens":[{"text":"hi ","is_final":false}]}"#)
    await transcriber.handleTextFrame(#"{"tokens":[{"text":"hi ","is_final":true},{"text":"there","is_final":false}]}"#)
    await transcriber.handleTextFrame(#"{"type":"endpoint"}"#)

    #expect(partials == ["hi ", "hi there"])
    #expect(finals == ["hi"])
}

@Test func sonioxTranscriberCommitsTokensOnCombinedFinalizedFrame() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket)
    var partials: [String] = []
    var finals: [String] = []
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { partials.append($0) },
        final: { finals.append($0) },
        error: { _ in }
    ))

    try await transcriber.start()
    await transcriber.handleTextFrame(#"{"type":"finalized","tokens":[{"text":"final text","is_final":true}]}"#)

    #expect(partials == ["final text"])
    #expect(finals == ["final text"])
}

@Test func sonioxTranscriberDoesNotDuplicateRepeatedFinalPrefixes() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket)
    var partials: [String] = []
    var finals: [String] = []
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { partials.append($0) },
        final: { finals.append($0) },
        error: { _ in }
    ))

    try await transcriber.start()
    await transcriber.handleTextFrame(#"{"tokens":[{"text":"Εσύ ","is_final":true},{"text":"ρε","is_final":false}]}"#)
    await transcriber.handleTextFrame(#"{"tokens":[{"text":"Εσύ ","is_final":true},{"text":"ρε","is_final":false}]}"#)
    await transcriber.handleTextFrame(#"{"tokens":[{"text":"Εσύ ρε παιδί μου","is_final":true}]}"#)
    await transcriber.handleTextFrame(#"{"type":"endpoint"}"#)

    #expect(partials == ["Εσύ ρε", "Εσύ ρε", "Εσύ ρε παιδί μου"])
    #expect(!partials.joined(separator: "\n").contains("Εσύ Εσύ"))
    #expect(finals == ["Εσύ ρε παιδί μου"])
}

@Test func sonioxTranscriberCommitAndStopSendFinalizeAndFinishFrames() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket)

    try await transcriber.start()
    try await transcriber.commit()
    try await transcriber.stop()
    try await transcriber.stop()

    #expect(socket.sentTexts.contains(#"{"type":"finalize"}"#))
    #expect(socket.sentTexts.last == "")
    #expect(socket.closeCount == 1)
    #expect(socket.sentTexts.filter { $0 == "" }.count == 1)
}

@Test func sonioxTranscriberMapsServerAuthErrorsToTypedError() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket)
    var errors: [UntypeError] = []
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { _ in },
        final: { _ in },
        error: { error in
            if let error = error as? UntypeError {
                errors.append(error)
            }
        }
    ))

    try await transcriber.start()
    await transcriber.handleTextFrame(#"{"type":"error","error_type":"auth_error","message":"bad key"}"#)

    #expect(errors == [.sonioxAuth("Soniox authentication failed: bad key")])
}

@Test func sonioxTranscriberMapsConnectFailuresToNetworkError() async {
    let socket = MockRealtimeWebSocket()
    socket.connectError = TestSonioxSocketError()
    let transcriber = makeSonioxTranscriber(socket: socket)

    await #expect(throws: UntypeError.self) {
        try await transcriber.start()
    }
}

@Test func sonioxTranscriberRoutesSocketReceiveFramesAndErrors() async throws {
    let socket = MockRealtimeWebSocket()
    let transcriber = makeSonioxTranscriber(socket: socket)
    var partials: [String] = []
    var errors: [UntypeError] = []
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { partials.append($0) },
        final: { _ in },
        error: { error in
            if let error = error as? UntypeError {
                errors.append(error)
            }
        }
    ))

    try await transcriber.start()
    await socket.handlers.text(#"{"tokens":[{"text":"socket text","is_final":false}]}"#)
    await socket.handlers.error(TestSonioxSocketError())

    #expect(partials == ["socket text"])
    #expect(errors.count == 1)
    #expect(errors.first?.code == "soniox_network")
    #expect(errors.first?.message.hasPrefix("Soniox WebSocket receive failed:") == true)
}

private func makeSonioxTranscriber(
    socket: MockRealtimeWebSocket,
    languages: [String] = ["en"],
    transcriptionContext: String? = nil
) -> SonioxTranscriber {
    SonioxTranscriber(
        options: SonioxTranscriberOptions(
            apiKey: "test-key",
            model: "stt-rt-v4",
            endpoint: "wss://stt-rt.soniox.com/transcribe-websocket",
            languages: languages,
            sampleRate: 16_000,
            enableEndpointDetection: true,
            transcriptionContext: transcriptionContext,
            finalizeDrainNanoseconds: 0
        ),
        socket: socket
    )
}

private final class MockRealtimeWebSocket: RealtimeWebSocketClient {
    var handlers = RealtimeWebSocketHandlers()
    var connected = false
    var connectError: Error?
    var sentTexts: [String] = []
    var sentBinaries: [Data] = []
    var closeCount = 0

    func setHandlers(_ handlers: RealtimeWebSocketHandlers) {
        self.handlers = handlers
    }

    func connect() async throws {
        if let connectError {
            throw connectError
        }
        connected = true
    }

    func sendText(_ text: String) async throws {
        sentTexts.append(text)
    }

    func sendBinary(_ data: Data) async throws {
        sentBinaries.append(data)
    }

    func close() {
        closeCount += 1
    }
}

private struct TestSonioxSocketError: Error {}

private func jsonObject(_ text: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
    return object as? [String: Any] ?? [:]
}
