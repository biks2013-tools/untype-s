import Foundation

/// The meeting's microphone, shared with dictation.
///
/// With echo cancellation on, the meeting captures the microphone through
/// Apple's voice processing. While that runs, a second, unprocessed capture
/// in the same process gets no audio, so push-to-talk cannot keep its own
/// microphone: it takes its audio from here instead (mono PCM16 at
/// `MeetingRecorder.sampleRate`, before the meeting's dictation mute).
public final class MeetingSharedMicrophone: @unchecked Sendable {
    public typealias Listener = @Sendable (_ pcm: Data) -> Void

    private let lock = NSLock()
    private var active = false
    private var listeners: [UUID: Listener] = [:]

    public init() {}

    /// True while the meeting's microphone runs with voice processing.
    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func setActive(_ value: Bool) {
        lock.lock()
        active = value
        lock.unlock()
    }

    /// Nil when the microphone is not shared now.
    public func subscribe(_ listener: @escaping Listener) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard active else {
            return nil
        }
        let id = UUID()
        listeners[id] = listener
        return id
    }

    public func unsubscribe(_ id: UUID) {
        lock.lock()
        listeners[id] = nil
        lock.unlock()
    }

    public func publish(_ pcm: Data) {
        lock.lock()
        let current = active ? Array(listeners.values) : []
        lock.unlock()
        for listener in current {
            listener(pcm)
        }
    }
}

/// A dictation session's microphone while the meeting shares its own.
public final class SharedMicrophoneAudioSource: RuntimeAudioSource, @unchecked Sendable {
    private let shared: MeetingSharedMicrophone
    private let sourceRate: Int
    private let sampleRate: Int
    private var subscription: UUID?
    private var handlers: AudioSourceEventHandlers?

    public init(shared: MeetingSharedMicrophone, sourceRate: Int = MeetingRecorder.sampleRate, sampleRate: Int) {
        self.shared = shared
        self.sourceRate = sourceRate
        self.sampleRate = sampleRate
    }

    public func start(handlers: AudioSourceEventHandlers) async throws {
        guard subscription == nil else {
            throw UntypeError.microphoneCapture("Shared microphone source start() called more than once.")
        }
        self.handlers = handlers
        let id = shared.subscribe { [weak self] pcm in
            self?.handle(pcm)
        }
        guard let id else {
            self.handlers = nil
            throw UntypeError.microphoneCapture("The meeting's microphone is no longer shared; the session starts again with its own microphone.")
        }
        subscription = id
    }

    public func stop() async throws {
        if let subscription {
            shared.unsubscribe(subscription)
        }
        subscription = nil
        handlers = nil
    }

    private func handle(_ pcm: Data) {
        guard let handlers else {
            return
        }
        let audio = Self.resample(pcm, from: sourceRate, to: sampleRate)
        guard !audio.isEmpty else {
            return
        }
        Task {
            await handlers.audio(audio)
        }
    }

    /// Mono PCM16 from one sample rate to another (linear interpolation,
    /// each chunk on its own: enough for speech recognition).
    public static func resample(_ pcm: Data, from: Int, to: Int) -> Data {
        guard from != to, from > 0, to > 0 else {
            return pcm
        }
        let count = pcm.count / 2
        guard count > 0 else {
            return Data()
        }
        let outCount = max(1, Int((Double(count) * Double(to) / Double(from)).rounded()))
        var out = [Int16](repeating: 0, count: outCount)
        pcm.withUnsafeBytes { raw in
            let input = raw.bindMemory(to: Int16.self)
            let step = Double(from) / Double(to)
            for index in 0..<outCount {
                let position = Double(index) * step
                let low = min(count - 1, Int(position))
                let high = min(count - 1, low + 1)
                let fraction = position - Double(low)
                let value = Double(Int16(littleEndian: input[low])) * (1 - fraction) + Double(Int16(littleEndian: input[high])) * fraction
                out[index] = Int16(max(-32768, min(32767, value.rounded()))).littleEndian
            }
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
