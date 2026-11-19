import Foundation
import Testing
@testable import UntypeCore

private let rate = 16_000

/// Noise with a speech-like rhythm (bursts), repeatable.
private func voice(seed: UInt64, seconds: Double, level: Double) -> [Double] {
    var state = seed
    func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(Int64(bitPattern: state >> 11) % 2_000_001) / 1_000_000 - 1
    }
    let count = Int(seconds * Double(rate))
    var samples = [Double](repeating: 0, count: count)
    var previous = 0.0
    for index in 0..<count {
        // Syllables of about 200 ms with short gaps.
        let phase = Double(index % (rate / 4)) / Double(rate / 4)
        let envelope = phase < 0.8 ? sin(phase / 0.8 * .pi) : 0
        // A one-pole low-pass keeps the energy where speech has it.
        previous = 0.7 * previous + 0.3 * next()
        samples[index] = previous * envelope * level
    }
    return samples
}

/// The loudspeakers' sound as the microphone hears it: later, quieter, with a short room response.
private func echo(of reference: [Double], delaySamples: Int) -> [Double] {
    let taps: [(Int, Double)] = [(0, 0.5), (23, 0.2), (61, -0.12), (140, 0.06)]
    var result = [Double](repeating: 0, count: reference.count)
    for (offset, gain) in taps {
        let shift = delaySamples + offset
        for index in shift..<reference.count {
            result[index] += reference[index - shift] * gain
        }
    }
    return result
}

private func pcm(_ samples: [Double]) -> [Int16] {
    samples.map { Int16(max(-32_767, min(32_767, $0 * 32_767))) }
}

private func level(_ samples: ArraySlice<Int16>) -> Double {
    let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count))
    return 10 * log10(power / (32_768 * 32_768) + 1e-12)
}

/// How far down (dB) `signal` is in `output` over `part`, at the lag (in
/// samples, `output` later) where it is strongest. Unlike the level, this
/// does not count the soft noise the canceller puts where it removed sound.
private func left(of signal: [Int16], in output: [Int16], _ part: Range<Int>, lags: ClosedRange<Int> = -200...200) -> (down: Double, lag: Int) {
    let wanted = signal[part].map(Float.init)
    let heard = output[(part.lowerBound + lags.lowerBound)..<(part.upperBound + lags.upperBound)].map(Float.init)
    var best = (gain: Float(0), lag: 0)
    wanted.withUnsafeBufferPointer { wanted in
        heard.withUnsafeBufferPointer { heard in
            var own: Float = 0
            for index in 0..<wanted.count {
                own += wanted[index] * wanted[index]
            }
            for shift in 0..<lags.count {
                var cross: Float = 0
                for index in 0..<wanted.count {
                    cross += heard[index + shift] * wanted[index]
                }
                if abs(cross / own) > best.gain {
                    best = (abs(cross / own), lags.lowerBound + shift)
                }
            }
        }
    }
    return (Double(-20 * log10(best.gain + 1e-12)), best.lag)
}

private func run(_ canceller: EchoCancelling, reference: [Int16], microphone: [Int16]) -> [Int16] {
    let frame = canceller.frameSamples
    var output: [Int16] = []
    var start = 0
    while start + frame <= microphone.count {
        output += canceller.process(
            reference: Array(reference[start..<start + frame]),
            microphone: Array(microphone[start..<start + frame])
        )
        start += frame
    }
    return output
}

@Test func theEchoCancellerLibraryIsLinked() throws {
    #expect(WebRTCEchoCanceller.library == "webrtc-audio-processing 2.1")
    let canceller = try #require(WebRTCEchoCanceller(sampleRate: rate))
    #expect(canceller.frameSamples == 160)
    #expect(WebRTCEchoCanceller(sampleRate: 44_100) == nil)
}

