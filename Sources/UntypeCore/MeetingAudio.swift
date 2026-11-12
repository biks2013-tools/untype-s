@preconcurrency import AVFoundation
import Foundation

/// Which sides of a meeting are saved as audio next to the transcript.
public enum MeetingAudioSources: String, Codable, Sendable, CaseIterable {
    /// No audio is saved (transcript only).
    case none
    /// The microphone and the system audio.
    case both
    case microphone
    case system

    public var title: String {
        switch self {
        case .none: return "Off"
        case .both: return "Microphone and system audio"
        case .microphone: return "Microphone only"
        case .system: return "System audio only"
        }
    }

    func includes(_ side: MeetingSide) -> Bool {
        switch self {
        case .none: return false
        case .both: return true
        case .microphone: return side == .you
        case .system: return side == .call
        }
    }
}

/// How the two sides are saved when both are (`MeetingAudioSources.both`).
public enum MeetingAudioLayout: String, Codable, Sendable, CaseIterable {
    /// One file per side.
    case separate
    /// One file with both sides mixed.
    case mixed

    public var title: String {
        switch self {
        case .separate: return "Separate files"
        case .mixed: return "One mixed file"
        }
    }
}

/// The audio part of the meeting settings.
public struct MeetingAudioSettings: Sendable, Equatable {
    public let sources: MeetingAudioSources
    public let layout: MeetingAudioLayout

    public init(sources: MeetingAudioSources, layout: MeetingAudioLayout) {
        self.sources = sources
        self.layout = layout
    }

    public static let off = MeetingAudioSettings(sources: .none, layout: .separate)

    /// Both sides go into one file.
    public var isMixed: Bool {
        sources == .both && layout == .mixed
    }

    public var summary: String {
        switch sources {
        case .none: return "off"
        case .microphone: return "microphone"
        case .system: return "system audio"
        case .both: return isMixed ? "microphone and system audio, mixed" : "microphone and system audio, separate files"
        }
    }
}

/// Places the chunks of one audio source on the meeting's clock, so the
/// saved audio lines up with the transcript and with the other side: the
/// time before the first chunk, and any gap of half a second or more
/// between chunks, becomes silence.
public struct MeetingAudioTimeline: Sendable {
    public let sampleRate: Int
    public let start: TimeInterval
    /// Samples placed so far (silence included).
    public private(set) var position = 0
    private var started = false

    public init(sampleRate: Int, start: TimeInterval) {
        self.sampleRate = sampleRate
        self.start = start
    }

    /// The silence (in samples) that goes before a chunk of `sampleCount`
    /// samples that arrived at `uptime`; the chunk is then counted as placed.
    public mutating func place(sampleCount: Int, at uptime: TimeInterval) -> Int {
        let expected = max(0, Int(((uptime - start) * Double(sampleRate)).rounded()) - sampleCount)
        var gap = expected - position
        if started, gap < sampleRate / 2 {
            gap = 0
        }
        gap = max(0, gap)
        started = true
        position += gap + sampleCount
        return gap
    }
}

/// Mixes two sources that arrive in chunks at their own pace. Each chunk is
/// added at its place on the meeting's clock; samples are released once both
/// sources have passed them, or when one source is more than `maxLag`
/// samples behind the other.
public struct MeetingAudioMixer: Sendable {
    public let maxLag: Int
    private var base = 0
    private var buffer: [Int32] = []
    private var ends = [0, 0]

    public init(maxLag: Int) {
        self.maxLag = maxLag
    }

    /// Adds `samples` of `source` (0 or 1) at `position` and returns the
    /// mixed samples that are complete.
    public mutating func add(_ samples: [Int16], at position: Int, source: Int) -> [Int16] {
        let end = position + samples.count
        if end > base + buffer.count {
            buffer.append(contentsOf: repeatElement(0, count: end - base - buffer.count))
        }
        for (offset, sample) in samples.enumerated() {
            let index = position + offset - base
            // Before `base`: already released (the source was too far behind).
            if index >= 0 {
                buffer[index] += Int32(sample)
            }
        }
        ends[source] = max(ends[source], end)
        let latest = max(ends[0], ends[1])
        let ready = max(min(ends[0], ends[1]), latest - maxLag)
        return release(upTo: ready)
    }

    /// Everything still held.
    public mutating func finish() -> [Int16] {
        release(upTo: base + buffer.count)
    }

    private mutating func release(upTo position: Int) -> [Int16] {
        let count = min(buffer.count, position - base)
        guard count > 0 else {
            return []
        }
        let mixed = buffer[0..<count].map { Int16(clamping: $0) }
        buffer.removeFirst(count)
        base += count
        return mixed
    }
}

