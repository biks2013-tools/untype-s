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

private func piece(_ text: String, _ speaker: String?, _ level: Double? = nil, start: Int? = nil, fromSample: Bool = false) -> VoiceFilterToken {
    VoiceFilterToken(text: text, speaker: speaker, levelDb: level, startMs: start, fromSample: fromSample)
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

/// A sample of one second and its 200 ms of silence: the user's audio starts at 1200 ms.
private let sample = VoiceSample(pcm: tone(0.1, ms: 1_000), sampleRate: 16_000)

@Test func theSpeakerOfTheVoiceSampleIsKeptAndTheOthersDropped() {
    var filter = UserSpeakerFilter(mode: .filter(sample: sample))
    let lead = [piece(" my", "2", start: 100, fromSample: true), piece(" voice", "2", start: 500, fromSample: true)]
    // Two people at the same loudness: only the label tells them apart.
    let tokens = [
        piece(" Send", "2", -26, start: 1_300), piece(" the", "2", -27, start: 1_500), piece(" report", "2", -25, start: 1_700), piece(".", "2", start: 1_900),
        piece(" Did", "1", -26, start: 2_100), piece(" you", "1", -25, start: 2_300), piece(" see", "1", -27, start: 2_500),
        piece(" today", "2", -26, start: 2_800)
    ]
    (lead + tokens).forEach { filter.record($0) }
    #expect(filter.userSpeaker() == "2")
    #expect(filter.kept(lead + tokens).map(\.text).joined() == " Send the report. today")
    let summary = filter.summary(of: lead + tokens)
    #expect(summary?.contains("4 words kept, 3 dropped") == true)
    #expect(summary?.contains("speaker 2 (you) at -26 dB kept") == true)
    #expect(summary?.contains("Did") == false)
    // The sample alone is not an utterance.
    #expect(filter.summary(of: lead) == nil)
}

@Test func theSampleInProgressAlreadyNamesTheUser() {
    let filter = UserSpeakerFilter(mode: .filter(sample: sample))
    let pending = [piece(" my", "1", start: 100, fromSample: true), piece(" hello", "1", start: 1_300), piece(" over", "2", start: 1_600)]
    #expect(filter.kept([], pending: pending).map(\.text) == [" hello"])
    // A piece without a speaker label is kept.
    #expect(filter.kept([], pending: pending + [piece(" hi", nil, start: 1_900)]).count == 2)
}

@Test func nothingIsDroppedWhileTheSampleWasNotRecognised() {
    var filter = UserSpeakerFilter(mode: .filter(sample: sample))
    let tokens = [piece(" one", "1", start: 1_300), piece(" two", "2", start: 1_600)]
    tokens.forEach { filter.record($0) }
    #expect(filter.userSpeaker() == nil)
    #expect(filter.kept(tokens).count == 2)
    #expect(filter.summary(of: tokens)?.contains("was not recognised") == true)
}

@Test func learningTakesTheSpeakerWhoSaysTheMostAsTheUser() throws {
    var filter = UserSpeakerFilter(mode: .learn)
    let tokens = [piece(" one", "2", start: 100), piece(" two", "1", start: 600), piece(" three", "1", start: 900), piece(" four", "1", start: 1_200)]
    tokens.forEach { filter.record($0) }
    #expect(filter.kept(tokens).map(\.text) == [" two", " three", " four"])
    let learned = try #require(filter.learned())
    #expect(learned.words == 3)
    #expect(learned.firstStartMs == 600)
}

@Test func theVoiceSampleSurvivesSavingAndLoading() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("untype-voice-\(UUID().uuidString)").appendingPathComponent("voice-sample.wav")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(try VoiceSampleStore.load(from: url) == nil)
    try VoiceSampleStore.save(sample, to: url)
    #expect(try VoiceSampleStore.load(from: url) == sample)
    #expect(abs(sample.seconds - 1) < 0.001)
    let mode = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
    #expect(mode.intValue == 0o600)
    try Data("not a wav file, but long enough to be looked at closely.".utf8).write(to: url)
    #expect(throws: UntypeError.self) { try VoiceSampleStore.load(from: url) }
}

@Test func sonioxAsksForSpeakersOnlyWhenTheVoiceFilterIsUsed() async throws {
    let plain = VoiceFilterSocket()
    try await makeTranscriber(socket: plain, mode: nil).start()
    #expect(try configOf(plain)["enable_speaker_diarization"] == nil)
    #expect(plain.sentBinaries.isEmpty)

    let filtered = VoiceFilterSocket()
    try await makeTranscriber(socket: filtered, mode: .filter(sample: sample)).start()
    #expect(try configOf(filtered)["enable_speaker_diarization"] as? Bool == true)
}

@Test func sonioxSendsTheVoiceSampleFirstAndFinishesIt() async throws {
    let socket = VoiceFilterSocket()
    try await makeTranscriber(socket: socket, mode: .filter(sample: sample)).start()
    // The sample and 200 ms of silence, then a request to finish it.
    #expect(socket.sentBinaries.count == 1)
    #expect(socket.sentBinaries[0].count == (16_000 + 3_200) * 2)
    #expect(socket.sentBinaries[0].prefix(sample.pcm.count) == sample.pcm)
    #expect(socket.sentTexts.last == #"{"type":"finalize"}"#)

    let other = VoiceFilterSocket()
    let wrongRate = VoiceSample(pcm: sample.pcm, sampleRate: 8_000)
    await #expect(throws: UntypeError.self) {
        try await makeTranscriber(socket: other, mode: .filter(sample: wrongRate)).start()
    }
}

