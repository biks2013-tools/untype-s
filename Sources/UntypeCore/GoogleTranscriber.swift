import Foundation

public struct GoogleTranscriberOptions: Sendable, Equatable {
    public let apiKey: String
    public let model: String
    public let endpoint: String
    public let languages: [String]
    public let sampleRate: Int
    public let enableEndpointDetection: Bool
    public let verbose: Bool
    public let commitDrainNanoseconds: UInt64
    /// How long the server may take to accept the session setup.
    public let setupTimeoutNanoseconds: UInt64
    /// A connection this old is replaced at the next quiet moment.
    public let rotateWhenQuietAfterSeconds: TimeInterval
    /// A connection this old is replaced even in the middle of speech.
    public let rotateAlwaysAfterSeconds: TimeInterval

    public init(
        apiKey: String,
        model: String,
        endpoint: String,
        languages: [String],
        sampleRate: Int,
        enableEndpointDetection: Bool,
        verbose: Bool = false,
        commitDrainNanoseconds: UInt64 = 250_000_000,
        setupTimeoutNanoseconds: UInt64 = 10_000_000_000,
        rotateWhenQuietAfterSeconds: TimeInterval = 420,
        rotateAlwaysAfterSeconds: TimeInterval = 560
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.languages = languages
        self.sampleRate = sampleRate
        self.enableEndpointDetection = enableEndpointDetection
        self.verbose = verbose
        self.commitDrainNanoseconds = commitDrainNanoseconds
        self.setupTimeoutNanoseconds = setupTimeoutNanoseconds
        self.rotateWhenQuietAfterSeconds = rotateWhenQuietAfterSeconds
        self.rotateAlwaysAfterSeconds = rotateAlwaysAfterSeconds
    }

    public init(config: ResolvedConfig) {
        self.init(
            apiKey: config.apiKey,
            model: config.model,
            endpoint: config.endpoint,
            languages: config.languages,
            sampleRate: config.sampleRate,
            enableEndpointDetection: config.enableEndpointDetection,
            verbose: config.verbose
        )
    }
}

/// Realtime transcription with Google's live transcription model
/// (`gemini-3.5-transcribe-live`) over the Gemini Live API.
///
/// The Live API limits a session to 10 minutes and closes one that receives
/// no audio for about a minute, while untype keeps its push-to-talk session
/// warm for hours. So this transcriber replaces its connection on its own
/// before the limit: at a quiet moment when it can (no speech since the last
/// finished sentence), otherwise shortly before the server would cut it. The
/// new connection is opened first and audio moves to it only once it is
/// ready, so nothing is lost at a quiet moment.
///
/// With endpoint detection on, the server detects the end of speech and
/// `commit()` (push-to-talk release) ends the audio stream so the sentence is
/// finalized at once. With endpoint detection off, speech is marked
/// explicitly: it starts with the first audio that is not silence and ends at
/// `commit()`.
public final class GoogleTranscriber: RuntimeTranscriber, @unchecked Sendable {
    /// The audio format the live transcription model takes: 16 kHz PCM16 mono.
    public static let sampleRate = 16_000

    private let options: GoogleTranscriberOptions
    private let makeSocket: () -> RealtimeWebSocketClient
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    private var handlers: TranscriberEventHandlers?
    private var started = false
    private var shuttingDown = false
    /// The connection audio goes to, and its number: events of an older
    /// connection are recognised by theirs.
    private var socket: RealtimeWebSocketClient?
    private var generation = 0
    private var connectedAt = Date.distantPast
    /// Waiters for `setupComplete`, by connection number.
    private var setupWaiters: [Int: CheckedContinuation<Void, Error>] = [:]
    private var setupResults: [Int: Result<Void, Error>] = [:]
    private var rotating = false
    /// Speech was sent that no finished sentence has answered yet.
    private var speechPending = false
    /// Endpoint detection off: an explicit activity is open.
    private var activityOpen = false

    public init(
        options: GoogleTranscriberOptions,
        makeSocket: @escaping () -> RealtimeWebSocketClient,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.options = options
        self.makeSocket = makeSocket
        self.now = now
    }