/// Writes PCM16 mono samples to an AAC `.m4a` file.
final class MeetingAudioFileWriter {
    let url: URL
    private var file: AVAudioFile?
    private let format: AVAudioFormat

    init(url: URL, sampleRate: Int) throws {
        self.url = url
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)
        self.file = file
        format = file.processingFormat
    }

    func write(_ samples: [Int16]) throws {
        guard let file, !samples.isEmpty else {
            return
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.int16ChannelData?[0] else {
            throw MeetingError.capture("the audio file buffer could not be made")
        }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buffer)
    }

    func writeSilence(_ count: Int) throws {
        var left = count
        while left > 0 {
            let step = min(left, 16_000)
            try write([Int16](repeating: 0, count: step))
            left -= step
        }
    }

    /// Finishes the file (it is not playable before).
    func close() {
        if #available(macOS 15.0, *) {
            file?.close()
        }
        file = nil
    }
}

/// Saves the audio of a meeting next to its transcript, as the settings ask:
/// one side, both sides in separate files, or both mixed in one file. Audio
/// arrives from the two capture threads; the work is done on one queue. A
/// write error stops the audio (reported once) and never the meeting.
final class MeetingAudioRecorder: @unchecked Sendable {
    let settings: MeetingAudioSettings
    private let queue = DispatchQueue(label: "untype.meeting.audio-file")
    private let onError: @Sendable (String) -> Void
    private var timelines: [MeetingSide: MeetingAudioTimeline]
    private var writers: [MeetingSide: MeetingAudioFileWriter] = [:]
    private var mixedWriter: MeetingAudioFileWriter?
    private var mixer: MeetingAudioMixer
    private var failed = false

    init(
        folder: URL,
        names: MeetingFileNames,
        settings: MeetingAudioSettings,
        sampleRate: Int,
        startUptime: TimeInterval,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        self.settings = settings
        self.onError = onError
        mixer = MeetingAudioMixer(maxLag: sampleRate * 2)
        timelines = [
            .you: MeetingAudioTimeline(sampleRate: sampleRate, start: startUptime),
            .call: MeetingAudioTimeline(sampleRate: sampleRate, start: startUptime)
        ]
        if settings.isMixed {
            mixedWriter = try MeetingAudioFileWriter(
                url: folder.appendingPathComponent(names.mixedAudio),
                sampleRate: sampleRate
            )
        } else {
            if settings.sources.includes(.you) {
                writers[.you] = try MeetingAudioFileWriter(
                    url: folder.appendingPathComponent(names.microphoneAudio),
                    sampleRate: sampleRate
                )
            }
            if settings.sources.includes(.call) {
                writers[.call] = try MeetingAudioFileWriter(
                    url: folder.appendingPathComponent(names.systemAudio),
                    sampleRate: sampleRate
                )
            }
        }
    }

    /// PCM16 mono audio of one side, as it arrived at `uptime`.
    func push(_ pcm: Data, side: MeetingSide, at uptime: TimeInterval) {
        guard settings.sources.includes(side) else {
            return
        }
        queue.async { [self] in
            guard !failed else {
                return
            }
            let samples = Self.samples(pcm)
            guard !samples.isEmpty, var timeline = timelines[side] else {
                return
            }
            let gap = timeline.place(sampleCount: samples.count, at: uptime)
            timelines[side] = timeline
            do {
                if let mixedWriter {
                    let position = timeline.position - samples.count
                    try mixedWriter.write(mixer.add(samples, at: position, source: side == .you ? 0 : 1))
                } else if let writer = writers[side] {
                    try writer.writeSilence(gap)
                    try writer.write(samples)
                }
            } catch {
                fail(error)
            }
        }
    }

    /// Ends the files and returns the ones that were written.
    func finish() -> [URL] {
        queue.sync {
            var urls: [URL] = []
            if let mixedWriter {
                if !failed {
                    do {
                        try mixedWriter.write(mixer.finish())
                    } catch {
                        fail(error)
                    }
                }
                mixedWriter.close()
                urls.append(mixedWriter.url)
            }
            for side in [MeetingSide.you, .call] {
                if let writer = writers[side] {
                    writer.close()
                    urls.append(writer.url)
                }
            }
            mixedWriter = nil
            writers = [:]
            return urls
        }
    }

    private func fail(_ error: Error) {
        guard !failed else {
            return
        }
        failed = true
        onError(error.localizedDescription)
    }

    static func samples(_ pcm: Data) -> [Int16] {
        let count = pcm.count / MemoryLayout<Int16>.size
        guard count > 0 else {
            return []
        }
        return pcm.withUnsafeBytes { raw in
            (0..<count).map { Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self)) }
        }
    }
}
