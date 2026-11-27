import Foundation
import UntypeCore

/// One Soniox real-time session of a meeting recorded on the iPhone or iPad.
/// The phone's microphone hears everyone in the room, so speakers are told
/// apart (diarization) and the lines are those of the call side of the Mac's
/// meeting transcript ("Speaker 1", "Speaker 2", …). Audio is sent in order
/// by a single task; what arrives before the connection is ready waits.
final class MeetingTranscriptionStream: @unchecked Sendable {
    private let socket: URLSessionRealtimeWebSocketClient
    private let configFrame: String
    private let lock = NSLock()
    private var aggregator: MeetingTokenAggregator
    private let audio: AsyncStream<Data>
    private let audioContinuation: AsyncStream<Data>.Continuation
    private var sender: Task<Void, Never>?
    private var keepalive: Task<Void, Never>?
    private var finished = false
    private var finishWaiter: CheckedContinuation<Void, Never>?
    private let onSegment: @Sendable (MeetingSegment) -> Void
    private let onInProgress: @Sendable (String) -> Void
    private let onError: @Sendable (String) -> Void

    /// `offsetMs`: where in the meeting's audio this stream's audio starts.
    init(
        options: SonioxTranscriberOptions,
        offsetMs: Int,
        onSegment: @escaping @Sendable (MeetingSegment) -> Void,
        onInProgress: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        guard let url = URL(string: options.endpoint), url.scheme == "wss" || url.scheme == "ws" else {
            throw AppError("The Soniox address is not a wss:// address.")
        }
        socket = URLSessionRealtimeWebSocketClient(url: url)
        configFrame = try Self.configFrame(options)
        aggregator = MeetingTokenAggregator(side: .call, offsetMs: offsetMs)
        (audio, audioContinuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        self.onSegment = onSegment
        self.onInProgress = onInProgress
        self.onError = onError
    }

    static func configFrame(_ options: SonioxTranscriberOptions) throws -> String {
        var frame: [String: Any] = [
            "api_key": options.apiKey,
            "model": options.model,
            "audio_format": "pcm_s16le",
            "sample_rate": options.sampleRate,
            "num_channels": 1,
            "language_hints": options.languages,
            "enable_language_identification": true,
            "enable_endpoint_detection": true,
            "enable_speaker_diarization": true,
            "client_reference_id": "untype-ios-meeting"
        ]
        if !options.terms.isEmpty {
            frame["context"] = ["terms": options.terms]
        }
        let data = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppError("The Soniox settings could not be written.")
        }
        return text
    }

    func start() async throws {
        socket.setHandlers(RealtimeWebSocketHandlers(
            text: { [weak self] text in
                self?.handle(text)
            },
            error: { [weak self] error in
                self?.reportError(error.localizedDescription)
            },
            closed: { [weak self] in
                self?.markFinished()
            }
        ))
        do {
            try await socket.connect()
            try await socket.sendText(configFrame)
        } catch {
            throw AppError("Soniox could not be reached: \(error.localizedDescription)")
        }
        let socket = socket
        let audio = audio
        sender = Task {
            for await chunk in audio {
                try? await socket.sendBinary(chunk)
            }
            // End of audio: Soniox finishes the stream and answers `finished`.
            try? await socket.sendText("")
        }
        keepalive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                try? await socket.sendText(#"{"type":"keepalive"}"#)
            }
        }
    }

    func push(_ pcm: Data) {
        audioContinuation.yield(pcm)
    }

    /// Ends the audio, waits (up to 8 s) for Soniox to finish, and returns
    /// the segment still being spoken, if any.
    func finish() async -> MeetingSegment? {
        keepalive?.cancel()
        audioContinuation.finish()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
                return
            }
            finishWaiter = continuation
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self?.markFinished()
            }
        }
        socket.close()
        return lock.withLock { aggregator.flush() }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let code = object["error_code"] {
            reportError(object["error_message"] as? String ?? "error \(code)")
            return
        }
        if let tokens = object["tokens"] as? [[String: Any]] {
            let parsed = MeetingToken.parse(tokens)
            lock.lock()
            let segments = aggregator.add(parsed)
            let speaking = aggregator.inProgressText(with: parsed)
            lock.unlock()
            segments.forEach(onSegment)
            onInProgress(speaking)
        }
        if object["finished"] as? Bool == true {
            markFinished()
        }
    }

    private func reportError(_ message: String) {
        let done = lock.withLock { finished }
        if !done {
            onError(message)
        }
    }

    private func markFinished() {
        lock.lock()
        finished = true
        let waiter = finishWaiter
        finishWaiter = nil
        lock.unlock()
        waiter?.resume()
    }
}
