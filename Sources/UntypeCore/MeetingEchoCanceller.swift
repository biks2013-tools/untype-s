#if os(macOS)
import Foundation
import UntypeAEC

/// Removes the loudspeakers' sound from microphone audio, 10 ms at a time.
protocol EchoCancelling: AnyObject {
    /// Samples in one frame of 10 ms.
    var frameSamples: Int { get }
    /// How many samples later than it went in the microphone's audio comes
    /// back (the canceller's own delay).
    var delaySamples: Int { get }
    /// `reference` is what the loudspeakers played and `microphone` what the
    /// microphone heard in the same 10 ms (both `frameSamples` long); the
    /// microphone frame comes back without the reference's echo.
    func process(reference: [Int16], microphone: [Int16]) -> [Int16]
}

/// WebRTC's echo canceller (AEC3), echo cancellation only. Not thread-safe.
final class WebRTCEchoCanceller: EchoCancelling {
    /// The library's delay per rate, in samples (measured 2026-11-19 with
    /// webrtc-audio-processing 2.1; a test measures it again).
    static let delays = [8_000: 88, 16_000: 128, 32_000: 260, 48_000: 430]

    let frameSamples: Int
    let delaySamples: Int
    private let handle: OpaquePointer

    /// Nil when the rate is not one the library takes (8, 16, 32, 48 kHz)
    /// or the canceller could not be made.
    init?(sampleRate: Int) {
        guard let handle = untype_aec_create(Int32(sampleRate)) else {
            return nil
        }
        self.handle = handle
        frameSamples = Int(untype_aec_frame_samples(handle))
        delaySamples = Self.delays[sampleRate] ?? 0
    }

    deinit {
        untype_aec_destroy(handle)
    }

    /// The library in use, for the log.
    static var library: String {
        String(cString: untype_aec_library())
    }

    func process(reference: [Int16], microphone: [Int16]) -> [Int16] {
        guard reference.count == frameSamples, microphone.count == frameSamples else {
            return microphone
        }
        var output = [Int16](repeating: 0, count: frameSamples)
        let failed = reference.withUnsafeBufferPointer { untype_aec_process_reverse(handle, $0.baseAddress) } != 0
            || microphone.withUnsafeBufferPointer { input in
                output.withUnsafeMutableBufferPointer { untype_aec_process(handle, input.baseAddress, $0.baseAddress) }
            } != 0
        // A frame the library refuses goes through as it came.
        return failed ? microphone : output
    }
}

/// What the meeting's echo cancellation did, for the log.
struct MeetingEchoStatistics: Equatable, Sendable {
    /// Microphone frames (10 ms) given back.
    var frames = 0
    /// Frames given back without their whole reference: it had not arrived
    /// within the limit, or the recording ended first.
    var framesWithoutReference = 0
    /// Samples of silence put where the microphone delivered nothing.
    var filledSamples = 0
    /// Microphone chunks that arrived after their place had been taken.
    var lateChunks = 0
    /// The longest time between a frame's capture and its processing, and
    /// the sum over all frames.
    var longestHold: TimeInterval = 0
    var totalHold: TimeInterval = 0
    /// Frames in which the reference had sound, and the microphone's power
    /// in them before and after.
    var framesWithCall = 0
    var powerBefore = 0.0
    var powerAfter = 0.0

    var averageHold: TimeInterval {
        frames > 0 ? totalHold / Double(frames) : 0
    }

    /// How much quieter the microphone is while the call has sound (dB);
    /// nil when the call never had any.
    var reduction: Double? {
        guard framesWithCall > 0, powerBefore > 0 else {
            return nil
        }
        return 10 * log10(powerBefore / max(powerAfter, 1e-9))
    }
}

