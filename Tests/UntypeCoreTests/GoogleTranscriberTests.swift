import Foundation
import Testing
@testable import UntypeCore

@Test func googleRequestSendsTheKeyInAHeaderNotInTheUrl() throws {
    let request = try GoogleTranscriber.request(options: googleOptions())

    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "google-test")
    #expect(request.url?.absoluteString == STTProvider.google.defaultEndpoint)
    #expect(request.url?.absoluteString.contains("google-test") == false)
}

@Test func googleRequestRejectsAnotherSampleRateAndABadEndpoint() {
    #expect(throws: UntypeError.self) {
        _ = try GoogleTranscriber.request(options: googleOptions(sampleRate: 24_000))
    }
    #expect(throws: UntypeError.self) {
        _ = try GoogleTranscriber.request(options: googleOptions(endpoint: "https://example.com"))
    }
}

@Test func googleStartSendsSetupAndWaitsForTheServerToAcceptIt() async throws {
    let sockets = GoogleSocketFactory()
    let transcriber = makeGoogleTranscriber(sockets: sockets)

    try await transcriber.start()

    let setup = try #require(try googleJson(sockets.all[0].sentTexts[0])["setup"] as? [String: Any])
    #expect(setup["model"] as? String == "models/gemini-3.5-transcribe-live")
    let transcription = try #require(setup["inputAudioTranscription"] as? [String: Any])
    #expect(transcription["languageCodes"] as? [String] == ["el", "en"])
    // Endpoint detection on: the server detects speech itself.
    #expect(setup["realtimeInputConfig"] == nil)
}

@Test func googleSetupOmitsLanguagesForAutoAndDisablesDetectionWhenOff() async throws {
    let sockets = GoogleSocketFactory()
    let transcriber = makeGoogleTranscriber(sockets: sockets, languages: ["auto"], endpointDetection: false)

    try await transcriber.start()

    let setup = try #require(try googleJson(sockets.all[0].sentTexts[0])["setup"] as? [String: Any])
    let transcription = try #require(setup["inputAudioTranscription"] as? [String: Any])
    #expect(transcription["languageCodes"] == nil)
    let input = try #require(setup["realtimeInputConfig"] as? [String: Any])
    #expect((input["automaticActivityDetection"] as? [String: Any])?["disabled"] as? Bool == true)
}

@Test func googleStartFailsWithAnAuthErrorWhenTheServerRefusesTheKey() async throws {
    let sockets = GoogleSocketFactory()
    sockets.refusal = RealtimeWebSocketCloseError(code: 1007, reason: "API key not valid. Please pass a valid API key.")
    let transcriber = makeGoogleTranscriber(sockets: sockets)

    do {
        try await transcriber.start()
        Issue.record("start() should have failed")
    } catch let error as UntypeError {
        #expect(error.code == "google_speech_auth")
        #expect(WarmSessionRecovery.shouldRetryStartup(after: error) == false)
    }
}

@Test func googleStartFailsWithAConfigurationErrorForAnUnknownModel() async throws {
    let sockets = GoogleSocketFactory()
    sockets.refusal = RealtimeWebSocketCloseError(
        code: 1008,
        reason: "models/nope is not found for API version v1beta, or is not supported for bidiGenerateContent."
    )
    let transcriber = makeGoogleTranscriber(sockets: sockets)

    do {
        try await transcriber.start()
        Issue.record("start() should have failed")
    } catch let error as UntypeError {
        #expect(error.exitCode == .configuration)
        #expect(WarmSessionRecovery.shouldRetryStartup(after: error) == false)
    }
}

@Test func googlePushAudioSendsBase64PcmAndCommitEndsTheAudioStream() async throws {
    let sockets = GoogleSocketFactory()
    let transcriber = makeGoogleTranscriber(sockets: sockets)
    try await transcriber.start()

    try await transcriber.pushAudio(Data([1, 2, 3, 4]))
    try await transcriber.commit()

    let socket = sockets.all[0]
    let audio = try #require((try googleJson(socket.sentTexts[1])["realtimeInput"] as? [String: Any])?["audio"] as? [String: Any])
    #expect(audio["data"] as? String == Data([1, 2, 3, 4]).base64EncodedString())
    #expect(audio["mimeType"] as? String == "audio/pcm;rate=16000")
    let end = try #require(try googleJson(socket.sentTexts[2])["realtimeInput"] as? [String: Any])
    #expect(end["audioStreamEnd"] as? Bool == true)
}

