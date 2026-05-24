import Foundation

public struct ElevenLabsTranscriberOptions: Sendable, Equatable {
    public let apiKey: String
    public let model: String
    public let endpoint: String
    public let languages: [String]
    public let sampleRate: Int
    public let enableEndpointDetection: Bool
    public let verbose: Bool
    public let commitDrainNanoseconds: UInt64

    public init(
        apiKey: String,
        model: String,
        endpoint: String,
        languages: [String],
        sampleRate: Int,
        enableEndpointDetection: Bool,
        verbose: Bool = false,
        commitDrainNanoseconds: UInt64 = 250_000_000
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.languages = languages
        self.sampleRate = sampleRate
        self.enableEndpointDetection = enableEndpointDetection
        self.verbose = verbose
        self.commitDrainNanoseconds = commitDrainNanoseconds
    }

    public init(config: ResolvedConfig, commitDrainNanoseconds: UInt64 = 250_000_000) {
        self.init(
            apiKey: config.apiKey,
            model: config.model,
            endpoint: config.endpoint,
            languages: config.languages,
            sampleRate: config.sampleRate,
            enableEndpointDetection: config.enableEndpointDetection,
            verbose: config.verbose,
            commitDrainNanoseconds: commitDrainNanoseconds
        )
    }
}

public final class ElevenLabsTranscriber: RuntimeTranscriber, @unchecked Sendable {
    private let options: ElevenLabsTranscriberOptions
    private let socket: RealtimeWebSocketClient
    private var handlers: TranscriberEventHandlers?
    private var connected = false
    private var started = false
    private var shuttingDown = false

    public init(options: ElevenLabsTranscriberOptions, socket: RealtimeWebSocketClient) {
        self.options = options
        self.socket = socket
    }

    public convenience init(options: ElevenLabsTranscriberOptions) throws {
        let request = try Self.request(options: options)
        self.init(options: options, socket: URLSessionRealtimeWebSocketClient(request: request))
    }

    public static func request(options: ElevenLabsTranscriberOptions) throws -> URLRequest {
        guard var components = URLComponents(string: options.endpoint),
              components.scheme == "wss" || components.scheme == "ws",
              components.host != nil else {
            throw UntypeError.invalidConfiguration(
                "ElevenLabs endpoint must be a ws:// or wss:// URL. Got: '\(options.endpoint)'."
            )
        }

        var queryItems = components.queryItems ?? []
        let replacementItems: [URLQueryItem] = [
            URLQueryItem(name: "model_id", value: options.model),
            URLQueryItem(name: "audio_format", value: "pcm_\(options.sampleRate)"),
            URLQueryItem(name: "sample_rate", value: String(options.sampleRate)),
            URLQueryItem(
                name: "commit_strategy",
                value: options.enableEndpointDetection ? "vad" : "manual"
            ),
            URLQueryItem(name: "include_timestamps", value: "false")
        ]
        let replacementNames = Set(replacementItems.map(\.name) + ["language_code"])
        queryItems.removeAll { replacementNames.contains($0.name) }
        queryItems.append(contentsOf: replacementItems)
        if !(options.languages.count == 1 && options.languages[0] == "auto"),
           let languageCode = options.languages.first {
            queryItems.append(URLQueryItem(name: "language_code", value: languageCode))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw UntypeError.invalidConfiguration(
                "ElevenLabs endpoint could not be converted to a WebSocket URL. Got: '\(options.endpoint)'."
            )
        }

        var request = URLRequest(url: url)
        request.setValue(options.apiKey, forHTTPHeaderField: "xi-api-key")
        return request
    }

    public func setHandlers(_ handlers: TranscriberEventHandlers) {
        self.handlers = handlers
    }

    public func start() async throws {
        guard !started else {
            throw UntypeError.elevenLabsProtocol("ElevenLabsTranscriber.start() called more than once.")
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
            connected = true
        } catch let error as UntypeError {
            throw error
        } catch {
            throw mapElevenLabsConnectionError(error)
        }
    }

