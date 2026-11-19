@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import UntypeCore

// Live checks with the real capture paths (ScreenCaptureKit and the
// microphone): the saved meeting audio's alignment (plan-072 step 2) and the
// echo cancellation in real time (step 4). They speak a sentence through
// the loudspeakers with `say`, so they run only when asked:
//
//   UNTYPE_LIVE_AUDIO=1 swift test --filter MeetingAudioLive
//
// Needs Screen Recording and Microphone permission for the terminal, the
// built-in loudspeakers (no headphones), and no call in progress.

private let liveAudio = ProcessInfo.processInfo.environment["UNTYPE_LIVE_AUDIO"] == "1"

private final class HeldDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [(Data, TimeInterval)] = []
    private var released = false
    let until: TimeInterval
    let deliver: (Data, TimeInterval) -> Void

    init(until: TimeInterval, deliver: @escaping (Data, TimeInterval) -> Void) {
        self.until = until
        self.deliver = deliver
    }

    /// Holds everything until the clock passes `until`, then delivers it in
    /// one burst: audio arriving late, as ScreenCaptureKit did on 2026-11-19.
    func push(_ pcm: Data, capturedAt: TimeInterval) {
        lock.lock()
        if !released, ProcessInfo.processInfo.systemUptime < until {
            held.append((pcm, capturedAt))
            lock.unlock()
            return
        }
        let burst = released ? [] : held
        released = true
        held = []
        lock.unlock()
        for (chunk, time) in burst {
            deliver(chunk, time)
        }
        deliver(pcm, capturedAt)
    }
}

/// Mean absolute value per millisecond.
private func envelope(of url: URL) throws -> [Double] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let samples = try #require(buffer.floatChannelData?[0])
    let block = Int(format.sampleRate / 1_000)
    return stride(from: 0, to: Int(buffer.frameLength) - block, by: block).map { start in
        (start..<start + block).reduce(0.0) { $0 + abs(Double(samples[$1])) } / Double(block)
    }
}

/// The lag (ms) at which `later` best matches `earlier`, within ±`range` ms,
/// and the normalised correlation there.
private func lag(of later: [Double], behind earlier: [Double], range: Int) -> (ms: Int, correlation: Double) {
    let count = min(later.count, earlier.count)
    func centred(_ values: [Double]) -> [Double] {
        let mean = values[0..<count].reduce(0, +) / Double(count)
        return values[0..<count].map { $0 - mean }
    }
    let a = centred(later)
    let b = centred(earlier)
    let norm = sqrt(a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 }) + 1e-12
    var best = (ms: 0, correlation: -1.0)
    for shift in -range...range {
        var sum = 0.0
        for index in max(0, shift)..<min(count, count + shift) {
            sum += a[index] * b[index - shift]
        }
        if sum / norm > best.correlation {
            best = (shift, sum / norm)
        }
    }
    return best
}

@Test(.enabled(if: liveAudio))
func meetingAudioFilesStayInStepWhenTheCallsAudioArrivesLate() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("untype-live-audio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let start = ProcessInfo.processInfo.systemUptime
    let recorder = try MeetingAudioRecorder(
        folder: folder,
        names: MeetingFileNames(stem: "live"),
        settings: MeetingAudioSettings(sources: .both, layout: .separate),
        sampleRate: 16_000,
        startUptime: start,
        onError: { message in Issue.record("audio error: \(message)") }
    )
    let call = HeldDelivery(until: start + 2.5) { pcm, time in
        recorder.push(pcm, side: .call, capturedAt: time)
    }
    let system = MeetingSystemAudioCapture(sampleRate: 16_000, onPCM: { pcm, time in
        call.push(pcm, capturedAt: time)
    }, onError: { error in Issue.record("system audio: \(error)") })
    try await system.start()
    let microphone = AVFoundationAudioSource(options: AVFoundationAudioSourceOptions(sampleRate: 16_000))
    try await microphone.start(handlers: AudioSourceEventHandlers(
        audio: { _ in Issue.record("the microphone gave audio without a capture time") },
        timedAudio: { pcm, time in recorder.push(pcm, side: .you, capturedAt: time) },
        error: { error in Issue.record("microphone: \(error)") },
        end: {}
    ))

    try await Task.sleep(nanoseconds: 700_000_000)
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-r", "190", "Testing the meeting audio. One, two, three, four, five, six, seven. The quick brown fox jumps over the lazy dog."]
    try say.run()
    say.waitUntilExit()
    try await Task.sleep(nanoseconds: 700_000_000)

    try await microphone.stop()
    await system.stop()
    let urls = recorder.finish()
    let mic = try envelope(of: try #require(urls.first { $0.lastPathComponent == "live.mic.m4a" }))
    let sys = try envelope(of: try #require(urls.first { $0.lastPathComponent == "live.system.m4a" }))

    // The microphone hears the loudspeakers a little after the system audio
    // has them; with arrival-time placement the late burst would put the
    // system audio about 2.5 s behind instead.
    let found = lag(of: mic, behind: sys, range: 3_000)
    print("live audio: microphone behind system audio by \(found.ms) ms (correlation \(String(format: "%.2f", found.correlation)))")
    #expect(found.correlation > 0.3, "the speech was not found in both files")
    #expect(found.ms >= -20 && found.ms <= 200, "microphone behind system audio by \(found.ms) ms")
}

/// The level (dBFS) of PCM16 audio.
private func level(_ samples: ArraySlice<Int16>) -> Double {
    let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count))
    return 10 * log10(power / (32_768 * 32_768) + 1e-12)
}

