import Foundation

/// Settings → Speech → Only my voice: dictation keeps the words of the
/// speaker whose loudness matches the user's and drops everyone else's.
public struct VoiceFilterPreferences: Codable, Equatable, Sendable {
    /// The filter is wanted (nil: the default, off).
    public var enabled: Bool?
    /// The loudness of the user's words at the microphone, in dBFS, learned
    /// from a dictation (nil: not learned yet; the filter cannot work).
    public var voiceLevelDb: Double?

    public init(enabled: Bool? = nil, voiceLevelDb: Double? = nil) {
        self.enabled = enabled
        self.voiceLevelDb = voiceLevelDb
    }

    public var isOn: Bool {
        enabled ?? false
    }
}

/// How the Soniox stream treats other people's voices.
public enum SonioxVoiceFilterMode: Equatable, Sendable {
    /// Keep the speakers about as loud as the user (dBFS), drop the others.
    case filter(userLevelDb: Double)
    /// Learning the user's loudness: the loudest speaker is taken as the
    /// user and their level is reported when the stream stops.
    case learn
}

public enum VoiceFilterEvent: Equatable, Sendable {
    /// For the event log (no dictated text).
    case summary(String)
    /// The user's loudness, learned from `words` words.
    case learned(levelDb: Double, words: Int)
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
    /// nil: not measured (punctuation, or a piece without duration).
    public let levelDb: Double?

    public init(text: String, speaker: String?, levelDb: Double?) {
        self.text = text
        self.speaker = speaker
        self.levelDb = levelDb
    }

    var startsWord: Bool {
        text.first?.isWhitespace == true
    }
}

/// Decides, speaker by speaker, whose words are the user's. A speaker is
/// judged by the median loudness of everything they said in this stream,
/// not word by word: single words vary too much.
public struct SpeakerLevelFilter: Equatable, Sendable {
    /// A speaker this much quieter than the user is someone else. Measured:
    /// people around the user were about 20 dB below the user's own level.
    public static let marginDb = 10.0
    /// Words needed before a learned level is trusted.
    public static let wordsToLearn = 5
    private static let keptLevels = 200

    public let mode: SonioxVoiceFilterMode
    /// Loudness of the finished pieces of each speaker.
    private var levels: [String: [Double]] = [:]

    public init(mode: SonioxVoiceFilterMode) {
        self.mode = mode
    }

    /// A finished piece: it counts toward its speaker from now on.
    public mutating func record(_ token: VoiceFilterToken) {
        guard let speaker = token.speaker, let level = token.levelDb else {
            return
        }
        levels[speaker, default: []].append(level)
        if levels[speaker]!.count > Self.keptLevels {
            levels[speaker]!.removeFirst(levels[speaker]!.count - Self.keptLevels)
        }
    }

    /// The median loudness per speaker, counting `pending` pieces (still
    /// being recognised) too.
    public func speakerLevels(pending: [VoiceFilterToken] = []) -> [String: Double] {
        var all = levels
        for token in pending {
            if let speaker = token.speaker, let level = token.levelDb {
                all[speaker, default: []].append(level)
            }
        }
        return all.mapValues { values in
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
    }

    /// The speakers whose words are kept. A speaker not measured yet is kept.
    public func acceptedSpeakers(pending: [VoiceFilterToken] = []) -> (levels: [String: Double], accepted: Set<String>) {
        let medians = speakerLevels(pending: pending)
        switch mode {
        case .filter(let userLevelDb):
            return (medians, Set(medians.filter { $0.value >= userLevelDb - Self.marginDb }.keys))
        case .learn:
            let loudest = medians.max { $0.value < $1.value }?.key
            return (medians, loudest.map { [$0] } ?? [])
        }
    }

    /// `finished` and `pending` without the pieces of other speakers.
    public func kept(_ finished: [VoiceFilterToken], pending: [VoiceFilterToken] = []) -> [VoiceFilterToken] {
        let decision = acceptedSpeakers(pending: pending)
        return (finished + pending).filter { token in
            guard let speaker = token.speaker, decision.levels[speaker] != nil else {
                return true
            }
            return decision.accepted.contains(speaker)
        }
    }

    /// Learning: the loudest speaker's level and how many words it rests on.
    public func learned() -> (levelDb: Double, words: Int)? {
        let medians = speakerLevels()
        guard let loudest = medians.max(by: { $0.value < $1.value }) else {
            return nil
        }
        return (loudest.value, levels[loudest.key]?.count ?? 0)
    }

    /// What was dropped, for the event log: numbers only.
    public func summary(of finished: [VoiceFilterToken]) -> String? {
        let decision = acceptedSpeakers()
        func words(_ tokens: [VoiceFilterToken]) -> Int {
            tokens.filter { $0.startsWord && $0.levelDb != nil }.count
        }
        let dropped = finished.filter { token in
            token.speaker.map { decision.levels[$0] != nil && !decision.accepted.contains($0) } ?? false
        }
        guard !dropped.isEmpty else {
            return nil
        }
        let speakers = decision.levels.sorted { $0.value > $1.value }.map { speaker, level in
            "speaker \(speaker) at \(Int(level.rounded())) dB \(decision.accepted.contains(speaker) ? "kept" : "dropped")"
        }
        let keptWords = words(finished) - words(dropped)
        return "only my voice: about \(max(0, keptWords)) words kept, \(max(1, words(dropped))) dropped (\(speakers.joined(separator: "; ")))"
    }
}
