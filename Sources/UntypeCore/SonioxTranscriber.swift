import Foundation

public struct RealtimeWebSocketHandlers: Sendable {
    public let text: @Sendable (_ text: String) async -> Void
    public let error: @Sendable (_ error: Error) async -> Void
    public let closed: @Sendable () async -> Void

    public init(
        text: @escaping @Sendable (_ text: String) async -> Void = { _ in },
        error: @escaping @Sendable (_ error: Error) async -> Void = { _ in },
        closed: @escaping @Sendable () async -> Void = {}
    ) {
        self.text = text
        self.error = error
        self.closed = closed
    }
}

/// The server closed the socket and gave a reason.
public struct RealtimeWebSocketCloseError: LocalizedError, Equatable, Sendable {
    public let code: Int
    public let reason: String

    public init(code: Int, reason: String) {
        self.code = code
        self.reason = reason
    }

    public var errorDescription: String? {
        "The server closed the connection (\(code)): \(reason)"
    }
}

public protocol RealtimeWebSocketClient: AnyObject {
    func setHandlers(_ handlers: RealtimeWebSocketHandlers)
    func connect() async throws
    func sendText(_ text: String) async throws
    func sendBinary(_ data: Data) async throws
    func close()
}

public final class URLSessionRealtimeWebSocketClient: RealtimeWebSocketClient, @unchecked Sendable {
    private let request: URLRequest
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var handlers = RealtimeWebSocketHandlers()
    private var closing = false

    public init(url: URL, session: URLSession = .shared) {
        self.request = URLRequest(url: url)
        self.session = session
    }

    public init(request: URLRequest, session: URLSession = .shared) {
        self.request = request
        self.session = session
    }

    public func setHandlers(_ handlers: RealtimeWebSocketHandlers) {
        self.handlers = handlers
    }

    public func connect() async throws {
        guard task == nil else {
            throw UntypeError.sonioxProtocol("WebSocket client connect() called more than once.")
        }
        closing = false
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task)
        }
    }

    public func sendText(_ text: String) async throws {
        guard let task else {
            throw UntypeError.sonioxNetwork("WebSocket is not connected.")
        }
        try await task.send(.string(text))
    }

    public func sendBinary(_ data: Data) async throws {
        guard let task else {
            throw UntypeError.sonioxNetwork("WebSocket is not connected.")
        }
        try await task.send(.data(data))
    }

    public func close() {
        guard !closing else {
            return
        }
        closing = true
        receiveTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    /// What the server said when it closed the socket, when it said anything:
    /// some providers report a wrong key or model only this way.
    private static func closeError(of task: URLSessionWebSocketTask) -> RealtimeWebSocketCloseError? {
        guard task.closeCode != .invalid,
              let data = task.closeReason,
              let reason = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else {
            return nil
        }
        return RealtimeWebSocketCloseError(code: task.closeCode.rawValue, reason: reason)
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    await handlers.text(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handlers.text(text)
                    }
                @unknown default:
                    await handlers.error(UntypeError.sonioxProtocol("Unexpected WebSocket message type."))
                }
            } catch {
                if !closing && !Task.isCancelled {
                    await handlers.error(Self.closeError(of: task) ?? error)
                }
                break
            }
        }

        if !closing {
            await handlers.closed()
        }
    }
}

public struct SonioxTranscriberOptions: Sendable, Equatable {
    public let apiKey: String
    public let model: String
    public let endpoint: String
    public let languages: [String]
    public let sampleRate: Int
    public let enableEndpointDetection: Bool
    public let transcriptionContext: String?
    public let verbose: Bool
    public let finalizeDrainNanoseconds: UInt64
    /// Keep only the user's voice (or learn a sample of it); nil: everyone's
    /// words are transcribed.
    public let voiceFilter: SonioxVoiceFilterMode?

    public init(
        apiKey: String,
        model: String,
        endpoint: String,
        languages: [String],
        sampleRate: Int,
        enableEndpointDetection: Bool,
        transcriptionContext: String? = nil,
        verbose: Bool = false,
        finalizeDrainNanoseconds: UInt64 = 250_000_000,
        voiceFilter: SonioxVoiceFilterMode? = nil
    ) {
        self.voiceFilter = voiceFilter
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.languages = languages
        self.sampleRate = sampleRate
        self.enableEndpointDetection = enableEndpointDetection
        self.transcriptionContext = transcriptionContext
        self.verbose = verbose
        self.finalizeDrainNanoseconds = finalizeDrainNanoseconds
    }