@Test func theEchoIsRemovedAndTheUsersVoiceKept() throws {
    let canceller = try #require(WebRTCEchoCanceller(sampleRate: rate))
    // 0 to 12 s: only the call talks. 12 to 16 s: only the user talks.
    let call = voice(seed: 1, seconds: 12, level: 0.5) + [Double](repeating: 0, count: 4 * rate)
    let user = [Double](repeating: 0, count: 12 * rate) + voice(seed: 2, seconds: 4, level: 0.3)
    let heard = zip(echo(of: call, delaySamples: 640), user).map { $0 + $1 }
    let reference = pcm(call)
    let microphone = pcm(heard)

    let cleaned = run(canceller, reference: reference, microphone: microphone)

    // After the first seconds (the canceller learns the room), the echo is far down:
    // in what is left of it, and in the level (which the canceller's soft noise bounds).
    let echoPart = (9 * rate)..<(10 * rate)
    let echo = left(of: microphone, in: cleaned, echoPart)
    #expect(echo.down > 30, "echo left \(echo.down) dB down")
    #expect(level(cleaned[echoPart]) < level(microphone[echoPart]) - 15)

    // The user's own voice comes through, later by the canceller's own delay.
    let kept = left(of: microphone, in: cleaned, (13 * rate)..<(14 * rate), lags: 100...160)
    #expect(kept.down < 3, "user \(kept.down) dB down")
    #expect(kept.lag == canceller.delaySamples)
}

@Test(arguments: [8_000, 16_000, 32_000, 48_000])
func theEchoCancellersOwnDelayIsTheOneWrittenDown(sampleRate: Int) throws {
    let canceller = try #require(WebRTCEchoCanceller(sampleRate: sampleRate))
    // Two seconds of noise with a silent reference come back unchanged but late.
    let noise = pcm(voice(seed: 7, seconds: 2, level: 0.3).enumerated().map { $1 + 0.05 * sin(Double($0)) })
    let input = sampleRate == rate ? noise : (0..<(2 * sampleRate)).map { noise[$0 * rate / sampleRate] }
    let frame = canceller.frameSamples
    var output: [Int16] = []
    let silence = [Int16](repeating: 0, count: frame)
    for start in stride(from: 0, to: input.count - frame + 1, by: frame) {
        output += canceller.process(reference: silence, microphone: Array(input[start..<start + frame]))
    }
    let found = left(of: input, in: output, sampleRate..<(sampleRate + sampleRate / 4), lags: 0...(sampleRate / 50))
    #expect(found.lag == canceller.delaySamples)
    #expect(canceller.delaySamples == WebRTCEchoCanceller.delays[sampleRate])
}

@Test func aFrameOfTheWrongLengthGoesThroughTheEchoCanceller() throws {
    let canceller = try #require(WebRTCEchoCanceller(sampleRate: rate))
    let odd = [Int16](repeating: 100, count: 50)
    #expect(canceller.process(reference: odd, microphone: odd) == odd)
}

// MARK: - The aligner (which call audio goes with which microphone audio)

/// The capture time of sample 0 in these tests.
private let start = 1_000.0
private let advance = 640

/// Call and microphone samples that say which sample they are: the call's
/// are 1...15,000, the microphone's -1...-15,000 (silence is 0).
private func callSignal(_ range: Range<Int>) -> [Int16] {
    range.map { Int16($0 % 15_000) + 1 }
}

private func voiceSignal(_ range: Range<Int>) -> [Int16] {
    range.map { -(Int16($0 % 15_000) + 1) }
}

/// Keeps what it is given, frame by frame, and gives the microphone back.
private final class PairRecorder: EchoCancelling {
    let frameSamples = 160
    let delaySamples: Int
    private(set) var pairs: [(reference: [Int16], microphone: [Int16])] = []
    /// What went in and has not come back yet.
    private var held: [Int16]

    /// With a delay it gives the microphone back that many samples late, as WebRTC's canceller does.
    init(delaySamples: Int = 0) {
        self.delaySamples = delaySamples
        held = [Int16](repeating: 0, count: delaySamples)
    }

    func process(reference: [Int16], microphone: [Int16]) -> [Int16] {
        pairs.append((reference, microphone))
        held += microphone
        let output = Array(held.prefix(microphone.count))
        held.removeFirst(microphone.count)
        return output
    }
}