/// Brings the meeting's microphone and the system audio (the reference)
/// together for the echo canceller: for every 10 ms of microphone audio, the
/// system audio of the same time.
///
/// Both arrive in chunks with the time their first sample was captured
/// (`ProcessInfo.systemUptime` clock). The system audio can arrive late (by
/// seconds: ScreenCaptureKit, 2026-11-19), so the microphone waits for it:
/// a frame is processed once the reference for its time is there, or after
/// `maximumHold` with what there is. The microphone's samples come back in
/// the order they were captured, none dropped, each at its capture time
/// (the canceller's own delay is taken out); where the microphone delivered
/// nothing for a moment, silence takes the place.
///
/// A value without threads or clocks of its own: every call says what time
/// it is. `MeetingEchoCanceller` puts it on a queue.
struct MeetingEchoAligner {
    struct Settings: Equatable, Sendable {
        /// How far ahead of a microphone frame its reference is taken. The
        /// echo then comes after its reference in what the canceller sees
        /// (it cannot remove an echo that comes first), also when the two
        /// streams' positions are each off by `tolerance`.
        var referenceAdvance: TimeInterval = 0.040
        /// How far a chunk's capture time may be from where the samples
        /// counted so far put it before the stream is set right. Above the
        /// jitter of the capture times, below half of `referenceAdvance`.
        var tolerance: TimeInterval = 0.015
        /// The longest a microphone frame waits for its reference.
        var maximumHold: TimeInterval = 3
        /// The longest gap in the microphone that is filled with silence; a
        /// longer one ends the audio so far and starts again at its own time.
        var maximumFill: TimeInterval = 2
        /// How long a microphone chunk waits for one captured before it
        /// (the microphone hands every chunk to a task of its own).
        var reorderWindow: TimeInterval = 0.030
        /// The cleaned audio is given back in pieces of about this length.
        var outputChunk: TimeInterval = 0.1
        /// How much reference is kept.
        var referenceHistory: TimeInterval = 6

        init() {}
    }

    /// Audio with the time its first sample was captured.
    struct Chunk: Equatable, Sendable {
        var samples: [Int16]
        var capturedAt: TimeInterval
    }

    private struct Incoming {
        let samples: [Int16]
        let capturedAt: TimeInterval
        let arrivedAt: TimeInterval
    }

    /// The reference has sound above this (mean square of PCM16, -50 dBFS).
    private static let callPower = 32_768.0 * 32_768.0 * 1e-5

    let sampleRate: Int
    let settings: Settings
    private(set) var statistics = MeetingEchoStatistics()
    private let canceller: EchoCancelling
    private let frame: Int
    /// The canceller gives its audio back this many samples late.
    private let delay: Int
    private let advanceSamples: Int
    private let toleranceSamples: Int
    private let maximumFillSamples: Int
    private let historySamples: Int
    private let outputSamples: Int

    /// The time of sample 0 of both streams (the first capture time seen).
    private var origin: TimeInterval?

    /// The reference, by capture time: `reference[0]` is sample `referenceBase`.
    private var reference: [Int16] = []
    private var referenceBase = 0
    /// The first reference sample ever (nil: none yet).
    private var referenceStart: Int?

    /// Microphone chunks waiting for one captured before them, by capture time.
    private var incoming: [Incoming] = []
    /// Microphone audio waiting for its reference: `pending[0]` is sample `pendingIndex`.
    private var pending: [Int16] = []
    private var pendingIndex = 0
    private var microphoneStarted = false

    /// Cleaned audio not yet given back: `ready[0]` is sample `readyIndex`.
    private var ready: [Int16] = []
    private var readyIndex = 0
    /// Samples the canceller still gives back from before this stretch of
    /// audio (at the start, and after a gap too long to fill).
    private var discard: Int
    /// Audio of this stretch has gone into the canceller.
    private var stretchHasAudio = false

    init(sampleRate: Int, canceller: EchoCancelling, settings: Settings = Settings()) {
        self.sampleRate = sampleRate
        self.settings = settings
        self.canceller = canceller
        frame = canceller.frameSamples
        delay = max(0, canceller.delaySamples)
        discard = delay
        let rate = Double(sampleRate)
        advanceSamples = Int((settings.referenceAdvance * rate).rounded())
        toleranceSamples = Int((settings.tolerance * rate).rounded())
        maximumFillSamples = Int((settings.maximumFill * rate).rounded())
        historySamples = max(frame, Int((settings.referenceHistory * rate).rounded()))
        outputSamples = max(frame, Int((settings.outputChunk * rate).rounded()))
    }

