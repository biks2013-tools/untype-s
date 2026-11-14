import Foundation
import Testing
@testable import UntypeCore

/// 16 kHz PCM16 of a constant amplitude (0...1) for `ms` milliseconds.
private func tone(_ amplitude: Double, ms: Int) -> Data {
    var data = Data()
    for index in 0..<(16 * ms) {
        let value = Int16((index % 2 == 0 ? 1.0 : -1.0) * amplitude * 32767)
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}

private func piece(_ text: String, _ speaker: String?, _ level: Double?) -> VoiceFilterToken {
    VoiceFilterToken(text: text, speaker: speaker, levelDb: level)
}

@Test func levelMeterMeasuresTheAudioBetweenTwoStreamTimes() throws {
    var meter = StreamLevelMeter(sampleRate: 16_000)
    meter.append(tone(0.1, ms: 1_000))     // -20 dBFS
    meter.append(tone(0.01, ms: 1_000))    // -40 dBFS
    let loud = try #require(meter.levelDb(fromMs: 200, toMs: 800))
    let quiet = try #require(meter.levelDb(fromMs: 1_200, toMs: 1_800))
    #expect(abs(loud - -20) < 0.5)
    #expect(abs(quiet - -40) < 0.5)
    #expect(meter.levelDb(fromMs: 5_000, toMs: 5_200) == nil)
    #expect(meter.levelDb(fromMs: 300, toMs: 300) == nil)
}

@Test func speakersAboutAsLoudAsTheUserAreKeptAndQuieterOnesDropped() {
    var filter = SpeakerLevelFilter(mode: .filter(userLevelDb: -23))
    let tokens = [
        piece(" Send", "1", -22), piece(" the", "1", -27), piece(" report", "1", -21), piece(".", "1", nil),
        piece(" Did", "2", -44), piece(" you", "2", -41), piece(" see", "2", -46),
        piece(" today", "1", -24)
    ]
    tokens.forEach { filter.record($0) }
    #expect(filter.kept(tokens).map(\.text).joined() == " Send the report. today")
    // One quiet word of the user does not get them dropped: the speaker is judged, not the word.
    filter.record(piece(" please", "1", -37))
    #expect(filter.kept([piece(" please", "1", -37)]).count == 1)
    let summary = filter.summary(of: tokens)
    #expect(summary?.contains("3 dropped") == true)
    #expect(summary?.contains("Did") == false)
}

@Test func piecesStillBeingRecognisedCountTowardTheirSpeaker() {
    let filter = SpeakerLevelFilter(mode: .filter(userLevelDb: -23))
    let pending = [piece(" hello", "1", -24), piece(" over", "2", -45), piece(" there", "2", -43)]
    #expect(filter.kept([], pending: pending).map(\.text) == [" hello"])
    // A speaker that was not measured, or has no label, is kept.
    #expect(filter.kept([], pending: [piece(" hi", nil, -50), piece("?", "3", nil)]).count == 2)
}

@Test func learningTakesTheLoudestSpeakerAsTheUser() throws {
    var filter = SpeakerLevelFilter(mode: .learn)
    let tokens = [piece(" one", "2", -40), piece(" two", "1", -24), piece(" three", "1", -22), piece(" four", "1", -26)]
    tokens.forEach { filter.record($0) }
    #expect(filter.kept(tokens).map(\.text) == [" two", " three", " four"])
    let learned = try #require(filter.learned())
    #expect(learned.levelDb == -24)
    #expect(learned.words == 3)
}

@Test func sonioxAsksForSpeakersOnlyWhenTheVoiceFilterIsUsed() async throws {
    let plain = VoiceFilterSocket()
    try await makeTranscriber(socket: plain, mode: nil).start()
    #expect(try configOf(plain)["enable_speaker_diarization"] == nil)

    let filtered = VoiceFilterSocket()
    try await makeTranscriber(socket: filtered, mode: .filter(userLevelDb: -20)).start()
    #expect(try configOf(filtered)["enable_speaker_diarization"] as? Bool == true)
}

@Test func sonioxDropsTheWordsOfAQuieterSpeaker() async throws {
    let socket = VoiceFilterSocket()
    let transcriber = makeTranscriber(socket: socket, mode: .filter(userLevelDb: -20))
    let box = VoiceFilterBox()
    transcriber.onVoiceFilterEvent = { box.events.append($0) }
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { box.partials.append($0) }, final: { box.finals.append($0) }, error: { _ in }))
    try await transcriber.start()
    // The user for one second, then someone 20 dB quieter for one second.
    try await transcriber.pushAudio(tone(0.1, ms: 1_000))
    try await transcriber.pushAudio(tone(0.01, ms: 1_000))

    await transcriber.handleTextFrame(#"{"tokens":[{"text":" Send","start_ms":100,"end_ms":400,"speaker":"1","is_final":true},{"text":" it","start_ms":450,"end_ms":800,"speaker":"1","is_final":true},{"text":" nice","start_ms":1100,"end_ms":1400,"speaker":"2","is_final":false}]}"#)
    #expect(box.partials.last == " Send it")
    await transcriber.handleTextFrame(#"{"tokens":[{"text":" nice","start_ms":1100,"end_ms":1400,"speaker":"2","is_final":true},{"text":" weather","start_ms":1450,"end_ms":1900,"speaker":"2","is_final":true},{"text":"<end>","is_final":true}]}"#)

    #expect(box.finals == ["Send it"])
    #expect(box.events.count == 1)
}

@Test func sonioxReportsTheLearnedVoiceLevelWhenTheStreamStops() async throws {
    let socket = VoiceFilterSocket()
    let transcriber = makeTranscriber(socket: socket, mode: .learn)
    let box = VoiceFilterBox()
    transcriber.onVoiceFilterEvent = { box.events.append($0) }
    transcriber.setHandlers(TranscriberEventHandlers(partial: { _ in }, final: { _ in }, error: { _ in }))
    try await transcriber.start()
    try await transcriber.pushAudio(tone(0.1, ms: 2_000))
    let tokens = (0..<6).map { #"{"text":" w","start_ms":\#($0 * 300),"end_ms":\#($0 * 300 + 250),"speaker":"1","is_final":true}"# }.joined(separator: ",")
    await transcriber.handleTextFrame("{\"tokens\":[\(tokens)]}")
    try await transcriber.stop()

    guard case .learned(let level, let words)? = box.events.last else {
        Issue.record("no level was learned")
        return
    }
    #expect(abs(level - -20) < 0.5)
    #expect(words == 6)
}

@Test func voiceFilterPreferencesDefaultToOff() throws {
    #expect(!VoiceFilterPreferences().isOn)
    #expect(UntypeUISettings.default.voiceFilter == VoiceFilterPreferences())
    let merged = try UntypeUISettings.default.merged(UntypeUISettingsPatch(voiceFilter: VoiceFilterPreferences(enabled: true, voiceLevelDb: -23.1)))
    #expect(merged.voiceFilter.isOn && merged.voiceFilter.voiceLevelDb == -23.1)
}

private final class VoiceFilterBox: @unchecked Sendable {
    var partials: [String] = []
    var finals: [String] = []
    var events: [VoiceFilterEvent] = []
}

private final class VoiceFilterSocket: RealtimeWebSocketClient {
    var sentTexts: [String] = []
    func setHandlers(_ handlers: RealtimeWebSocketHandlers) {}
    func connect() async throws {}
    func sendText(_ text: String) async throws { sentTexts.append(text) }
    func sendBinary(_ data: Data) async throws {}
    func close() {}
}

private func makeTranscriber(socket: VoiceFilterSocket, mode: SonioxVoiceFilterMode?) -> SonioxTranscriber {
    SonioxTranscriber(options: SonioxTranscriberOptions(
        apiKey: "test-key", model: "stt-rt-v6", endpoint: STTProvider.soniox.defaultEndpoint, languages: ["el", "en"],
        sampleRate: 16_000, enableEndpointDetection: true, finalizeDrainNanoseconds: 0, voiceFilter: mode), socket: socket)
}

private func configOf(_ socket: VoiceFilterSocket) throws -> [String: Any] {
    (try JSONSerialization.jsonObject(with: Data(socket.sentTexts[0].utf8)) as? [String: Any]) ?? [:]
}
