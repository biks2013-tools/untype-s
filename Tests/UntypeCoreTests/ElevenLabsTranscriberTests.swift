import Foundation
import Testing
@testable import UntypeCore

@Test func elevenLabsRequestBuildsRealtimeUrlAndAuthHeader() throws {
    let request = try ElevenLabsTranscriber.request(options: ElevenLabsTranscriberOptions(
        apiKey: "xi-test",
        model: "scribe_v2_realtime",
        endpoint: "wss://api.elevenlabs.io/v1/speech-to-text/realtime",
        languages: ["en"],
        sampleRate: 24_000,
        enableEndpointDetection: true
    ))

    let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect("\(components.scheme!)://\(components.host!)\(components.path)" == "wss://api.elevenlabs.io/v1/speech-to-text/realtime")
    #expect(query["model_id"] == "scribe_v2_realtime")
    #expect(query["audio_format"] == "pcm_24000")
    #expect(query["sample_rate"] == "24000")
    #expect(query["commit_strategy"] == "vad")
    #expect(query["include_timestamps"] == "false")
    #expect(query["language_code"] == "en")
    #expect(request.value(forHTTPHeaderField: "xi-api-key") == "xi-test")
}

@Test func elevenLabsRequestUsesManualCommitAndOmitsAutoLanguage() throws {
    let request = try ElevenLabsTranscriber.request(options: ElevenLabsTranscriberOptions(
        apiKey: "xi-test",
        model: "scribe_v2_realtime",
        endpoint: "wss://api.elevenlabs.io/v1/speech-to-text/realtime",
        languages: ["auto"],
        sampleRate: 16_000,
        enableEndpointDetection: false
    ))

    let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect(query["commit_strategy"] == "manual")
    #expect(query["language_code"] == nil)
}

@Test func elevenLabsRequestAddsConfiguredKeyterms() throws {
    let request = try ElevenLabsTranscriber.request(options: ElevenLabsTranscriberOptions(
        apiKey: "xi-test",
        model: "scribe_v2_realtime",
        endpoint: "wss://api.elevenlabs.io/v1/speech-to-text/realtime",
        languages: ["auto"],
        sampleRate: 16_000,
        enableEndpointDetection: true,
        keyterms: ["Untype", "Swift"]
    ))

    let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
    let keyterms = (components.queryItems ?? [])
        .filter { $0.name == "keyterms" }
        .compactMap(\.value)
    #expect(keyterms == ["Untype", "Swift"])
}

@Test func elevenLabsConvenienceInitializerRejectsInvalidEndpoint() {
    #expect(throws: UntypeError.self) {
        _ = try ElevenLabsTranscriber(options: ElevenLabsTranscriberOptions(
            apiKey: "xi-test",
            model: "scribe_v2_realtime",
            endpoint: "https://example.com",
            languages: ["auto"],
            sampleRate: 16_000,
            enableEndpointDetection: true
        ))
    }
}

@Test func elevenLabsPushAudioSendsBase64InputAudioChunk() async throws {
    let socket = MockElevenLabsWebSocket()
    let transcriber = makeElevenLabsTranscriber(socket: socket)

    try await transcriber.pushAudio(Data([0x00]))
    try await transcriber.start()
    try await transcriber.pushAudio(Data([0x01, 0x02, 0x03]))

    #expect(socket.sentTexts.count == 1)
    let chunk = try elevenLabsJsonObject(socket.sentTexts[0])
    #expect(chunk["message_type"] as? String == "input_audio_chunk")
    #expect(chunk["audio_base_64"] as? String == "AQID")
    #expect(chunk["sample_rate"] as? Int == 16_000)
    #expect(chunk["commit"] == nil)
}