    /// System audio whose first sample was captured at `capturedAt`; `now` is
    /// the time it arrived. Gives back the microphone audio this completes.
    mutating func pushReference(_ samples: [Int16], capturedAt: TimeInterval, now: TimeInterval) -> [Chunk] {
        guard !samples.isEmpty else {
            return []
        }
        let expected = index(of: capturedAt)
        if referenceStart == nil {
            referenceStart = expected
            referenceBase = expected
            reference = samples
        } else {
            let deviation = expected - referenceEnd
            if deviation > toleranceSamples {
                // Audio is missing (ScreenCaptureKit drops some when its
                // queue is full): silence in its place.
                if deviation >= historySamples {
                    reference.removeAll(keepingCapacity: true)
                    referenceBase = expected
                } else {
                    reference.append(contentsOf: repeatElement(0, count: deviation))
                }
            } else if deviation < -toleranceSamples {
                // Earlier than the samples counted so far say: the chunk
                // goes where its own time puts it.
                reference.removeLast(min(reference.count, -deviation))
                if reference.isEmpty {
                    referenceBase = expected
                }
            }
            reference.append(contentsOf: samples)
        }
        if reference.count > 2 * historySamples {
            let extra = reference.count - historySamples
            reference.removeFirst(extra)
            referenceBase += extra
        }
        return advance(now: now)
    }

    /// Microphone audio whose first sample was captured at `capturedAt`;
    /// `now` is the time it arrived. Gives back the audio that is ready.
    mutating func pushMicrophone(_ samples: [Int16], capturedAt: TimeInterval, now: TimeInterval) -> [Chunk] {
        guard !samples.isEmpty else {
            return []
        }
        _ = index(of: capturedAt)
        let position = incoming.firstIndex { $0.capturedAt > capturedAt } ?? incoming.count
        incoming.insert(Incoming(samples: samples, capturedAt: capturedAt, arrivedAt: now), at: position)
        return advance(now: now)
    }

    /// The end of the recording: everything still held, with the reference
    /// that is there.
    mutating func finish(now: TimeInterval) -> [Chunk] {
        var chunks: [Chunk] = []
        release(incoming.count, now: now, into: &chunks)
        drain(now: now, into: &chunks)
        flush(into: &chunks)
        return chunks
    }

    // MARK: - Internals

    private var referenceEnd: Int {
        referenceBase + reference.count
    }

    private mutating func index(of time: TimeInterval) -> Int {
        let start = origin ?? time
        origin = start
        return Int(((time - start) * Double(sampleRate)).rounded())
    }

    private func time(of index: Int) -> TimeInterval {
        (origin ?? 0) + Double(index) / Double(sampleRate)
    }

    private mutating func advance(now: TimeInterval) -> [Chunk] {
        var chunks: [Chunk] = []
        // A chunk that has waited the reorder window goes on, with every
        // chunk captured before it.
        if let last = incoming.lastIndex(where: { now - $0.arrivedAt >= settings.reorderWindow }) {
            release(last + 1, now: now, into: &chunks)
        }
        process(now: now, forced: false, into: &chunks)
        if ready.count >= outputSamples {
            flush(into: &chunks)
        }
        return chunks
    }

    /// Moves the first `count` waiting chunks, in capture order, to the
    /// audio that waits for its reference.
    private mutating func release(_ count: Int, now: TimeInterval, into chunks: inout [Chunk]) {
        guard count > 0 else {
            return
        }
        let released = Array(incoming.prefix(count))
        incoming.removeFirst(count)
        for chunk in released {
            place(chunk, now: now, into: &chunks)
        }
    }