/// Of the microphone samples given with a call sample: how many, and how
/// many with another call sample than the one of `advance` samples later.
private func pairing(_ pairs: [(reference: [Int16], microphone: [Int16])]) -> (checked: Int, wrong: Int) {
    var checked = 0
    var wrong = 0
    for pair in pairs {
        for (call, voice) in zip(pair.reference, pair.microphone) where call > 0 && voice < 0 {
            checked += 1
            let difference = (Int(call) - 1) - (-Int(voice) - 1) - advance
            if ((difference % 15_000) + 15_000) % 15_000 != 0 {
                wrong += 1
            }
        }
    }
    return (checked, wrong)
}

private struct Arrival {
    let at: TimeInterval
    let isReference: Bool
    let capturedAt: TimeInterval
    let samples: [Int16]
}

/// `signal` (its first sample is sample `first`) in chunks of `size`, each
/// arriving `delay` after its last sample was captured.
private func arrivals(of signal: [Int16], first: Int = 0, size: Int, isReference: Bool, delay: TimeInterval) -> [Arrival] {
    stride(from: 0, to: signal.count, by: size).map { offset in
        let chunk = Array(signal[offset..<min(offset + size, signal.count)])
        let capturedAt = start + Double(first + offset) / Double(rate)
        return Arrival(at: capturedAt + Double(chunk.count) / Double(rate) + delay, isReference: isReference, capturedAt: capturedAt, samples: chunk)
    }
}

private func callArrivals(_ signal: [Int16], first: Int = 0, delay: TimeInterval = 0.05) -> [Arrival] {
    arrivals(of: signal, first: first, size: 320, isReference: true, delay: delay)
}

private func voiceArrivals(_ signal: [Int16], first: Int = 0) -> [Arrival] {
    arrivals(of: signal, first: first, size: 1_600, isReference: false, delay: 0.005)
}

private struct Given {
    let chunk: MeetingEchoAligner.Chunk
    let at: TimeInterval
}

/// Gives the aligner everything in the order it arrives, then ends.
private func feed(_ aligner: inout MeetingEchoAligner, _ arrivals: [Arrival], finishAt: TimeInterval) -> [Given] {
    var given: [Given] = []
    let ordered = arrivals.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
    for (_, arrival) in ordered {
        let chunks = arrival.isReference
            ? aligner.pushReference(arrival.samples, capturedAt: arrival.capturedAt, now: arrival.at)
            : aligner.pushMicrophone(arrival.samples, capturedAt: arrival.capturedAt, now: arrival.at)
        given += chunks.map { Given(chunk: $0, at: arrival.at) }
    }
    given += aligner.finish(now: finishAt).map { Given(chunk: $0, at: finishAt) }
    return given
}

/// What was given back, every chunk at the place its capture time says.
private func timeline(_ given: [Given], count: Int) -> [Int16] {
    var result = [Int16](repeating: 0, count: count)
    for item in given {
        let index = Int(((item.chunk.capturedAt - start) * Double(rate)).rounded())
        for (offset, sample) in item.chunk.samples.enumerated() where index + offset >= 0 && index + offset < count {
            result[index + offset] = sample
        }
    }
    return result
}

@Test func theMicrophoneIsGivenTheCallsAudioOfItsOwnTime() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let voice = voiceSignal(0..<32_000)
    let given = feed(&aligner, callArrivals(callSignal(0..<35_200)) + voiceArrivals(voice), finishAt: start + 3)

    // Every microphone sample went to the canceller with the call's sample of 40 ms later.
    let result = pairing(recorder.pairs)
    #expect(result.checked == 32_000 && result.wrong == 0)
    // The microphone comes back whole, in order, at its own times, soon after it was captured.
    #expect(given.flatMap(\.chunk.samples) == voice)
    var position = 0
    for item in given {
        #expect(abs(item.chunk.capturedAt - (start + Double(position) / Double(rate))) < 0.0001)
        position += item.chunk.samples.count
        #expect(item.at - (start + Double(position) / Double(rate)) < 0.3)
    }
    #expect(aligner.statistics.frames == 200)
    #expect(aligner.statistics.framesWithoutReference == 0)
    #expect(aligner.statistics.longestHold < 0.3)
}