    public init(
        config: ResolvedConfig,
        finalizeDrainNanoseconds: UInt64 = 250_000_000,
        voiceFilter: SonioxVoiceFilterMode? = nil
    ) {
        self.init(
            apiKey: config.apiKey,
            model: config.model,
            endpoint: config.endpoint,
            languages: config.languages,
            sampleRate: config.sampleRate,
            enableEndpointDetection: config.enableEndpointDetection,
            transcriptionContext: config.prompts.sonioxTranscriptionContext,
            verbose: config.verbose,
            finalizeDrainNanoseconds: finalizeDrainNanoseconds,
            voiceFilter: voiceFilter
        )
    }
}

public final class SonioxTranscriber: RuntimeTranscriber, @unchecked Sendable {
    private let options: SonioxTranscriberOptions
    private let socket: RealtimeWebSocketClient
    private var handlers: TranscriberEventHandlers?
    private var connected = false
    private var started = false
    private var shuttingDown = false
    private var committedFinals = ""
    /// Only my voice: who said what (nil: the filter is not used).
    private var speakerFilter: UserSpeakerFilter?
    private var utteranceTokens: [VoiceFilterToken] = []
    private var levelMeter: StreamLevelMeter
    private let meterLock = NSLock()
    /// A piece of the user's own audio was seen in this stream.
    private var pastSample = false
    /// Stream time at which the user's own audio starts: the length of the
    /// voice sample sent ahead of it (0: none was sent).
    private var sampleLeadMs = 0
    /// Learning: the audio heard so far, to cut the voice sample from.
    private var learnAudio = Data()
    private static let learnAudioSeconds = 60
    /// What the voice filter dropped or learned (no dictated text).
    public var onVoiceFilterEvent: (@Sendable (VoiceFilterEvent) -> Void)?

    public init(options: SonioxTranscriberOptions, socket: RealtimeWebSocketClient) {
        self.options = options
        self.socket = socket
        self.speakerFilter = options.voiceFilter.map(UserSpeakerFilter.init(mode:))
        self.levelMeter = StreamLevelMeter(sampleRate: options.sampleRate)
    }

    public convenience init(options: SonioxTranscriberOptions) throws {
        guard let url = URL(string: options.endpoint), url.scheme == "wss" || url.scheme == "ws" else {
            throw UntypeError.invalidConfiguration("Soniox endpoint must be a ws:// or wss:// URL. Got: '\(options.endpoint)'.")
        }
        self.init(options: options, socket: URLSessionRealtimeWebSocketClient(url: url))
    }

    public func setHandlers(_ handlers: TranscriberEventHandlers) {
        self.handlers = handlers
    }

    public func start() async throws {
        guard !started else {
            throw UntypeError.sonioxProtocol("SonioxTranscriber.start() called more than once.")
        }
        started = true
        socket.setHandlers(RealtimeWebSocketHandlers(
            text: { [weak self] text in
                await self?.handleTextFrame(text)
            },
            error: { [weak self] error in
                await self?.handleSocketError(error)
            },
            closed: { [weak self] in
                self?.connected = false
            }
        ))

        do {
            try await socket.connect()
            try await socket.sendText(configFrame())
            try await sendVoiceSample()
            connected = true
        } catch let error as UntypeError {
            throw error
        } catch {
            throw UntypeError.sonioxNetwork("Soniox connection failed: \(error.localizedDescription)")
        }
    }

    public func pushAudio(_ pcm: Data) async throws {
        guard connected, !shuttingDown else {
            return
        }
        if speakerFilter != nil {
            measure(pcm)
        }
        do {
            try await socket.sendBinary(pcm)
        } catch let error as UntypeError {
            throw error
        } catch {
            throw UntypeError.sonioxNetwork("Soniox audio send failed: \(error.localizedDescription)")
        }
    }