@Test func googleMarksSpeechExplicitlyWhenEndpointDetectionIsOff() async throws {
    let sockets = GoogleSocketFactory()
    let transcriber = makeGoogleTranscriber(sockets: sockets, endpointDetection: false)
    try await transcriber.start()

    // Silence (the closed push-to-talk gate) opens nothing.
    try await transcriber.pushAudio(Data(repeating: 0, count: 8))
    try await transcriber.commit()
    try await transcriber.pushAudio(Data([5, 6]))
    try await transcriber.pushAudio(Data([7, 8]))
    try await transcriber.commit()
    try await transcriber.commit()

    let kinds = try sockets.all[0].sentTexts.dropFirst().map(googleFrameKind)
    #expect(kinds == ["audio", "activityStart", "audio", "audio", "activityEnd"])
}

@Test func googleEmitsInterimTextAsPartialsAndFinishedSentencesAsFinals() async throws {
    let sockets = GoogleSocketFactory()
    let transcriber = makeGoogleTranscriber(sockets: sockets)
    let events = GoogleEvents()
    transcriber.setHandlers(events.handlers)
    try await transcriber.start()

    await transcriber.handleTextFrame(#"{"serverContent":{},"voiceActivity":{"type":"ACTIVITY_START","audioOffset":"0.2s"}}"#)
    await transcriber.handleTextFrame(#"{"serverContent":{"interimInputTranscription":{"text":"Καλη"}}}"#)
    await transcriber.handleTextFrame(#"{"serverContent":{"inputTranscription":{"text":" Καλημέρα. "}}}"#)
    await transcriber.handleTextFrame(#"{"serverContent":{"generationComplete":true}}"#)

    #expect(events.partials == ["Καλη"])
    #expect(events.finals == ["Καλημέρα."])
    #expect(events.errors.isEmpty)
}

@Test func googleReportsAClosedStreamOnce() async throws {
    let sockets = GoogleSocketFactory()
    let transcriber = makeGoogleTranscriber(sockets: sockets)
    let events = GoogleEvents()
    transcriber.setHandlers(events.handlers)
    try await transcriber.start()

    let socket = sockets.all[0]
    await socket.handlers.error(RealtimeWebSocketCloseError(code: 1008, reason: "The operation was aborted."))
    await socket.handlers.closed()
    try await transcriber.pushAudio(Data([1, 2]))

    #expect(events.errors.map(\.code) == ["google_speech_network"])
    // Nothing is sent to a connection that is gone.
    #expect(socket.sentTexts.count == 1)
}

@Test func googleReplacesAnAgingConnectionAtAQuietMoment() async throws {
    let sockets = GoogleSocketFactory()
    let clock = GoogleClock()
    let transcriber = makeGoogleTranscriber(sockets: sockets, now: { clock.now })
    let events = GoogleEvents()
    transcriber.setHandlers(events.handlers)
    try await transcriber.start()

    // Speech without a finished sentence yet: not a quiet moment.
    clock.advance(500)
    try await transcriber.pushAudio(Data([1, 2]))
    try await transcriber.pushAudio(Data(repeating: 0, count: 4))
    #expect(sockets.all.count == 1)

    // The sentence is finished: the next silence is a quiet moment.
    await transcriber.handleTextFrame(#"{"serverContent":{"inputTranscription":{"text":"ok"}}}"#)
    try await transcriber.pushAudio(Data(repeating: 0, count: 4))
    try await googleWait { sockets.all.count == 2 && sockets.all[0].closeCount == 1 }

    try await transcriber.pushAudio(Data([9, 9]))
    let second = sockets.all[1]
    #expect(try second.sentTexts.map(googleFrameKind) == ["setup", "audio"])
    // The replaced connection ended without an error for the session.
    await sockets.all[0].handlers.closed()
    #expect(events.errors.isEmpty)
}

@Test func googleReplacesTheConnectionBeforeTheServerLimitEvenDuringSpeech() async throws {
    let sockets = GoogleSocketFactory()
    let clock = GoogleClock()
    let transcriber = makeGoogleTranscriber(sockets: sockets, now: { clock.now })
    try await transcriber.start()

    clock.advance(561)
    try await transcriber.pushAudio(Data([1, 2]))
    try await googleWait { sockets.all.count == 2 && sockets.all[0].closeCount == 1 }

    // The old connection was told the audio ended, so its sentence is finished.
    #expect(try sockets.all[0].sentTexts.map(googleFrameKind).last == "audioStreamEnd")
}

@Test func googleStopEndsTheStreamAndClosesOnce() async throws {
    let sockets = GoogleSocketFactory()
    let transcriber = makeGoogleTranscriber(sockets: sockets)
    try await transcriber.start()

    try await transcriber.stop()
    try await transcriber.stop()

    #expect(try sockets.all[0].sentTexts.map(googleFrameKind) == ["setup", "audioStreamEnd"])
    #expect(sockets.all[0].closeCount == 1)
}

@Test func supersededSpeechModelsGiveWayToTheirSuccessors() {
    #expect(STTProvider.currentModel(for: "stt-rt-v5") == "stt-rt-v6")
    #expect(STTProvider.currentModel(for: "scribe_v2_realtime") == "scribe_v3_live")
    #expect(STTProvider.currentModel(for: "my-own-model") == "my-own-model")
}

@Test func theModelFollowsAProviderChangeUnlessTheUserTypedTheirOwn() {
    #expect(STTProvider.model("stt-rt-v6", movingTo: .google) == "gemini-3.5-transcribe-live")
    #expect(STTProvider.model("stt-rt-v5", movingTo: .elevenlabs) == "scribe_v3_live")
    #expect(STTProvider.model("gemini-3.5-transcribe-live", movingTo: .soniox) == "stt-rt-v6")
    #expect(STTProvider.model("my-own-model", movingTo: .google) == "my-own-model")
}

// MARK: Helpers

private func googleOptions(
    endpoint: String = STTProvider.google.defaultEndpoint,
    languages: [String] = ["el", "en"],
    sampleRate: Int = 16_000,
    endpointDetection: Bool = true
) -> GoogleTranscriberOptions {
    GoogleTranscriberOptions(
        apiKey: "google-test",
        model: "gemini-3.5-transcribe-live",
        endpoint: endpoint,
        languages: languages,
        sampleRate: sampleRate,
        enableEndpointDetection: endpointDetection,
        commitDrainNanoseconds: 0,
        setupTimeoutNanoseconds: 2_000_000_000
    )
}

private func makeGoogleTranscriber(
    sockets: GoogleSocketFactory,
    languages: [String] = ["el", "en"],
    endpointDetection: Bool = true,
    now: @escaping @Sendable () -> Date = Date.init
) -> GoogleTranscriber {
    GoogleTranscriber(
        options: googleOptions(languages: languages, endpointDetection: endpointDetection),
        makeSocket: { sockets.make() },
        now: now
    )
}

private final class GoogleClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000_000)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class GoogleEvents: @unchecked Sendable {
    var partials: [String] = []
    var finals: [String] = []
    var errors: [UntypeError] = []

    var handlers: TranscriberEventHandlers {
        TranscriberEventHandlers(
            partial: { self.partials.append($0) },
            final: { self.finals.append($0) },
            error: { error in
                if let error = error as? UntypeError {
                    self.errors.append(error)
                }
            }
        )
    }
}

private final class GoogleSocketFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [MockGoogleWebSocket] = []
    /// When set, the server closes each new connection with this instead of
    /// accepting its setup.
    var refusal: RealtimeWebSocketCloseError?

    var all: [MockGoogleWebSocket] {
        lock.lock()
        defer { lock.unlock() }
        return sockets
    }

    func make() -> MockGoogleWebSocket {
        let socket = MockGoogleWebSocket(refusal: refusal)
        lock.lock()
        sockets.append(socket)
        lock.unlock()
        return socket
    }
}

/// Accepts the setup frame like the server does (or refuses it).
private final class MockGoogleWebSocket: RealtimeWebSocketClient, @unchecked Sendable {
    private let lock = NSLock()
    private let refusal: RealtimeWebSocketCloseError?
    private var texts: [String] = []
    private var closes = 0
    var handlers = RealtimeWebSocketHandlers()

    init(refusal: RealtimeWebSocketCloseError?) {
        self.refusal = refusal
    }

    var sentTexts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return texts
    }

    var closeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return closes
    }

    func setHandlers(_ handlers: RealtimeWebSocketHandlers) {
        self.handlers = handlers
    }

    func connect() async throws {}

    private func record(_ text: String) {
        lock.lock()
        texts.append(text)
        lock.unlock()
    }

    func sendText(_ text: String) async throws {
        record(text)
        guard text.contains(#""setup""#) else {
            return
        }
        let handlers = self.handlers
        let refusal = self.refusal
        Task {
            if let refusal {
                await handlers.error(refusal)
                await handlers.closed()
            } else {
                await handlers.text(#"{"setupComplete":{}}"#)
            }
        }
    }

    func sendBinary(_ data: Data) async throws {}

    func close() {
        lock.lock()
        closes += 1
        lock.unlock()
    }
}

private func googleJson(_ text: String) throws -> [String: Any] {
    (try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
}

private func googleFrameKind(_ text: String) throws -> String {
    let object = try googleJson(text)
    if object["setup"] != nil {
        return "setup"
    }
    let input = object["realtimeInput"] as? [String: Any] ?? [:]
    return input.keys.sorted().first ?? "unknown"
}

private func googleWait(_ condition: @escaping () -> Bool) async throws {
    for _ in 0..<400 {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("condition not reached in time")
}