@Test func aCallTwoSecondsLateIsWaitedFor() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let voice = voiceSignal(0..<32_000)
    let given = feed(&aligner, callArrivals(callSignal(0..<35_200), delay: 2) + voiceArrivals(voice), finishAt: start + 5)

    // Nothing goes on before the call's audio is there, and then all of it with the right audio.
    #expect(given.allSatisfy { $0.at >= start + 2 })
    let result = pairing(recorder.pairs)
    #expect(result.checked == 32_000 && result.wrong == 0)
    #expect(given.flatMap(\.chunk.samples) == voice)
    #expect(aligner.statistics.framesWithoutReference == 0)
    #expect(aligner.statistics.longestHold > 1.9 && aligner.statistics.longestHold < 2.3)
}

@Test func withoutTheCallsAudioTheMicrophoneGoesOnAfterTheLimit() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let voice = voiceSignal(0..<80_000)
    let given = feed(&aligner, voiceArrivals(voice), finishAt: start + 5.2)

    // Three seconds, not more: at the end two seconds have gone on by themselves.
    #expect(given.allSatisfy { $0.at >= start + 3 })
    #expect(given.filter { $0.at < start + 5.2 }.reduce(0) { $0 + $1.chunk.samples.count } == 32_000)
    #expect(given.flatMap(\.chunk.samples) == voice)
    #expect(recorder.pairs.allSatisfy { $0.reference.allSatisfy { $0 == 0 } })
    #expect(aligner.statistics.frames == 500 && aligner.statistics.framesWithoutReference == 500)
}

@Test func aCallArrivingInBurstsIsUsedWhole() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let voice = voiceSignal(0..<64_000)
    // The call's audio arrives once a second, a second's worth at a time.
    let call = callArrivals(callSignal(0..<72_000)).map { arrival -> Arrival in
        let end = arrival.capturedAt - start + 0.02
        return Arrival(at: start + (end - 1e-6).rounded(.up) + 0.05, isReference: true, capturedAt: arrival.capturedAt, samples: arrival.samples)
    }
    let given = feed(&aligner, call + voiceArrivals(voice), finishAt: start + 6)

    let result = pairing(recorder.pairs)
    #expect(result.checked == 64_000 && result.wrong == 0)
    #expect(given.flatMap(\.chunk.samples) == voice)
    #expect(aligner.statistics.framesWithoutReference == 0)
    #expect(aligner.statistics.longestHold < 1.2)
}

@Test func audioMissingFromTheCallCountsAsSilence() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let voice = voiceSignal(0..<48_000)
    // 0.76 s of the call's audio never arrive (ScreenCaptureKit dropped it); its times show the hole.
    let missing = 16_000..<28_160
    let call = callArrivals(callSignal(0..<51_200)).filter { arrival in
        !missing.contains(Int(((arrival.capturedAt - start) * Double(rate)).rounded()))
    }
    let given = feed(&aligner, call + voiceArrivals(voice), finishAt: start + 4)

    let result = pairing(recorder.pairs)
    #expect(result.checked == 48_000 - missing.count && result.wrong == 0)
    // The microphone audio that went with silence is the audio of the hole, and only that.
    var misplaced = 0
    for (number, pair) in recorder.pairs.enumerated() {
        for (offset, call) in pair.reference.enumerated() where (call == 0) != missing.contains(number * 160 + offset + advance) {
            misplaced += 1
        }
    }
    #expect(misplaced == 0)
    #expect(given.flatMap(\.chunk.samples) == voice)
    #expect(aligner.statistics.framesWithoutReference == 0)
}