    /// Only my voice: the user's voice sample goes first and is finished at
    /// once, so its speaker label is known before the user's audio starts.
    private func sendVoiceSample() async throws {
        guard case .filter(let sample)? = options.voiceFilter else {
            return
        }
        guard sample.sampleRate == options.sampleRate else {
            throw UntypeError.invalidConfiguration("The saved voice sample is at \(sample.sampleRate) Hz but the stream is at \(options.sampleRate) Hz. Learn your voice again (Settings → Speech → Learn).")
        }
        let lead = sample.lead
        measure(lead)
        sampleLeadMs = sample.leadMs
        try await socket.sendBinary(lead)
        try await socket.sendText(#"{"type":"finalize"}"#)
    }

    public func commit() async throws {
        guard connected else {
            return
        }
        do {
            try await socket.sendText(#"{"type":"finalize"}"#)
            if options.finalizeDrainNanoseconds > 0 {
                try await Task.sleep(nanoseconds: options.finalizeDrainNanoseconds)
            }
        } catch let error as UntypeError {
            throw error
        } catch {
            throw UntypeError.sonioxProtocol("Soniox finalize failed: \(error.localizedDescription)")
        }
    }

    public func stop() async throws {
        guard !shuttingDown else {
            return
        }
        shuttingDown = true
        reportLearnedVoiceSample()
        guard connected else {
            socket.close()
            return
        }
        do {
            try await commit()
        } catch {
            // Continue to finish/close so shutdown remains best-effort.
        }
        do {
            try await socket.sendText("")
        } catch {
            // The empty finish sentinel is best-effort during shutdown.
        }
        socket.close()
        connected = false
    }

    public func handleTextFrame(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let data = Data(text.utf8)
        let object: [String: Any]
        do {
            let decoded = try JSONSerialization.jsonObject(with: data)
            guard let decodedObject = decoded as? [String: Any] else {
                await dispatchError(.sonioxProtocol("Unexpected Soniox message shape."))
                return
            }
            object = decodedObject
        } catch {
            await dispatchError(.sonioxProtocol("Failed to parse Soniox message JSON: \(error.localizedDescription)"))
            return
        }

        if let serverError = serverError(from: object) {
            await dispatchError(serverError)
            return
        }

        if let tokens = object["tokens"] as? [[String: Any]] {
            let sawUtteranceBoundaryMarker = handleTokens(tokens)
            if sawUtteranceBoundaryMarker {
                await flushCommittedFinals()
            }
        }

        if object["finished"] as? Bool == true {
            await flushCommittedFinals()
            connected = false
            socket.close()
        }
    }

    private func configFrame() throws -> String {
        var object: [String: Any] = [
            "api_key": options.apiKey,
            "model": options.model,
            "audio_format": "pcm_s16le",
            "sample_rate": options.sampleRate,
            "num_channels": 1,
            "enable_endpoint_detection": options.enableEndpointDetection
        ]

        if options.voiceFilter != nil {
            object["enable_speaker_diarization"] = true
        }
        if options.languages.count == 1, options.languages[0] == "auto" {
            object["enable_language_identification"] = true
        } else {
            object["language_hints"] = options.languages
        }
        if let transcriptionContext = options.transcriptionContext,
           !transcriptionContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["context"] = ["text": transcriptionContext]
        }

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw UntypeError.sonioxProtocol("Failed to encode Soniox config frame as UTF-8 JSON.")
        }
        return text
    }

    // Soniox does not send standalone endpoint/finalized frames; the `<end>`
    // (endpoint detected) and `<fin>` (manual finalize complete) markers arrive
    // as tokens inside a regular tokens frame. Returns true when the frame
    // carried such a marker so the caller can flush committed finals — the same
    // event synthesis the official @soniox/node SDK performs.
    private func handleTokens(_ tokens: [[String: Any]]) -> Bool {
        if speakerFilter != nil {
            return handleTokensKeepingOneVoice(tokens)
        }
        var newFinals = ""
        var currentNonFinals = ""
        var sawUtteranceBoundaryMarker = false

        for token in tokens {
            guard let text = token["text"] as? String else {
                continue
            }
            if text == "<end>" || text == "<fin>" {
                sawUtteranceBoundaryMarker = true
                continue
            }
            if token["is_final"] as? Bool == true {
                newFinals += text
            } else {
                currentNonFinals += text
            }
        }

        if !newFinals.isEmpty {
            committedFinals = mergeFinalText(committed: committedFinals, incomingFinals: newFinals)
        }

        let display = committedFinals + currentNonFinals
        if !display.isEmpty {
            handlers?.partial(display)
        }

        return sawUtteranceBoundaryMarker
    }