@Test func elevenLabsPushAudioSendsPreviousTextOnlyOnFirstAudioChunk() async throws {
    let socket = MockElevenLabsWebSocket()
    let transcriber = makeElevenLabsTranscriber(socket: socket, previousText: "Swift dictation")

    try await transcriber.start()
    try await transcriber.pushAudio(Data([0x01]))
    try await transcriber.pushAudio(Data([0x02]))
    try await transcriber.commit()

    let first = try elevenLabsJsonObject(socket.sentTexts[0])
    let second = try elevenLabsJsonObject(socket.sentTexts[1])
    let commit = try elevenLabsJsonObject(socket.sentTexts[2])
    #expect(first["previous_text"] as? String == "Swift dictation")
    #expect(second["previous_text"] == nil)
    #expect(commit["previous_text"] == nil)
}

@Test func elevenLabsCommitAndStopSendCommitFrameAndCloseOnce() async throws {
    let socket = MockElevenLabsWebSocket()
    let transcriber = makeElevenLabsTranscriber(socket: socket)

    try await transcriber.start()
    try await transcriber.commit()
    try await transcriber.stop()
    try await transcriber.stop()

    let commitFrames = try socket.sentTexts.map(elevenLabsJsonObject)
        .filter { $0["commit"] as? Bool == true }
    #expect(commitFrames.count == 2)
    #expect(commitFrames.allSatisfy { $0["message_type"] as? String == "input_audio_chunk" })
    #expect(commitFrames.allSatisfy { $0["audio_base_64"] as? String == "" })
    #expect(commitFrames.allSatisfy { $0["sample_rate"] as? Int == 16_000 })
    #expect(socket.closeCount == 1)
}

@Test func elevenLabsEmitsPartialsAndTrimmedFinals() async throws {
    let socket = MockElevenLabsWebSocket()
    let transcriber = makeElevenLabsTranscriber(socket: socket)
    var partials: [String] = []
    var finals: [String] = []
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { partials.append($0) },
        final: { finals.append($0) },
        error: { _ in }
    ))

    try await transcriber.start()
    await transcriber.handleTextFrame(#"{"message_type":"partial_transcript","text":"hel"}"#)
    await transcriber.handleTextFrame(#"{"message_type":"committed_transcript","text":"hello "}"#)
    await transcriber.handleTextFrame(#"{"message_type":"committed_transcript_with_timestamps","text":" world\n"}"#)

    #expect(partials == ["hel"])
    #expect(finals == ["hello", "world"])
}

@Test func elevenLabsMapsServerAuthErrorsToTypedError() async throws {
    let socket = MockElevenLabsWebSocket()
    let transcriber = makeElevenLabsTranscriber(socket: socket)
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
    await transcriber.handleTextFrame(#"{"message_type":"error","error_type":"auth_error","message":"bad key"}"#)

    #expect(errors == [.elevenLabsAuth("ElevenLabs authentication failed: bad key")])
}

@Test func elevenLabsMapsProtocolAndNetworkErrors() async throws {
    let socket = MockElevenLabsWebSocket()
    let transcriber = makeElevenLabsTranscriber(socket: socket)
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
    await transcriber.handleTextFrame("not json")
    await socket.handlers.error(TestElevenLabsSocketError())

    #expect(errors.count == 2)
    #expect(errors[0].code == "elevenlabs_protocol")
    #expect(errors[1].code == "elevenlabs_network")
}

private func makeElevenLabsTranscriber(
    socket: MockElevenLabsWebSocket,
    previousText: String? = nil
) -> ElevenLabsTranscriber {
    ElevenLabsTranscriber(
        options: ElevenLabsTranscriberOptions(
            apiKey: "xi-test",
            model: "scribe_v2_realtime",
            endpoint: "wss://api.elevenlabs.io/v1/speech-to-text/realtime",
            languages: ["auto"],
            sampleRate: 16_000,
            enableEndpointDetection: true,
            previousText: previousText,
            commitDrainNanoseconds: 0
        ),
        socket: socket
    )
}

private final class MockElevenLabsWebSocket: RealtimeWebSocketClient {
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

private struct TestElevenLabsSocketError: Error {}

private func elevenLabsJsonObject(_ text: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
    return object as? [String: Any] ?? [:]
}