    public convenience init(options: GoogleTranscriberOptions) throws {
        let request = try Self.request(options: options)
        self.init(options: options, makeSocket: { URLSessionRealtimeWebSocketClient(request: request) })
    }

    /// The key travels in a header, not in the URL, so it stays out of logs
    /// that record request URLs.
    public static func request(options: GoogleTranscriberOptions) throws -> URLRequest {
        guard let components = URLComponents(string: options.endpoint),
              components.scheme == "wss" || components.scheme == "ws",
              components.host != nil,
              let url = components.url else {
            throw UntypeError.invalidConfiguration(
                "Google speech endpoint must be a ws:// or wss:// URL. Got: '\(options.endpoint)'."
            )
        }
        guard options.sampleRate == Self.sampleRate else {
            throw UntypeError.invalidConfiguration(
                "Google speech-to-text takes \(Self.sampleRate) Hz audio. Got: \(options.sampleRate)."
            )
        }
        var request = URLRequest(url: url)
        request.setValue(options.apiKey, forHTTPHeaderField: "x-goog-api-key")
        return request
    }

    public func setHandlers(_ handlers: TranscriberEventHandlers) {
        self.handlers = handlers
    }

    public func start() async throws {
        let alreadyStarted = withLock { () -> Bool in
            if started {
                return true
            }
            started = true
            return false
        }
        guard !alreadyStarted else {
            throw UntypeError.googleSpeechProtocol("GoogleTranscriber.start() called more than once.")
        }
        let connection = try await openConnection()
        withLock {
            socket = connection.socket
            generation = connection.generation
            connectedAt = now()
        }
    }

    public func pushAudio(_ pcm: Data) async throws {
        guard !pcm.isEmpty else {
            return
        }
        let silent = pcm.allSatisfy { $0 == 0 }
        let plan = withLock { () -> (socket: RealtimeWebSocketClient, openActivity: Bool, rotate: Bool)? in
            guard let socket, !shuttingDown else {
                return nil
            }
            var openActivity = false
            if !silent {
                speechPending = true
                if !options.enableEndpointDetection, !activityOpen {
                    activityOpen = true
                    openActivity = true
                }
            }
            let age = now().timeIntervalSince(connectedAt)
            let quiet = silent && !speechPending
            let due = age >= options.rotateAlwaysAfterSeconds
                || (quiet && age >= options.rotateWhenQuietAfterSeconds)
            let rotate = due && !rotating
            if rotate {
                rotating = true
            }
            return (socket, openActivity, rotate)
        }
        guard let plan else {
            return
        }
        if plan.rotate {
            Task { [weak self] in
                await self?.rotateConnection()
            }
        }
        do {
            if plan.openActivity {
                try await plan.socket.sendText(Self.activityStartFrame)
            }
            try await plan.socket.sendText(try audioFrame(pcm))
        } catch {
            throw mapError(error, during: "audio send")
        }
    }

    public func commit() async throws {
        let plan = withLock { () -> (socket: RealtimeWebSocketClient, frame: String)? in
            guard let socket else {
                return nil
            }
            // What was spoken is being finished now: the connection counts
            // as quiet again even when no sentence comes back.
            speechPending = false
            if options.enableEndpointDetection {
                return (socket, Self.audioStreamEndFrame)
            }
            guard activityOpen else {
                return nil
            }
            activityOpen = false
            return (socket, Self.activityEndFrame)
        }
        guard let plan else {
            return
        }
        do {
            try await plan.socket.sendText(plan.frame)
            if options.commitDrainNanoseconds > 0 {
                try await Task.sleep(nanoseconds: options.commitDrainNanoseconds)
            }
        } catch {
            throw mapError(error, during: "commit")
        }
    }

    public func stop() async throws {
        let wasRunning = withLock { () -> Bool in
            if shuttingDown {
                return false
            }
            shuttingDown = true
            return true
        }
        guard wasRunning else {
            return
        }
        do {
            try await commit()
        } catch {
            // The final commit is best-effort during shutdown.
        }
        let (current, waiters) = withLock { () -> (RealtimeWebSocketClient?, [CheckedContinuation<Void, Error>]) in
            let current = socket
            socket = nil
            let waiters = Array(setupWaiters.values)
            setupWaiters.removeAll()
            return (current, waiters)
        }
        for waiter in waiters {
            waiter.resume(throwing: CancellationError())
        }
        current?.close()
    }