    private mutating func place(_ chunk: Incoming, now: TimeInterval, into chunks: inout [Chunk]) {
        let expected = index(of: chunk.capturedAt)
        guard microphoneStarted else {
            microphoneStarted = true
            pendingIndex = expected
            pending = chunk.samples
            return
        }
        let deviation = expected - (pendingIndex + pending.count)
        if deviation > toleranceSamples {
            if deviation <= maximumFillSamples {
                // The microphone delivered nothing for a moment: silence,
                // so that what follows stays at its own time.
                pending.append(contentsOf: repeatElement(0, count: deviation))
                statistics.filledSamples += deviation
            } else {
                // Too long to fill: the audio so far ends here and the
                // microphone starts again at its own time.
                drain(now: now, into: &chunks)
                flush(into: &chunks)
                pendingIndex = expected
            }
        } else if deviation < -toleranceSamples {
            if -deviation >= chunk.samples.count {
                // Wholly before audio already placed: it came after the
                // reorder window and its place has been taken.
                statistics.lateChunks += 1
                return
            }
            // Earlier than the samples counted so far say: the audio is
            // kept, and the times of what is still held move back with it.
            pendingIndex += deviation
        }
        pending.append(contentsOf: chunk.samples)
    }

    /// Processes the frames whose reference is there (all full frames when
    /// `forced`).
    private mutating func process(now: TimeInterval, forced: Bool, into chunks: inout [Chunk]) {
        var offset = 0
        while pending.count - offset >= frame {
            let index = pendingIndex + offset
            // One past the last reference sample this frame is given.
            let needed = index + advanceSamples + frame
            let covered = referenceStart != nil && referenceEnd >= needed
            // Before the system audio began: nothing will come for it.
            let neverComes = referenceStart.map { needed <= $0 } ?? false
            let held = now - time(of: index + frame)
            guard forced || covered || neverComes || held >= settings.maximumHold else {
                break
            }
            let microphone = Array(pending[offset..<offset + frame])
            let call = referenceFrame(from: index + advanceSamples)
            let cleaned = canceller.process(reference: call, microphone: microphone)
            stretchHasAudio = true

            statistics.frames += 1
            if !covered, !neverComes {
                statistics.framesWithoutReference += 1
            }
            statistics.longestHold = max(statistics.longestHold, held)
            statistics.totalHold += max(0, held)
            if Self.power(call) > Self.callPower {
                statistics.framesWithCall += 1
                statistics.powerBefore += Self.power(microphone)
                statistics.powerAfter += Self.power(cleaned)
            }
            // What comes back is the audio of `delay` samples earlier.
            append(cleaned, at: index - delay, into: &chunks)
            offset += frame
        }
        if offset > 0 {
            pending.removeFirst(offset)
            pendingIndex += offset
        }
    }

    /// Everything held goes out now, with the reference that is there, and
    /// this stretch of audio ends: exactly the samples that came in.
    private mutating func drain(now: TimeInterval, into chunks: inout [Chunk]) {
        process(now: now, forced: true, into: &chunks)
        var padding = 0
        if !pending.isEmpty {
            // The last part of a frame: processed with silence after it.
            padding = frame - pending.count
            pending.append(contentsOf: repeatElement(0, count: padding))
            process(now: now, forced: true, into: &chunks)
        }
        guard stretchHasAudio else {
            return
        }
        stretchHasAudio = false
        if padding >= delay {
            // More came back than came in: the silence after it goes again.
            ready.removeLast(min(padding - delay, ready.count))
        } else {
            // The canceller still holds the last of the audio: silence
            // pushes it out.
            var missing = delay - padding
            var index = pendingIndex - delay
            let silence = [Int16](repeating: 0, count: frame)
            while missing > 0 {
                let tail = canceller.process(reference: silence, microphone: silence)
                let count = min(missing, tail.count)
                guard count > 0 else {
                    break
                }
                append(Array(tail.prefix(count)), at: index, into: &chunks)
                index += tail.count
                missing -= count
            }
        }
        // What the canceller holds now is silence: the next stretch's first
        // output is not its own.
        discard = delay
    }