    public func pushAudio(_ pcm: Data) async throws {
        guard connected, !shuttingDown else {
            return
        }
        do {
            try await socket.sendText(try inputAudioChunk(audio: pcm, commit: nil))
        } catch let error as UntypeError {
            throw error
        } catch {
            throw mapElevenLabsConnectionError(error)
        }
    }

    public func commit() async throws {
        guard connected else {
            return
        }
        do {
            try await socket.sendText(try inputAudioChunk(audio: Data(), commit: true))
            if options.commitDrainNanoseconds > 0 {
                try await Task.sleep(nanoseconds: options.commitDrainNanoseconds)
            }
        } catch let error as UntypeError {
            throw error
        } catch {
            throw mapElevenLabsConnectionError(error)
        }
    }

    public func stop() async throws {
        guard !shuttingDown else {
            return
        }
        shuttingDown = true
        guard connected else {
            socket.close()
            return
        }
        do {
            try await commit()
        } catch {
            // Final commit is best-effort during shutdown.
        }
        socket.close()
        connected = false
    }

    public func handleTextFrame(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let object: [String: Any]
        do {
            let decoded = try JSONSerialization.jsonObject(with: Data(text.utf8))
            guard let decodedObject = decoded as? [String: Any] else {
                await dispatchError(.elevenLabsProtocol("Unexpected ElevenLabs message shape."))
                return
            }
            object = decodedObject
        } catch {
            await dispatchError(.elevenLabsProtocol("ElevenLabs returned non-JSON message."))
            return
        }

        if let serverError = serverError(from: object) {
            await dispatchError(serverError)
            return
        }

        switch messageType(from: object) {
        case "session_started":
            return
        case "partial_transcript":
            if let text = object["text"] as? String, !text.isEmpty {
                handlers?.partial(text)
            }
        case "committed_transcript", "committed_transcript_with_timestamps":
            if let text = object["text"] as? String {
                let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalText.isEmpty {
                    await handlers?.final(finalText)
                }
            }
        default:
            return
        }
    }

    private func inputAudioChunk(audio: Data, commit: Bool?) throws -> String {
        var object: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": audio.base64EncodedString(),
            "sample_rate": options.sampleRate
        ]
        if let commit {
            object["commit"] = commit
        }

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw UntypeError.elevenLabsProtocol("Failed to encode ElevenLabs audio chunk as UTF-8 JSON.")
        }
        return text
    }

    private func dispatchError(_ error: UntypeError) async {
        await handlers?.error(error)
    }

    private func handleSocketError(_ error: Error) async {
        if let error = error as? UntypeError {
            await dispatchError(error)
        } else {
            await dispatchError(mapElevenLabsConnectionError(error))
        }
        connected = false
    }

    private func serverError(from object: [String: Any]) -> UntypeError? {
        guard messageType(from: object) == "error" else {
            return nil
        }
        let type = (object["error_type"] as? String)
            ?? (object["error"] as? String)
            ?? "error"
        let message = (object["message"] as? String)
            ?? (object["detail"] as? String)
            ?? type
        let normalized = "\(type) \(message)".lowercased()
        if isElevenLabsAuthLike(normalized) {
            return .elevenLabsAuth("ElevenLabs authentication failed: \(message)")
        }
        return .elevenLabsProtocol("ElevenLabs \(type): \(message)")
    }

    private func messageType(from object: [String: Any]) -> String? {
        (object["message_type"] as? String) ?? (object["type"] as? String)
    }
}

private func mapElevenLabsConnectionError(_ error: Error) -> UntypeError {
    let message = error.localizedDescription
    if isElevenLabsAuthLike(message.lowercased()) {
        return .elevenLabsAuth("ElevenLabs authentication failed: \(message)")
    }
    return .elevenLabsNetwork("ElevenLabs WebSocket failed: \(message)")
}

private func isElevenLabsAuthLike(_ text: String) -> Bool {
    text.contains("401")
        || text.contains("403")
        || text.contains("auth")
        || text.contains("unauthorized")
        || text.contains("unauthorised")
        || text.contains("forbidden")
        || text.contains("api key")
}
