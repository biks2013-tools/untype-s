import Foundation
import Testing
@testable import UntypeCore

private final class PCMBox: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = []
    func add(_ pcm: Data) { lock.lock(); chunks.append(pcm); lock.unlock() }
    var all: [Data] { lock.lock(); defer { lock.unlock() }; return chunks }
}

private func pcm(_ samples: [Int16]) -> Data {
    samples.withUnsafeBufferPointer { Data(buffer: $0) }
}

private func samples(_ data: Data) -> [Int16] {
    data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
}

@Test func echoCancellationIsOffByDefaultAndStored() throws {
    #expect(!MeetingPreferences().removesSpeakerSound)
    let old = try JSONDecoder().decode(MeetingPreferences.self, from: Data(#"{"language":"en","silenceMinutes":3}"#.utf8))
    #expect(old.echoCancellation == nil && !old.removesSpeakerSound)
    var meeting = MeetingPreferences()
    meeting.echoCancellation = true
    let stored = try JSONDecoder().decode(MeetingPreferences.self, from: try JSONEncoder().encode(meeting))
    #expect(stored.removesSpeakerSound)
}

@Test func sharedMicrophoneOnlyTakesListenersWhileActive() {
    let shared = MeetingSharedMicrophone()
    #expect(!shared.isActive)
    #expect(shared.subscribe { _ in } == nil)
    shared.setActive(true)
    #expect(shared.subscribe { _ in } != nil)
}

@Test func sharedMicrophoneDeliversToListenersUntilReleased() {
    let shared = MeetingSharedMicrophone()
    shared.setActive(true)
    let heard = PCMBox()
    let id = shared.subscribe { heard.add($0) }
    shared.publish(pcm([1, 2]))
    shared.setActive(false)
    shared.publish(pcm([3, 4]))
    shared.setActive(true)
    if let id { shared.unsubscribe(id) }
    shared.publish(pcm([5, 6]))
    #expect(heard.all == [pcm([1, 2])])
}

@Test func dictationSourceHearsTheSharedMicrophone() async throws {
    let shared = MeetingSharedMicrophone()
    shared.setActive(true)
    let heard = PCMBox()
    let source = SharedMicrophoneAudioSource(shared: shared, sampleRate: MeetingRecorder.sampleRate)
    try await source.start(handlers: AudioSourceEventHandlers(audio: { heard.add($0) }, error: { _ in }, end: {}))
    shared.publish(pcm([7, 8, 9]))
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(heard.all == [pcm([7, 8, 9])])
    try await source.stop()
    shared.publish(pcm([1]))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(heard.all.count == 1)
}

@Test func dictationSourceCannotStartWhenTheMicrophoneIsNotShared() async {
    let source = SharedMicrophoneAudioSource(shared: MeetingSharedMicrophone(), sampleRate: 16_000)
    await #expect(throws: UntypeError.self) {
        try await source.start(handlers: AudioSourceEventHandlers(audio: { _ in }, error: { _ in }, end: {}))
    }
}

@Test func sharedMicrophoneAudioIsResampledToTheSessionRate() {
    let input = pcm([0, 100, 200, 300])
    #expect(SharedMicrophoneAudioSource.resample(input, from: 16_000, to: 16_000) == input)
    #expect(samples(SharedMicrophoneAudioSource.resample(input, from: 16_000, to: 8_000)) == [0, 200])
    #expect(samples(SharedMicrophoneAudioSource.resample(input, from: 16_000, to: 32_000)) == [0, 50, 100, 150, 200, 250, 300, 300])
    #expect(SharedMicrophoneAudioSource.resample(Data(), from: 16_000, to: 8_000).isEmpty)
}