    // MARK: Connections

    private struct Connection {
        let socket: RealtimeWebSocketClient
        let generation: Int
    }

    /// Opens a connection and returns once the server accepted its setup.
    private func openConnection() async throws -> Connection {
        let socket = makeSocket()
        let number = withLock { () -> Int in
            generationCounter += 1
            return generationCounter
        }
        socket.setHandlers(RealtimeWebSocketHandlers(
            text: { [weak self] text in
                await self?.handleTextFrame(text, generation: number)
            },
            error: { [weak self] error in
                await self?.handleSocketError(error, generation: number)
            },
            closed: { [weak self] in
                await self?.handleSocketClosed(generation: number)
            }
        ))
        do {
            try await socket.connect()
            try await socket.sendText(try setupFrame())
            try await waitForSetup(generation: number)
        } catch {
            socket.close()
            throw mapError(error, during: "connection")
        }
        return Connection(socket: socket, generation: number)
    }

    private var generationCounter = 0

    private func waitForSetup(generation number: Int) async throws {
        let timeout = options.setupTimeoutNanoseconds
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled else {
                return
            }
            self?.finishSetup(
                generation: number,
                result: .failure(UntypeError.googleSpeechNetwork(
                    "Google speech-to-text did not accept the session within \(timeout / 1_000_000_000) s."
                ))
            )
        }
        defer {
            timer.cancel()
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let early = withLock { () -> Result<Void, Error>? in
                if let result = setupResults.removeValue(forKey: number) {
                    return result
                }
                setupWaiters[number] = continuation
                return nil
            }
            if let early {
                continuation.resume(with: early)
            }
        }
    }

    private func finishSetup(generation number: Int, result: Result<Void, Error>) {
        let waiter = withLock { () -> CheckedContinuation<Void, Error>? in
            if let waiter = setupWaiters.removeValue(forKey: number) {
                return waiter
            }
            if setupResults[number] == nil {
                setupResults[number] = result
            }
            return nil
        }
        waiter?.resume(with: result)
    }

    /// Replaces the connection: the new one is opened first, audio moves to
    /// it once it is ready, and the old one stays open a moment longer so a
    /// sentence it was finishing still arrives.
    private func rotateConnection() async {
        defer {
            withLock { rotating = false }
        }
        let connection: Connection
        do {
            connection = try await openConnection()
        } catch {
            // The old connection still works; the server ends it at its
            // limit and the session is restarted then.
            return
        }
        let previous = withLock { () -> (socket: RealtimeWebSocketClient?, activityWasOpen: Bool)? in
            guard !shuttingDown else {
                return nil
            }
            let previous = socket
            let activityWasOpen = activityOpen
            socket = connection.socket
            generation = connection.generation
            connectedAt = now()
            return (previous, activityWasOpen)
        }
        guard let previous else {
            connection.socket.close()
            return
        }
        // Speech in progress carries over: it ends on the old connection and
        // goes on, on the new one.
        if previous.activityWasOpen {
            try? await connection.socket.sendText(Self.activityStartFrame)
            try? await previous.socket?.sendText(Self.activityEndFrame)
        } else if options.enableEndpointDetection {
            try? await previous.socket?.sendText(Self.audioStreamEndFrame)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        previous.socket?.close()
    }

    // MARK: Frames

    private static let audioStreamEndFrame = #"{"realtimeInput":{"audioStreamEnd":true}}"#
    private static let activityStartFrame = #"{"realtimeInput":{"activityStart":{}}}"#
    private static let activityEndFrame = #"{"realtimeInput":{"activityEnd":{}}}"#

    func setupFrame() throws -> String {
        var transcription: [String: Any] = [:]
        if !(options.languages.count == 1 && options.languages[0] == "auto") {
            transcription["languageCodes"] = options.languages
        }
        var setup: [String: Any] = [
            "model": options.model.hasPrefix("models/") ? options.model : "models/\(options.model)",
            "generationConfig": ["responseModalities": ["TEXT"]],
            "inputAudioTranscription": transcription
        ]
        if !options.enableEndpointDetection {
            setup["realtimeInputConfig"] = ["automaticActivityDetection": ["disabled": true]]
        }
        return try encode(["setup": setup])
    }

    private func audioFrame(_ pcm: Data) throws -> String {
        try encode([
            "realtimeInput": [
                "audio": [
                    "data": pcm.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=\(options.sampleRate)"
                ]
            ]
        ])
    }

    private func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let text = String(data: data, encoding: .utf8) else {
            throw UntypeError.googleSpeechProtocol("Failed to encode a Google speech frame as UTF-8 JSON.")
        }
        return text
    }

    // MARK: Server events

    /// For tests: a frame of the current connection.
    public func handleTextFrame(_ text: String) async {
        await handleTextFrame(text, generation: withLock { generation })
    }

    func handleTextFrame(_ text: String, generation number: Int) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            await dispatchError(.googleSpeechProtocol("Google speech-to-text returned a message that is not a JSON object."), generation: number)
            return
        }
        if object["setupComplete"] != nil {
            finishSetup(generation: number, result: .success(()))
            return
        }
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "unknown error"
            await dispatchError(Self.classify(message), generation: number)
            return
        }
        if object["goAway"] != nil {
            // The server is about to end this connection: replace it now.
            let rotate = withLock { () -> Bool in
                guard number == generation, !rotating, !shuttingDown else {
                    return false
                }
                rotating = true
                return true
            }
            if rotate {
                Task { [weak self] in
                    await self?.rotateConnection()
                }
            }
            return
        }
        guard let content = object["serverContent"] as? [String: Any] else {
            return
        }
        // Sentences are taken from an older connection too: after a
        // replacement it may still be finishing one.
        if let interim = (content["interimInputTranscription"] as? [String: Any])?["text"] as? String,
           !interim.isEmpty {
            handlers?.partial(interim)
        }
        if let final = (content["inputTranscription"] as? [String: Any])?["text"] as? String {
            let finalText = final.trimmingCharacters(in: .whitespacesAndNewlines)
            withLock { speechPending = false }
            if !finalText.isEmpty {
                await handlers?.final(finalText)
            }
        }
    }

    private func handleSocketError(_ error: Error, generation number: Int) async {
        let mapped = mapError(error, during: "stream")
        finishSetup(generation: number, result: .failure(mapped))
        await dispatchError(mapped, generation: number)
    }

    private func handleSocketClosed(generation number: Int) async {
        let mapped = UntypeError.googleSpeechNetwork("Google speech-to-text closed the stream.")
        finishSetup(generation: number, result: .failure(mapped))
        await dispatchError(mapped, generation: number)
    }

    /// Reports an error of the connection in use; one of a connection that
    /// was replaced, or is still being set up, concerns nobody else.
    private func dispatchError(_ error: UntypeError, generation number: Int) async {
        let current = withLock { () -> Bool in
            guard number == generation, socket != nil, !shuttingDown else {
                return false
            }
            socket = nil
            return true
        }
        if current {
            await handlers?.error(error)
        }
    }

    private func mapError(_ error: Error, during phase: String) -> UntypeError {
        if let error = error as? UntypeError {
            return error
        }
        if let close = error as? RealtimeWebSocketCloseError {
            return Self.classify(close.reason)
        }
        return .googleSpeechNetwork("Google speech-to-text \(phase) failed: \(error.localizedDescription)")
    }

    /// A wrong key and a wrong model need the user, so they are not retried.
    static func classify(_ message: String) -> UntypeError {
        let lower = message.lowercased()
        if lower.contains("api key") || lower.contains("permission") || lower.contains("unauthenticated")
            || lower.contains("unauthorized") || lower.contains("forbidden") {
            return .googleSpeechAuth("Google speech-to-text authentication failed: \(message)")
        }
        if lower.contains("is not found") || lower.contains("not supported") || lower.contains("invalid argument") {
            return .invalidConfiguration("Google speech-to-text refused the session: \(message)")
        }
        return .googleSpeechNetwork("Google speech-to-text closed the stream: \(message)")
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