@Test func microphoneChunksArrivingOutOfOrderAreSorted() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let voice = voiceSignal(0..<16_000)
    var microphone = voiceArrivals(voice)
    // The fourth chunk arrives 10 ms after the fifth.
    let fourth = microphone[3]
    microphone[3] = Arrival(at: microphone[4].at + 0.01, isReference: false, capturedAt: fourth.capturedAt, samples: fourth.samples)
    let given = feed(&aligner, callArrivals(callSignal(0..<19_200)) + microphone, finishAt: start + 2)

    #expect(given.flatMap(\.chunk.samples) == voice)
    #expect(pairing(recorder.pairs).wrong == 0)
    #expect(aligner.statistics.filledSamples == 0 && aligner.statistics.lateChunks == 0)
}

@Test func aMicrophoneChunkArrivingAfterItsPlaceWasTakenIsLeftOut() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let voice = voiceSignal(0..<16_000)
    var microphone = voiceArrivals(voice)
    // The fourth chunk arrives 200 ms after the fifth: silence already stands where it belonged.
    let fourth = microphone[3]
    microphone[3] = Arrival(at: microphone[4].at + 0.2, isReference: false, capturedAt: fourth.capturedAt, samples: fourth.samples)
    let given = feed(&aligner, callArrivals(callSignal(0..<19_200)) + microphone, finishAt: start + 2)

    var expected = voice
    expected.replaceSubrange(4_800..<6_400, with: [Int16](repeating: 0, count: 1_600))
    #expect(given.flatMap(\.chunk.samples) == expected)
    #expect(pairing(recorder.pairs).wrong == 0)
    #expect(aligner.statistics.filledSamples == 1_600 && aligner.statistics.lateChunks == 1)
}

@Test func aShortGapInTheMicrophoneBecomesSilence() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let voice = voiceSignal(0..<16_000)
    var microphone = voiceArrivals(voice)
    microphone.remove(at: 3)
    let given = feed(&aligner, callArrivals(callSignal(0..<19_200)) + microphone, finishAt: start + 2)

    var expected = voice
    expected.replaceSubrange(4_800..<6_400, with: [Int16](repeating: 0, count: 1_600))
    #expect(given.flatMap(\.chunk.samples) == expected)
    // What follows the gap still gets the call's audio of its own time.
    let result = pairing(recorder.pairs)
    #expect(result.checked == 14_400 && result.wrong == 0)
    #expect(aligner.statistics.filledSamples == 1_600)
}

@Test func afterALongGapTheMicrophoneStartsAgainAtItsOwnTime() {
    let recorder = PairRecorder()
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    // One second of microphone, three seconds of nothing, one more second.
    let before = voiceSignal(0..<16_000)
    let after = voiceSignal(64_000..<80_000)
    let given = feed(&aligner, callArrivals(callSignal(0..<83_200)) + voiceArrivals(before) + voiceArrivals(after, first: 64_000), finishAt: start + 6)

    // No three seconds of silence are made up; the second part carries its own time.
    #expect(given.reduce(0) { $0 + $1.chunk.samples.count } == 32_000)
    #expect(aligner.statistics.filledSamples == 0)
    let placed = timeline(given, count: 80_000)
    #expect(Array(placed[0..<16_000]) == before)
    #expect(placed[16_000..<64_000].allSatisfy { $0 == 0 })
    #expect(Array(placed[64_000..<80_000]) == after)
    let result = pairing(recorder.pairs)
    #expect(result.checked == 32_000 && result.wrong == 0)
}

/// Microphone chunks of 100 ms of samples whose capture times are `spacing`
/// apart: a microphone whose clock is not the system's.
private func driftingVoice(_ voice: [Int16], spacing: TimeInterval) -> [Arrival] {
    stride(from: 0, to: voice.count, by: 1_600).enumerated().map { number, offset in
        let capturedAt = start + Double(number) * spacing
        return Arrival(at: capturedAt + 0.105, isReference: false, capturedAt: capturedAt, samples: Array(voice[offset..<offset + 1_600]))
    }
}