    /// The reference for one frame; silence where there is none.
    private func referenceFrame(from start: Int) -> [Int16] {
        var result = [Int16](repeating: 0, count: frame)
        let lower = max(start, referenceBase)
        let upper = min(start + frame, referenceEnd)
        if lower < upper {
            result.replaceSubrange((lower - start)..<(upper - start), with: reference[(lower - referenceBase)..<(upper - referenceBase)])
        }
        return result
    }

    private mutating func append(_ samples: [Int16], at index: Int, into chunks: inout [Chunk]) {
        var samples = samples
        var index = index
        if discard > 0 {
            let dropped = min(discard, samples.count)
            samples.removeFirst(dropped)
            index += dropped
            discard -= dropped
            guard !samples.isEmpty else {
                return
            }
        }
        if !ready.isEmpty, abs(index - (readyIndex + ready.count)) > toleranceSamples {
            flush(into: &chunks)
        }
        if ready.isEmpty {
            readyIndex = index
        }
        ready.append(contentsOf: samples)
    }

    private mutating func flush(into chunks: inout [Chunk]) {
        guard !ready.isEmpty else {
            return
        }
        chunks.append(Chunk(samples: ready, capturedAt: time(of: readyIndex)))
        ready.removeAll(keepingCapacity: true)
    }

    private static func power(_ samples: [Int16]) -> Double {
        guard !samples.isEmpty else {
            return 0
        }
        return samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
    }
}

/// The meeting's echo cancellation: takes the microphone and the system
/// audio as they arrive (from their own threads) and gives back the
/// microphone without the call's sound, in capture order, on one queue.
final class MeetingEchoCanceller: @unchecked Sendable {
    typealias Output = @Sendable (_ pcm: Data, _ capturedAt: TimeInterval) -> Void

    private let queue = DispatchQueue(label: "untype.meeting.echo-canceller")
    private var aligner: MeetingEchoAligner
    private var finished = false
    private let onOutput: Output

    /// `onOutput` gets the cleaned microphone audio (PCM16 mono) with the
    /// time its first sample was captured, on this canceller's queue.
    init(
        sampleRate: Int,
        canceller: EchoCancelling,
        settings: MeetingEchoAligner.Settings = MeetingEchoAligner.Settings(),
        onOutput: @escaping Output
    ) {
        aligner = MeetingEchoAligner(sampleRate: sampleRate, canceller: canceller, settings: settings)
        self.onOutput = onOutput
    }

    /// With WebRTC's canceller; nil when it cannot be made for this rate.
    static func make(sampleRate: Int, onOutput: @escaping Output) -> MeetingEchoCanceller? {
        guard let canceller = WebRTCEchoCanceller(sampleRate: sampleRate) else {
            return nil
        }
        return MeetingEchoCanceller(sampleRate: sampleRate, canceller: canceller, onOutput: onOutput)
    }

    /// System audio (PCM16 mono) whose first sample was captured at `capturedAt`.
    func pushReference(_ pcm: Data, capturedAt: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            guard !finished else {
                return
            }
            deliver(aligner.pushReference(MeetingAudioRecorder.samples(pcm), capturedAt: capturedAt, now: now))
        }
    }

    /// Microphone audio (PCM16 mono) whose first sample was captured at `capturedAt`.
    func pushMicrophone(_ pcm: Data, capturedAt: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            guard !finished else {
                return
            }
            deliver(aligner.pushMicrophone(MeetingAudioRecorder.samples(pcm), capturedAt: capturedAt, now: now))
        }
    }

    /// Gives back everything still held and says what was done. Audio
    /// pushed afterwards is ignored.
    func finish() -> MeetingEchoStatistics {
        queue.sync {
            if !finished {
                finished = true
                deliver(aligner.finish(now: ProcessInfo.processInfo.systemUptime))
            }
            return aligner.statistics
        }
    }

    private func deliver(_ chunks: [MeetingEchoAligner.Chunk]) {
        for chunk in chunks {
            onOutput(chunk.samples.withUnsafeBufferPointer { Data(buffer: $0) }, chunk.capturedAt)
        }
    }
}
#endif
