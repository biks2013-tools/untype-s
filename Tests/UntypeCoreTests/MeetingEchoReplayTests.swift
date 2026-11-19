@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import UntypeCore

// Replays a saved recording through the meeting's own echo cancellation
// (the aligner and WebRTC's canceller, plan-072), as the two streams would
// have arrived. It runs only when asked:
//
//   UNTYPE_AEC_REPLAY=/path/to/recording-2026-11-19-16-11 [UNTYPE_AEC_CALL_LATE=1.956] \
//     swift test --filter meetingEchoReplay
//
// Reads <base>.mic.wav and <base>.system.wav (16 kHz mono PCM16; made from a
// recording's .m4a files; test_scripts/aec-eval/replay.py does it and runs this) and writes
// <base>.untype-aec.wav, in step with the microphone's file.
// UNTYPE_AEC_CALL_LATE: by how many seconds the system audio is late in the
// saved files (recordings made before plan-072 step 2 placed it by arrival;
// test_scripts/aec-eval/lagscan.py measures it). The system audio is then
// taken as captured that much earlier and as arriving that much late.

private let replayBase = ProcessInfo.processInfo.environment["UNTYPE_AEC_REPLAY"]

private func samples(of url: URL) throws -> [Int16] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
    #expect(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1, "16 kHz mono expected: \(url.lastPathComponent)")
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let channel = try #require(buffer.int16ChannelData?[0])
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

private func write(_ samples: [Int16], to url: URL) throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
    buffer.frameLength = AVAudioFrameCount(samples.count)
    let channel = try #require(buffer.int16ChannelData?[0])
    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false
    ], commonFormat: .pcmFormatInt16, interleaved: false)
    try file.write(from: buffer)
}

@Test(.enabled(if: replayBase != nil))
func meetingEchoReplay() throws {
    let base = try #require(replayBase)
    let late = Double(ProcessInfo.processInfo.environment["UNTYPE_AEC_CALL_LATE"] ?? "0") ?? 0
    let microphone = try samples(of: URL(fileURLWithPath: base + ".mic.wav"))
    let call = try samples(of: URL(fileURLWithPath: base + ".system.wav"))
    let rate = 16_000.0

    struct Arrival {
        let at: TimeInterval
        let isCall: Bool
        let capturedAt: TimeInterval
        let samples: [Int16]
    }
    var arrivals: [Arrival] = []
    // The microphone: 100 ms at a time, there 5 ms after its last sample.
    for offset in stride(from: 0, to: microphone.count, by: 1_600) {
        let chunk = Array(microphone[offset..<min(offset + 1_600, microphone.count)])
        let capturedAt = Double(offset) / rate
        arrivals.append(Arrival(at: capturedAt + Double(chunk.count) / rate + 0.005, isCall: false, capturedAt: capturedAt, samples: chunk))
    }
    // The call: 20 ms at a time, there 50 ms after its last sample, and `late` later than that.
    for offset in stride(from: 0, to: call.count, by: 320) {
        let chunk = Array(call[offset..<min(offset + 320, call.count)])
        let capturedAt = Double(offset) / rate - late
        arrivals.append(Arrival(at: capturedAt + Double(chunk.count) / rate + 0.05 + late, isCall: true, capturedAt: capturedAt, samples: chunk))
    }
    let ordered = arrivals.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }

    let canceller = try #require(WebRTCEchoCanceller(sampleRate: 16_000))
    var aligner = MeetingEchoAligner(sampleRate: 16_000, canceller: canceller)
    var cleaned = [Int16](repeating: 0, count: microphone.count)
    var given = 0
    func place(_ chunks: [MeetingEchoAligner.Chunk]) {
        for chunk in chunks {
            let index = Int((chunk.capturedAt * rate).rounded())
            for (offset, sample) in chunk.samples.enumerated() where index + offset >= 0 && index + offset < cleaned.count {
                cleaned[index + offset] = sample
            }
            given += chunk.samples.count
        }
    }
    let started = Date()
    for (_, arrival) in ordered {
        place(arrival.isCall
            ? aligner.pushReference(arrival.samples, capturedAt: arrival.capturedAt, now: arrival.at)
            : aligner.pushMicrophone(arrival.samples, capturedAt: arrival.capturedAt, now: arrival.at))
    }
    place(aligner.finish(now: ordered.last?.element.at ?? 0))
    let took = Date().timeIntervalSince(started)

    let output = URL(fileURLWithPath: base + ".untype-aec.wav")
    try write(cleaned, to: output)
    let statistics = aligner.statistics
    let seconds = Double(microphone.count) / rate
    print(String(format: "replay: %.0f s of microphone in %.1f s (%.0f times real time); %d samples in, %d given back", seconds, took, seconds / took, microphone.count, given))
    print(String(format: "replay: %d frames, %d without their reference, %d samples of silence put in, %d late chunks; held %.0f ms on average, %.0f ms at most", statistics.frames, statistics.framesWithoutReference, statistics.filledSamples, statistics.lateChunks, statistics.averageHold * 1000, statistics.longestHold * 1000))
    print(String(format: "replay: while the call has sound (%.0f s) the microphone is %.1f dB quieter", Double(statistics.framesWithCall) / 100, statistics.reduction ?? 0))
    print("replay: written \(output.path)")
    #expect(given == microphone.count)
}