/// The largest difference (seconds) between the time a sample is given
/// back with and the time it was captured, for the samples of `voice`
/// (silence that was put in is skipped).
private func largestTimeError(_ given: [Given], spacing: TimeInterval) -> Double {
    var worst = 0.0
    var number = 0
    for item in given {
        for (offset, sample) in item.chunk.samples.enumerated() where sample != 0 {
            let labelled = item.chunk.capturedAt + Double(offset) / Double(rate)
            let captured = start + Double(number / 1_600) * spacing + Double(number % 1_600) / Double(rate)
            worst = max(worst, abs(labelled - captured))
            number += 1
        }
    }
    return worst
}

@Test func aMicrophoneClockSlowerThanTheSystemsIsFollowedWithSilence() {
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: PairRecorder())
    let voice = voiceSignal(0..<160_000)
    // Every 100 ms of samples takes 100.5 ms: the times run ahead of the samples counted.
    let given = feed(&aligner, callArrivals(callSignal(0..<176_000)) + driftingVoice(voice, spacing: 0.1005), finishAt: start + 12)

    let samples = given.flatMap(\.chunk.samples)
    #expect(samples.filter { $0 != 0 } == voice)
    #expect(aligner.statistics.filledSamples == samples.count - voice.count && aligner.statistics.filledSamples > 0)
    #expect(largestTimeError(given, spacing: 0.1005) <= 0.0155)
}

@Test func aMicrophoneClockFasterThanTheSystemsLosesNoAudio() {
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: PairRecorder())
    let voice = voiceSignal(0..<160_000)
    // Every 100 ms of samples takes 99.5 ms: the samples counted run ahead of the times.
    let given = feed(&aligner, callArrivals(callSignal(0..<176_000)) + driftingVoice(voice, spacing: 0.0995), finishAt: start + 12)

    #expect(given.flatMap(\.chunk.samples) == voice)
    #expect(aligner.statistics.filledSamples == 0 && aligner.statistics.lateChunks == 0)
    #expect(largestTimeError(given, spacing: 0.0995) <= 0.0155)
}

@Test func aCancellerThatAnswersLateStillGivesEverySampleAtItsOwnTime() {
    let recorder = PairRecorder(delaySamples: 128)
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    // Not a whole number of frames: the last 100 samples are part of one.
    let voice = voiceSignal(0..<32_100)
    let given = feed(&aligner, callArrivals(callSignal(0..<35_200)) + voiceArrivals(voice), finishAt: start + 3)

    #expect(given.flatMap(\.chunk.samples) == voice)
    #expect(timeline(given, count: 32_100) == voice)
    #expect(pairing(recorder.pairs).wrong == 0)
}

@Test func aCancellerThatAnswersLateLosesNothingAroundALongGap() {
    let recorder = PairRecorder(delaySamples: 128)
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: recorder)
    let before = voiceSignal(0..<16_050)
    let after = voiceSignal(64_000..<80_000)
    let given = feed(&aligner, callArrivals(callSignal(0..<83_200)) + voiceArrivals(before) + voiceArrivals(after, first: 64_000), finishAt: start + 6)

    #expect(given.flatMap(\.chunk.samples) == before + after)
    let placed = timeline(given, count: 80_000)
    #expect(Array(placed[0..<16_050]) == before)
    #expect(placed[16_050..<64_000].allSatisfy { $0 == 0 })
    #expect(Array(placed[64_000..<80_000]) == after)
}

@Test(arguments: [1, 100, 160, 200, 288, 320])
func aCancellerThatAnswersLateGivesBackAVeryShortRecordingWhole(count: Int) {
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: PairRecorder(delaySamples: 128))
    let voice = voiceSignal(0..<count)
    let given = feed(&aligner, voiceArrivals(voice), finishAt: start + 1)
    #expect(given.flatMap(\.chunk.samples) == voice)
    #expect(given.first.map { abs($0.chunk.capturedAt - start) < 0.0001 } == true)
}

@Test func nothingComesOutOfARecordingWithoutMicrophoneAudio() {
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: PairRecorder(delaySamples: 128))
    #expect(feed(&aligner, callArrivals(callSignal(0..<16_000)), finishAt: start + 2).isEmpty)
    #expect(aligner.statistics == MeetingEchoStatistics())
}

// MARK: - The aligner with WebRTC's canceller