    /// The same as `handleTokens`, but the pieces of speakers who are not
    /// the user never reach the text.
    private func handleTokensKeepingOneVoice(_ tokens: [[String: Any]]) -> Bool {
        var pending: [VoiceFilterToken] = []
        var sawUtteranceBoundaryMarker = false
        var previousFromSample: Bool?
        for token in tokens {
            guard let text = token["text"] as? String else {
                continue
            }
            if text == "<end>" || text == "<fin>" {
                sawUtteranceBoundaryMarker = true
                continue
            }
            var level: Double?
            let start = token["start_ms"] as? Int
            if text.contains(where: { $0.isLetter || $0.isNumber }),
               let start, let end = token["end_ms"] as? Int {
                meterLock.lock()
                level = levelMeter.levelDb(fromMs: start, toMs: end)
                meterLock.unlock()
            }
            // A piece without a time belongs with the piece before it.
            let fromSample = start.map { $0 < sampleLeadMs } ?? (previousFromSample ?? (sampleLeadMs > 0 && utteranceTokens.isEmpty && !pastSample))
            previousFromSample = fromSample
            if !fromSample {
                pastSample = true
            }
            let piece = VoiceFilterToken(text: text, speaker: Self.speakerLabel(token["speaker"]), levelDb: level, startMs: start, fromSample: fromSample)
            if token["is_final"] as? Bool == true {
                utteranceTokens.append(piece)
                speakerFilter?.record(piece)
            } else {
                pending.append(piece)
            }
        }
        if let speakerFilter {
            committedFinals = speakerFilter.kept(utteranceTokens).map(\.text).joined()
            let display = speakerFilter.kept(utteranceTokens, pending: pending).map(\.text).joined()
            if !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handlers?.partial(display)
            }
        }
        return sawUtteranceBoundaryMarker
    }

    private func measure(_ pcm: Data) {
        meterLock.lock()
        levelMeter.append(pcm)
        if options.voiceFilter == .learn, learnAudio.count < Self.learnAudioSeconds * options.sampleRate * 2 {
            learnAudio.append(pcm)
        }
        meterLock.unlock()
    }

    /// The first seconds of the user's speech in the audio heard while learning.
    private func learnedSample(firstStartMs: Int) -> VoiceSample? {
        meterLock.lock()
        let audio = learnAudio
        meterLock.unlock()
        let bytesPerSecond = options.sampleRate * 2
        let from = min(audio.count, max(0, firstStartMs - 100) * options.sampleRate / 1000 * 2)
        let to = min(audio.count, from + Int(VoiceSample.wantedSeconds * Double(bytesPerSecond)))
        guard Double(to - from) >= VoiceSample.minimumSeconds * Double(bytesPerSecond) else {
            return nil
        }
        return VoiceSample(pcm: audio.subdata(in: from..<to), sampleRate: options.sampleRate)
    }

    private static func speakerLabel(_ value: Any?) -> String? {
        if let label = value as? String {
            return label
        }
        return (value as? Int).map(String.init)
    }

    private func reportLearnedVoiceSample() {
        guard let speakerFilter, speakerFilter.mode == .learn else {
            return
        }
        if let learned = speakerFilter.learned(), learned.words >= UserSpeakerFilter.wordsToLearn,
           let sample = learnedSample(firstStartMs: learned.firstStartMs) {
            onVoiceFilterEvent?(.learned(sample: sample, words: learned.words))
        } else {
            onVoiceFilterEvent?(.notLearned(words: speakerFilter.learned()?.words ?? 0))
        }
    }

    private func flushCommittedFinals() async {
        if let speakerFilter {
            // Decided again with everything heard so far in this stream.
            committedFinals = speakerFilter.kept(utteranceTokens).map(\.text).joined()
            if let summary = speakerFilter.summary(of: utteranceTokens) {
                onVoiceFilterEvent?(.summary(summary))
            }
            utteranceTokens = []
        }
        let text = committedFinals.trimmingCharacters(in: .whitespacesAndNewlines)
        committedFinals = ""
        if !text.isEmpty {
            await handlers?.final(text)
        }
    }

    private func dispatchError(_ error: UntypeError) async {
        await handlers?.error(error)
    }

    private func handleSocketError(_ error: Error) async {
        if let error = error as? UntypeError {
            await dispatchError(error)
        } else {
            await dispatchError(.sonioxNetwork("Soniox WebSocket receive failed: \(error.localizedDescription)"))
        }
        connected = false
    }

    // Real Soniox realtime error frames carry a numeric `error_code` plus an
    // `error_message` string (the same shape the official @soniox/node SDK's
    // mapErrorResponse consumes). There is no `type`/`error_type` field in the
    // live protocol.
    private func serverError(from object: [String: Any]) -> UntypeError? {
        guard object["error_code"] != nil || object["error_message"] != nil else {
            return nil
        }

        let code = object["error_code"] as? Int
        let message = (object["error_message"] as? String)
            ?? "Soniox server returned error code \(code.map(String.init) ?? "unknown")."
        switch code {
        case 401, 403:
            return .sonioxAuth("Soniox authentication failed: \(message)")
        case 503:
            return .sonioxNetwork(message)
        default:
            return .sonioxProtocol(message)
        }
    }
}

private func mergeFinalText(committed: String, incomingFinals: String) -> String {
    if committed.isEmpty {
        return incomingFinals
    }
    if incomingFinals.isEmpty {
        return committed
    }
    if incomingFinals.hasPrefix(committed) {
        return incomingFinals
    }
    if committed.hasSuffix(incomingFinals) {
        return committed
    }
    let overlap = longestSuffixPrefixOverlap(committed, incomingFinals)
    return committed + incomingFinals.dropFirst(overlap)
}

private func longestSuffixPrefixOverlap(_ a: String, _ b: String) -> Int {
    let maximum = min(a.count, b.count)
    guard maximum > 0 else {
        return 0
    }

    for length in stride(from: maximum, through: 1, by: -1) {
        let suffix = String(a.suffix(length))
        let prefix = String(b.prefix(length))
        if suffix == prefix {
            return length
        }
    }
    return 0
}
