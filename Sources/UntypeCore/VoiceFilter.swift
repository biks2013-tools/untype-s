import Foundation

/// Settings → Speech → Only my voice: dictation keeps the words of the
/// speaker whose voice matches the user's saved voice sample and drops
/// everyone else's.
public struct VoiceFilterPreferences: Codable, Equatable, Sendable {
    /// The filter is wanted (nil: the default, off).
    public var enabled: Bool?

    public init(enabled: Bool? = nil) {
        self.enabled = enabled
    }

    public var isOn: Bool {
        enabled ?? false
    }
}

/// A few seconds of the user's voice (PCM16 little-endian mono). It is sent
/// at the start of every filtered stream, so the provider's speaker label of
/// the user is known: the label it gives the sample.
public struct VoiceSample: Equatable, Sendable {
    /// How much of the user's speech is kept as the sample.
    public static let wantedSeconds = 4.0
    /// Less than this is not enough to name a speaker.
    public static let minimumSeconds = 2.0
    /// Silence sent after the sample, so its last word is not cut.
    public static let trailingSilenceMs = 200

    public let pcm: Data
    public let sampleRate: Int

    public init(pcm: Data, sampleRate: Int) {
        self.pcm = pcm
        self.sampleRate = sampleRate
    }

    public var seconds: Double {
        Double(pcm.count / 2) / Double(max(1, sampleRate))
    }

    /// The sample followed by the silence, as sent to the provider.
    var lead: Data {
        pcm + Data(count: sampleRate * Self.trailingSilenceMs / 1000 * 2)
    }

    /// Stream time at which the user's own audio starts.
    var leadMs: Int {
        lead.count / 2 * 1000 / max(1, sampleRate)
    }
}

/// The saved voice sample: `~/.tool-agents/untype/voice-sample.wav`, readable
/// by the user only. It never leaves the Mac except as the start of a
/// filtered stream to the speech provider.
public enum VoiceSampleStore {
    public static func path(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".tool-agents").appendingPathComponent("untype").appendingPathComponent("voice-sample.wav")
    }

    /// nil: no sample was learned yet.
    public static func load(from url: URL = path()) throws -> VoiceSample? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        func field<T: FixedWidthInteger>(_ offset: Int, _: T.Type) -> T {
            data.subdata(in: offset..<(offset + MemoryLayout<T>.size)).withUnsafeBytes { T(littleEndian: $0.loadUnaligned(as: T.self)) }
        }
        guard data.count > 44,
              String(data: data.subdata(in: 0..<4), encoding: .ascii) == "RIFF",
              String(data: data.subdata(in: 8..<16), encoding: .ascii) == "WAVEfmt ",
              String(data: data.subdata(in: 36..<40), encoding: .ascii) == "data",
              field(20, UInt16.self) == 1, field(22, UInt16.self) == 1, field(34, UInt16.self) == 16 else {
            throw UntypeError.invalidConfiguration("The saved voice sample (\(url.path)) is not a file untype wrote. Learn your voice again (Settings → Speech → Learn).")
        }
        return VoiceSample(pcm: data.subdata(in: 44..<data.count), sampleRate: Int(field(24, UInt32.self)))
    }

    public static func save(_ sample: VoiceSample, to url: URL = path()) throws {
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        put(UInt32(36 + sample.pcm.count))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(sample.sampleRate)); put(UInt32(sample.sampleRate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        put(UInt32(sample.pcm.count))
        data.append(sample.pcm)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// How the Soniox stream treats other people's voices.
public enum SonioxVoiceFilterMode: Equatable, Sendable {
    /// Keep the speaker of this voice sample, drop the others.
    case filter(sample: VoiceSample)
    /// Learning the user's voice: the speaker who says the most is taken as
    /// the user and a sample of their speech is reported when the stream stops.
    case learn
}

public enum VoiceFilterEvent: Equatable, Sendable {
    /// For the event log (no dictated text).
    case summary(String)
    /// A sample of the user's voice, cut from speech of `words` pieces of words.
    case learned(sample: VoiceSample, words: Int)
    /// Too little speech to learn from.
    case notLearned(words: Int)
}

/// The loudness of the audio sent to the provider, by stream time, so a
/// recognised word can be measured from its start and end times.
public struct StreamLevelMeter: Sendable {
    private static let frameMs = 10
    /// Five minutes: far longer than any word waits to be recognised.
    private static let keptFrames = 30_000

    private let samplesPerFrame: Int
    /// Mean square of each frame (1.0 = full scale).
    private var frames: [Float] = []
    /// Index of `frames[0]` in the stream.
    private var firstFrame = 0
    private var pendingSum = 0.0
    private var pendingSamples = 0

    public init(sampleRate: Int) {
        samplesPerFrame = max(1, sampleRate * Self.frameMs / 1000)
    }

    /// PCM16 little-endian mono, as sent to the provider.
    public mutating func append(_ pcm: Data) {
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for sample in samples {
                let value = Double(Int16(littleEndian: sample)) / 32768
                pendingSum += value * value
                pendingSamples += 1
                if pendingSamples == samplesPerFrame {
                    frames.append(Float(pendingSum / Double(samplesPerFrame)))
                    pendingSum = 0
                    pendingSamples = 0
                }
            }
        }
        if frames.count > Self.keptFrames + 3_000 {
            let drop = frames.count - Self.keptFrames
            frames.removeFirst(drop)
            firstFrame += drop
        }
    }

    /// The level between two stream times, in dBFS; nil when that audio is
    /// not (or no longer) known.
    public func levelDb(fromMs: Int, toMs: Int) -> Double? {
        let from = max(fromMs / Self.frameMs, firstFrame) - firstFrame
        let to = min((toMs + Self.frameMs - 1) / Self.frameMs - firstFrame, frames.count)
        guard toMs > fromMs, from < to else {
            return nil
        }
        var sum = 0.0
        for index in from..<to {
            sum += Double(frames[index])
        }
        return 10 * log10(sum / Double(to - from) + 1e-12)
    }
}

/// One piece of a recognised word with who said it and how loud it was.
public struct VoiceFilterToken: Equatable, Sendable {
    public let text: String
    /// The provider's speaker label; nil when it gave none.
    public let speaker: String?
    /// nil: not measured (punctuation, or a piece without duration). Only
    /// reported in the event log; nothing is decided by loudness.
    public let levelDb: Double?
    /// Where the piece starts in the stream; nil when the provider gave no time.
    public let startMs: Int?
    /// The piece belongs to the voice sample sent ahead of the user's audio.
    public let fromSample: Bool

    public init(text: String, speaker: String?, levelDb: Double? = nil, startMs: Int? = nil, fromSample: Bool = false) {
        self.text = text
        self.speaker = speaker
        self.levelDb = levelDb
        self.startMs = startMs
        self.fromSample = fromSample
    }

    var startsWord: Bool {
        text.first?.isWhitespace == true
    }

    var isSpoken: Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }
}