/// Runs a call and what the microphone heard through the aligner with the
/// real canceller; the call's audio arrives `callDelay` later than usual.
private func clean(call: [Int16], heard: [Int16], callDelay: TimeInterval = 0) throws -> (cleaned: [Int16], statistics: MeetingEchoStatistics) {
    let canceller = try #require(WebRTCEchoCanceller(sampleRate: rate))
    var aligner = MeetingEchoAligner(sampleRate: rate, canceller: canceller)
    let given = feed(
        &aligner,
        // The call's audio goes on a little longer than the microphone's, as it does until a recording stops.
        callArrivals(call + [Int16](repeating: 0, count: 1_600), delay: 0.05 + callDelay) + voiceArrivals(heard),
        finishAt: start + Double(heard.count) / Double(rate) + callDelay + 1
    )
    return (timeline(given, count: heard.count), aligner.statistics)
}

/// 12 s of call, then 4 s of the user alone; the microphone hears the call
/// `echoDelay` samples after it was played (negative: before, as when the
/// streams' times are off).
private func meeting(echoDelay: Int) -> (call: [Int16], heard: [Int16]) {
    let call = voice(seed: 1, seconds: 12, level: 0.5) + [Double](repeating: 0, count: 4 * rate)
    let user = [Double](repeating: 0, count: 12 * rate) + voice(seed: 2, seconds: 4, level: 0.3)
    let played = echoDelay >= 0 ? call : Array(call[(-echoDelay)...]) + [Double](repeating: 0, count: -echoDelay)
    let heard = zip(echo(of: played, delaySamples: max(0, echoDelay)), user).map { $0 + $1 }
    return (pcm(call), pcm(heard))
}

private func expectTheCallGoneAndTheUserKept(_ heard: [Int16], _ cleaned: [Int16]) {
    // Until 12 s the microphone hears only the call.
    let callPart = (9 * rate)..<(10 * rate)
    let call = left(of: heard, in: cleaned, callPart)
    #expect(call.down > 30, "call left \(call.down) dB down")
    #expect(level(cleaned[callPart]) < level(heard[callPart]) - 15)
    // From 12 s only the user: kept, and at its own time (the canceller's delay is taken out).
    let user = left(of: heard, in: cleaned, (13 * rate)..<(14 * rate), lags: -30...30)
    #expect(user.down < 3, "user \(user.down) dB down")
    #expect(user.lag == 0)
}

@Test func theCallIsRemovedWhenItsAudioArrivesTwoSecondsLate() throws {
    let (call, heard) = meeting(echoDelay: 640)
    let result = try clean(call: call, heard: heard, callDelay: 2)
    expectTheCallGoneAndTheUserKept(heard, result.cleaned)
    #expect(result.statistics.longestHold > 1.9 && result.statistics.longestHold < 2.3)
    #expect(result.statistics.framesWithoutReference == 0)
    #expect((result.statistics.reduction ?? 0) > 10)
}

@Test func theCallIsRemovedWhenItsEchoHasNoDelay() throws {
    let (call, heard) = meeting(echoDelay: 0)
    expectTheCallGoneAndTheUserKept(heard, try clean(call: call, heard: heard).cleaned)
}

@Test func theCallIsRemovedWhenTheStreamsTimesAreOffByTwentyMilliseconds() throws {
    // The microphone hears the call 20 ms before the call's audio says it was played.
    let (call, heard) = meeting(echoDelay: -320)
    expectTheCallGoneAndTheUserKept(heard, try clean(call: call, heard: heard).cleaned)
}

@Test func withASilentCallTheMicrophoneComesThrough() throws {
    // Headphones: nothing of the call reaches the microphone and there is nothing to remove.
    let user = pcm(voice(seed: 3, seconds: 8, level: 0.3))
    let result = try clean(call: [Int16](repeating: 0, count: user.count), heard: user)
    let part = rate..<(8 * rate)
    #expect(abs(level(result.cleaned[part]) - level(user[part])) < 1, "\(level(user[part])) dB -> \(level(result.cleaned[part])) dB")
    #expect(result.statistics.reduction == nil)
}