@Test func sonioxDropsTheWordsOfAnotherSpeakerAtTheSameLoudness() async throws {
    let socket = VoiceFilterSocket()
    let transcriber = makeTranscriber(socket: socket, mode: .filter(sample: sample))
    let box = VoiceFilterBox()
    transcriber.onVoiceFilterEvent = { box.events.append($0) }
    transcriber.setHandlers(TranscriberEventHandlers(
        partial: { box.partials.append($0) }, final: { box.finals.append($0) }, error: { _ in }))
    try await transcriber.start()
    // The sample is recognised and finished: nothing is written, nothing logged.
    await transcriber.handleTextFrame(#"{"tokens":[{"text":" my","start_ms":100,"end_ms":400,"speaker":"1","is_final":true},{"text":" voice","start_ms":450,"end_ms":900,"speaker":"1","is_final":true},{"text":".","is_final":true},{"text":"<fin>","is_final":true}]}"#)
    #expect(box.partials.isEmpty && box.finals.isEmpty && box.events.isEmpty)

    // The user, then someone just as loud.
    try await transcriber.pushAudio(tone(0.1, ms: 2_000))
    await transcriber.handleTextFrame(#"{"tokens":[{"text":" Send","start_ms":1300,"end_ms":1600,"speaker":"1","is_final":true},{"text":" it","start_ms":1650,"end_ms":2000,"speaker":"1","is_final":true},{"text":" nice","start_ms":2300,"end_ms":2600,"speaker":"2","is_final":false}]}"#)
    #expect(box.partials.last == " Send it")
    await transcriber.handleTextFrame(#"{"tokens":[{"text":" nice","start_ms":2300,"end_ms":2600,"speaker":"2","is_final":true},{"text":" weather","start_ms":2650,"end_ms":3100,"speaker":"2","is_final":true},{"text":"<end>","is_final":true}]}"#)

    #expect(box.finals == ["Send it"])
    #expect(box.events == [.summary("only my voice: about 2 words kept, 2 dropped (speaker 1 (you) at -20 dB kept; speaker 2 at -20 dB dropped)")])
}

@Test func sonioxReportsASampleOfTheUsersVoiceWhenLearningStops() async throws {
    let socket = VoiceFilterSocket()
    let transcriber = makeTranscriber(socket: socket, mode: .learn)
    let box = VoiceFilterBox()
    transcriber.onVoiceFilterEvent = { box.events.append($0) }
    transcriber.setHandlers(TranscriberEventHandlers(partial: { _ in }, final: { _ in }, error: { _ in }))
    try await transcriber.start()
    #expect(socket.sentBinaries.isEmpty)
    // One second of quiet, then six seconds of speech.
    try await transcriber.pushAudio(tone(0.001, ms: 1_000))
    try await transcriber.pushAudio(tone(0.1, ms: 6_000))
    let tokens = (0..<6).map { #"{"text":" w","start_ms":\#(1_100 + $0 * 300),"end_ms":\#(1_100 + $0 * 300 + 250),"speaker":"1","is_final":true}"# }.joined(separator: ",")
    await transcriber.handleTextFrame("{\"tokens\":[\(tokens)]}")
    try await transcriber.stop()

    guard case .learned(let learned, let words)? = box.events.last else {
        Issue.record("no voice sample was learned")
        return
    }
    #expect(words == 6)
    #expect(learned.sampleRate == 16_000)
    // Four seconds from just before the first word (1100 ms - 100 ms).
    #expect(abs(learned.seconds - 4) < 0.001)
    #expect(learned.pcm == tone(0.1, ms: 4_000))
}

@Test func sonioxDoesNotLearnFromTooLittleSpeech() async throws {
    let socket = VoiceFilterSocket()
    let transcriber = makeTranscriber(socket: socket, mode: .learn)
    let box = VoiceFilterBox()
    transcriber.onVoiceFilterEvent = { box.events.append($0) }
    try await transcriber.start()
    try await transcriber.pushAudio(tone(0.1, ms: 1_500))
    let tokens = (0..<6).map { #"{"text":" w","start_ms":\#($0 * 200),"end_ms":\#($0 * 200 + 150),"speaker":"1","is_final":true}"# }.joined(separator: ",")
    await transcriber.handleTextFrame("{\"tokens\":[\(tokens)]}")
    try await transcriber.stop()
    #expect(box.events.last == .notLearned(words: 6))
}

@Test func voiceFilterPreferencesDefaultToOff() throws {
    #expect(!VoiceFilterPreferences().isOn)
    #expect(UntypeUISettings.default.voiceFilter == VoiceFilterPreferences())
    let merged = try UntypeUISettings.default.merged(UntypeUISettingsPatch(voiceFilter: VoiceFilterPreferences(enabled: true)))
    #expect(merged.voiceFilter.isOn)
    // Settings written before the voice sample existed still load.
    let old = try JSONDecoder().decode(VoiceFilterPreferences.self, from: Data(#"{"enabled":true,"voiceLevelDb":-31.6}"#.utf8))
    #expect(old.isOn)
}

private final class VoiceFilterBox: @unchecked Sendable {
    var partials: [String] = []
    var finals: [String] = []
    var events: [VoiceFilterEvent] = []
}

private final class VoiceFilterSocket: RealtimeWebSocketClient {
    var sentTexts: [String] = []
    var sentBinaries: [Data] = []
    func setHandlers(_ handlers: RealtimeWebSocketHandlers) {}
    func connect() async throws {}
    func sendText(_ text: String) async throws { sentTexts.append(text) }
    func sendBinary(_ data: Data) async throws { sentBinaries.append(data) }
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