private final class Timeline: @unchecked Sendable {
    private let lock = NSLock()
    private let start: TimeInterval
    private(set) var samples: [Int16]

    init(start: TimeInterval, seconds: Int) {
        self.start = start
        samples = [Int16](repeating: 0, count: seconds * 16_000)
    }

    /// Puts audio where its capture time says.
    func put(_ pcm: Data, capturedAt: TimeInterval) {
        let chunk = MeetingAudioRecorder.samples(pcm)
        let index = Int(((capturedAt - start) * 16_000).rounded())
        lock.lock()
        for (offset, sample) in chunk.enumerated() where index + offset >= 0 && index + offset < samples.count {
            samples[index + offset] = sample
        }
        lock.unlock()
    }

    var all: [Int16] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

@Test(.enabled(if: liveAudio))
func meetingEchoCancellationRemovesTheLoudspeakersInRealTime() async throws {
    let start = ProcessInfo.processInfo.systemUptime
    let raw = Timeline(start: start, seconds: 30)
    let cleaned = Timeline(start: start, seconds: 30)
    let call = Timeline(start: start, seconds: 30)
    let canceller = try #require(MeetingEchoCanceller.make(sampleRate: 16_000) { pcm, time in
        cleaned.put(pcm, capturedAt: time)
    })
    // As in the recorder, with the call's audio arriving 1.5 s late in one burst.
    let late = HeldDelivery(until: start + 1.5) { pcm, time in
        call.put(pcm, capturedAt: time)
        canceller.pushReference(pcm, capturedAt: time)
    }
    let system = MeetingSystemAudioCapture(sampleRate: 16_000, onPCM: { pcm, time in
        late.push(pcm, capturedAt: time)
    }, onError: { error in Issue.record("system audio: \(error)") })
    try await system.start()
    let microphone = AVFoundationAudioSource(options: AVFoundationAudioSourceOptions(sampleRate: 16_000))
    try await microphone.start(handlers: AudioSourceEventHandlers(
        audio: { _ in Issue.record("the microphone gave audio without a capture time") },
        timedAudio: { pcm, time in
            raw.put(pcm, capturedAt: time)
            canceller.pushMicrophone(pcm, capturedAt: time)
        },
        error: { error in Issue.record("microphone: \(error)") },
        end: {}
    ))

    // The canceller learns the room for a few seconds, then is measured.
    try await Task.sleep(nanoseconds: 500_000_000)
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-r", "180", "This is the call speaking through the loudspeakers. The canceller has to learn the room first. One, two, three, four, five. The microphone should keep the user, and not this voice. Six, seven, eight, nine, ten. The quick brown fox jumps over the lazy dog, again and again."]
    let spoken = ProcessInfo.processInfo.systemUptime
    try say.run()
    say.waitUntilExit()
    let ended = ProcessInfo.processInfo.systemUptime
    try await Task.sleep(nanoseconds: 500_000_000)
    try await microphone.stop()
    await system.stop()
    let statistics = canceller.finish()

    // From 5 s after the voice began to its end.
    let from = Int((spoken - start + 5) * 16_000)
    let to = min(Int((ended - start) * 16_000), raw.all.count)
    #expect(to - from > 3 * 16_000, "the sentence was too short")
    let before = level(raw.all[from..<to])
    let after = level(cleaned.all[from..<to])
    let reference = level(call.all[from..<to])
    print(String(format: "live echo: call %.1f dB; microphone %.1f dB -> %.1f dB after the canceller (%.1f dB less)", reference, before, after, before - after))
    print("live echo: \(MeetingRecorder.describe(statistics))")
    #expect(reference > -50, "the system audio did not have the voice")
    #expect(before > -60, "the microphone did not hear the loudspeakers")
    #expect(before - after > 10, "microphone \(before) dB -> \(after) dB")
    #expect(statistics.framesWithoutReference < 50)
    #expect(statistics.longestHold < 2.5)
}