// MARK: - On its queue

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16] = []

    func add(_ pcm: Data) {
        lock.lock()
        samples += MeetingAudioRecorder.samples(pcm)
        lock.unlock()
    }

    var all: [Int16] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

private func data(_ samples: [Int16]) -> Data {
    samples.withUnsafeBufferPointer { Data(buffer: $0) }
}

@Test func theQueuedCancellerTakesBothStreamsFromTheirOwnThreads() {
    let recorder = PairRecorder()
    let collected = Collected()
    let canceller = MeetingEchoCanceller(sampleRate: rate, canceller: recorder) { pcm, _ in collected.add(pcm) }
    // Two seconds captured a moment ago.
    let base = ProcessInfo.processInfo.systemUptime - 2.5
    let voice = voiceSignal(0..<32_000)
    let call = callSignal(0..<35_200)
    let group = DispatchGroup()
    DispatchQueue.global().async(group: group) {
        for offset in stride(from: 0, to: call.count, by: 320) {
            canceller.pushReference(data(Array(call[offset..<offset + 320])), capturedAt: base + Double(offset) / Double(rate))
        }
    }
    DispatchQueue.global().async(group: group) {
        for offset in stride(from: 0, to: voice.count, by: 1_600) {
            canceller.pushMicrophone(data(Array(voice[offset..<offset + 1_600])), capturedAt: base + Double(offset) / Double(rate))
        }
    }
    group.wait()
    let statistics = canceller.finish()

    #expect(collected.all == voice)
    #expect(statistics.frames == 200 && statistics.framesWithoutReference == 0)
    let result = pairing(recorder.pairs)
    #expect(result.checked == 32_000 && result.wrong == 0)
    // After the end nothing more is taken.
    canceller.pushMicrophone(data(voice), capturedAt: base + 3)
    #expect(canceller.finish() == statistics)
    #expect(collected.all.count == 32_000)
}

@Test func theMeetingsCancellerIsMadeForTheRatesTheLibraryTakes() {
    #expect(MeetingEchoCanceller.make(sampleRate: 16_000) { _, _ in } != nil)
    #expect(MeetingEchoCanceller.make(sampleRate: 44_100) { _, _ in } == nil)
}

// MARK: - In the recorder

@Test func echoCancellationIsOffByDefaultAndStored() throws {
    #expect(!MeetingPreferences().removesSpeakerSound)
    let old = try JSONDecoder().decode(MeetingPreferences.self, from: Data(#"{"language":"en","silenceMinutes":3}"#.utf8))
    #expect(old.echoCancellation == nil && !old.removesSpeakerSound)
    var meeting = MeetingPreferences()
    meeting.echoCancellation = true
    let stored = try JSONDecoder().decode(MeetingPreferences.self, from: try JSONEncoder().encode(meeting))
    #expect(stored.removesSpeakerSound)
}

@Test func theEchoCancellationsLogLineSaysWhatItDid() {
    var statistics = MeetingEchoStatistics()
    statistics.frames = 30_000
    statistics.totalHold = 30_000 * 0.107
    statistics.longestHold = 1.172
    statistics.framesWithCall = 24_000
    statistics.powerBefore = 400
    statistics.powerAfter = 1
    #expect(MeetingRecorder.describe(statistics) == "meeting echo cancellation: 300 s of microphone; 26 dB quieter while the call had sound (240 s); held 107 ms on average, 1172 ms at most")

    statistics.framesWithoutReference = 250
    statistics.filledSamples = 8_000
    statistics.lateChunks = 2
    #expect(MeetingRecorder.describe(statistics).hasSuffix("; 2.5 s without the call's audio; 0.5 s of silence put in; 2 microphone chunks too late"))

    // Headphones: nothing of the call reached the microphone.
    var quiet = MeetingEchoStatistics()
    quiet.frames = 500
    #expect(MeetingRecorder.describe(quiet) == "meeting echo cancellation: 5 s of microphone; the call had no sound (nothing to remove); held 0 ms on average, 0 ms at most")
}