/// Decides whose words are the user's: those of the speaker the provider
/// heard in the voice sample. Measured: two people at the same loudness are
/// told apart by the provider's speaker labels, not by level.
public struct UserSpeakerFilter: Equatable, Sendable {
    /// Pieces of words needed before a learned sample is trusted.
    public static let wordsToLearn = 5
    private static let keptLevels = 200

    public let mode: SonioxVoiceFilterMode
    /// Finished pieces of the voice sample, per speaker label.
    private var sampleSpeakers: [String: Int] = [:]
    /// Loudness of the finished pieces of each speaker (for the log).
    private var levels: [String: [Double]] = [:]
    /// Finished spoken pieces per speaker, and where each speaker started.
    private var pieces: [String: Int] = [:]
    private var firstStartMs: [String: Int] = [:]

    public init(mode: SonioxVoiceFilterMode) {
        self.mode = mode
    }

    /// A finished piece: it counts toward its speaker from now on.
    public mutating func record(_ token: VoiceFilterToken) {
        guard let speaker = token.speaker, token.isSpoken else {
            return
        }
        if token.fromSample {
            sampleSpeakers[speaker, default: 0] += 1
            return
        }
        pieces[speaker, default: 0] += 1
        if let start = token.startMs, firstStartMs[speaker] == nil {
            firstStartMs[speaker] = start
        }
        if let level = token.levelDb {
            levels[speaker, default: []].append(level)
            if levels[speaker]!.count > Self.keptLevels {
                levels[speaker]!.removeFirst(levels[speaker]!.count - Self.keptLevels)
            }
        }
    }

    /// The user's speaker label, counting `pending` pieces (still being
    /// recognised) too; nil while it is not known.
    public func userSpeaker(pending: [VoiceFilterToken] = []) -> String? {
        switch mode {
        case .filter:
            var counts = sampleSpeakers
            if counts.isEmpty {
                // Until the sample is finished, its pieces in progress name the speaker.
                for token in pending where token.fromSample && token.isSpoken {
                    if let speaker = token.speaker {
                        counts[speaker, default: 0] += 1
                    }
                }
            }
            return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        case .learn:
            var counts = pieces
            for token in pending where token.isSpoken {
                if let speaker = token.speaker {
                    counts[speaker, default: 0] += 1
                }
            }
            return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        }
    }

    /// `finished` and `pending` without the voice sample and without the
    /// pieces of other speakers. While the user's speaker is not known, or a
    /// piece has no speaker label, the piece is kept.
    public func kept(_ finished: [VoiceFilterToken], pending: [VoiceFilterToken] = []) -> [VoiceFilterToken] {
        let user = userSpeaker(pending: pending)
        return (finished + pending).filter { token in
            guard !token.fromSample else {
                return false
            }
            guard let user, let speaker = token.speaker else {
                return true
            }
            return speaker == user
        }
    }

    /// Learning: how many pieces the user said and where they started.
    public func learned() -> (words: Int, firstStartMs: Int)? {
        guard let user = userSpeaker(), let start = firstStartMs[user] else {
            return nil
        }
        return (pieces[user] ?? 0, start)
    }

    /// What was kept and dropped, for the event log: numbers only. nil when
    /// nothing was said.
    public func summary(of finished: [VoiceFilterToken]) -> String? {
        let spoken = finished.filter { !$0.fromSample }
        func words(_ tokens: [VoiceFilterToken]) -> Int {
            tokens.filter { $0.startsWord && $0.isSpoken }.count
        }
        guard words(spoken) > 0 else {
            return nil
        }
        let user = userSpeaker()
        let speakers = pieces.keys.sorted().map { speaker -> String in
            let sorted = (levels[speaker] ?? []).sorted()
            let level = sorted.isEmpty ? "" : " at \(Int(sorted[sorted.count / 2].rounded())) dB"
            guard let user else {
                return "speaker \(speaker)\(level)"
            }
            return speaker == user ? "speaker \(speaker) (you)\(level) kept" : "speaker \(speaker)\(level) dropped"
        }
        guard let user else {
            return "only my voice: your voice sample was not recognised in this stream, nothing was dropped (\(speakers.joined(separator: "; ")))"
        }
        let dropped = spoken.filter { $0.speaker.map { $0 != user } ?? false }
        return "only my voice: about \(words(spoken) - words(dropped)) words kept, \(words(dropped)) dropped (\(speakers.joined(separator: "; ")))"
    }
}
