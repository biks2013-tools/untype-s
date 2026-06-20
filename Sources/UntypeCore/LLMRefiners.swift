import Foundation

public enum LLMRefinementFailureKind: String, Sendable, Equatable {
    case auth
    case network
    case timeout
    case server
    case shape
}

public struct LLMRefinementError: Error, Sendable, Equatable, LocalizedError {
    public let kind: LLMRefinementFailureKind
    public let message: String

    public init(_ message: String, kind: LLMRefinementFailureKind) {
        self.kind = kind
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public struct CompositeRefineTranslateRequest: Sendable, Equatable {
    public let rawText: String
    public let targetLanguageName: String

    public init(rawText: String, targetLanguageName: String) {
        self.rawText = rawText
        self.targetLanguageName = targetLanguageName
    }
}

public struct CompositeRefineTranslateResult: Sendable, Equatable {
    public let refinedText: String
    public let translatedText: String

    public init(refinedText: String, translatedText: String) {
        self.refinedText = refinedText
        self.translatedText = translatedText
    }
}

public protocol CompositeRefineTranslating: AnyObject {
    func refineAndTranslate(_ request: CompositeRefineTranslateRequest) async throws -> CompositeRefineTranslateResult
    func refineAndTranslate(
        _ request: CompositeRefineTranslateRequest,
        onProgress: ((String) -> Void)?
    ) async throws -> CompositeRefineTranslateResult
    func dispose()
}

public extension CompositeRefineTranslating {
    // Default for the base call so callers may invoke `refineAndTranslate(request)`.
    // A conformer that implements ONLY the base method (e.g. existing test mocks) is kept
    // valid by the second default below, which routes the streaming overload to the base
    // one-shot method (ignoring progress). The concrete `LLMCompositeRefineTranslator`
    // overrides the overload with the real streaming body.
    func refineAndTranslate(
        _ request: CompositeRefineTranslateRequest
    ) async throws -> CompositeRefineTranslateResult {
        try await refineAndTranslate(request, onProgress: nil)
    }

    func refineAndTranslate(
        _ request: CompositeRefineTranslateRequest,
        onProgress: ((String) -> Void)?
    ) async throws -> CompositeRefineTranslateResult {
        // No streaming for a conformer that only implements the base method.
        try await refineAndTranslate(request)
    }

    func dispose() {}
}

/// Streaming-capable refine surface. The concrete refiners (`AzureOpenAIRefiner`,
/// `GoogleRefiner`) conform to this; its `refine(_:onProgress:)` signature is identical to
/// the `TextRefining.refine(_:onProgress:)` requirement that Unit C adds to the
/// `TextRefining` protocol (declared in `VoiceAgentProtocolController.swift`). Defining it
/// here lets the composite drive streaming through a refiner reference WITHOUT this unit
/// editing Unit C's file; the same concrete methods satisfy both protocols.
public protocol StreamingTextRefining: AnyObject {
    func refine(_ text: String, onProgress: ((String) -> Void)?) async throws -> String
}

public struct LLMHTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol LLMHTTPClient: AnyObject {
    func perform(_ request: URLRequest, timeoutMs: Int) async throws -> LLMHTTPResponse
    /// Streams the SSE response body for `request`. Each yielded `String` is ONE SSE
    /// `data:` payload with the `data:` prefix stripped and trimmed. The `[DONE]` sentinel
    /// is consumed internally and simply ends the stream (never yielded); Gemini's EOF
    /// (no sentinel) also ends the stream. Status is validated on the up-front
    /// `URLResponse` BEFORE the body is consumed. Cancellation finishes the stream silently.
    func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error>
    func cancelAll()
}

public extension LLMHTTPClient {
    // Default so existing conformers / test mocks compile unchanged.
    func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMRefinementError("streaming not supported", kind: .shape))
        }
    }

    func cancelAll() {}
}

public final class URLSessionLLMHTTPClient: NSObject, LLMHTTPClient, @unchecked Sendable {
    // One process-wide session so TCP+TLS connections are kept alive and
    // reused across refiner instances and recycled push-to-talk sessions.
    // The previous per-instance ephemeral sessions paid a full DNS+TLS
    // handshake on every release. Cache and cookies stay disabled to keep
    // the ephemeral configuration's privacy behavior.
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession
    private let lock = NSLock()
    private var activeTasks: [Int: URLSessionDataTask] = [:]
    // `bytes(for:)` does not expose the underlying URLSessionDataTask, so streaming
    // requests are tracked by their driving Swift Task instead. cancelAll() cancels
    // every entry so a new push-to-talk session aborts an in-flight stream.
    private var activeStreamTasks: [UUID: Task<Void, Never>] = [:]

    public override init() {
        session = Self.sharedSession
        super.init()
    }

    public func perform(_ request: URLRequest, timeoutMs: Int) async throws -> LLMHTTPResponse {
        var request = request
        request.timeoutInterval = TimeInterval(timeoutMs) / 1000.0

        return try await withCheckedThrowingContinuation { continuation in
            // Written once before resume(), read only from the completion
            // handler, which URLSession guarantees runs after resume().
            let identifierBox = TaskIdentifierBox()
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                if let self, let taskIdentifier = identifierBox.value {
                    self.lock.lock()
                    self.activeTasks.removeValue(forKey: taskIdentifier)
                    self.lock.unlock()
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: LLMRefinementError(
                        "LLM response was not an HTTP response",
                        kind: .shape
                    ))
                    return
                }
                continuation.resume(returning: LLMHTTPResponse(
                    statusCode: httpResponse.statusCode,
                    body: data ?? Data()
                ))
            }
            identifierBox.value = task.taskIdentifier
            lock.lock()
            activeTasks[task.taskIdentifier] = task
            lock.unlock()
            task.resume()
        }
    }

    public func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error> {
        var streamRequest = request
        // timeoutInterval is the idle/stall timeout (abort if no bytes arrive for
        // timeoutMs); it is NOT a wall-clock cap. Do not set a session-wide resource
        // timeout on the shared session — it would cap every request.
        streamRequest.timeoutInterval = TimeInterval(timeoutMs) / 1000.0
        let preparedRequest = streamRequest

        return AsyncThrowingStream { continuation in
            let identifier = UUID()
            let work = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    let (bytes, response) = try await self.session.bytes(for: preparedRequest)

                    guard let http = response as? HTTPURLResponse else {
                        throw LLMRefinementError("LLM response was not an HTTP response", kind: .shape)
                    }
                    // Validate status BEFORE consuming the body. On non-2xx the body is a
                    // regular JSON error object (not SSE) — drain it for the message.
                    guard (200..<300).contains(http.statusCode) else {
                        var errorBody = Data()
                        for try await byte in bytes {
                            errorBody.append(byte)
                        }
                        let kind: LLMRefinementFailureKind = [401, 403].contains(http.statusCode) ? .auth : .server
                        throw LLMRefinementError(
                            "LLM HTTP \(http.statusCode): \(truncate(errorBody.utf8Text, max: 200))",
                            kind: kind
                        )
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else {
                            continue // ignore comments/keepalives/blank lines
                        }
                        let payload = trimmed.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            break // OpenAI/Azure terminal sentinel — end the stream.
                        }
                        if payload.isEmpty {
                            continue
                        }
                        continuation.yield(payload)
                    }
                    // Gemini has no [DONE]; EOF of `bytes.lines` also lands here.
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish() // user aborted — swallow silently, not a timeout.
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish() // request cancelled — swallow silently.
                } catch let error as LLMRefinementError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: mapTransportError(error))
                }
            }
            self.lock.lock()
            self.activeStreamTasks[identifier] = work
            self.lock.unlock()
            continuation.onTermination = { @Sendable [weak self] _ in
                work.cancel()
                guard let self else {
                    return
                }
                self.lock.lock()
                self.activeStreamTasks.removeValue(forKey: identifier)
                self.lock.unlock()
            }
        }
    }

    private final class TaskIdentifierBox: @unchecked Sendable {
        var value: Int?
    }

    public func cancelAll() {
        // The session is shared; cancel only this client's tasks so disposing
        // one refiner cannot abort another refiner's in-flight request.
        lock.lock()
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        let streamTasks = Array(activeStreamTasks.values)
        activeStreamTasks.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
        streamTasks.forEach { $0.cancel() }
    }
}

public final class AzureOpenAIRefiner: TextRefining, StreamingTextRefining {
    private let endpoint: String
    private let apiKey: String
    private let deployment: String
    private let apiVersion: String
    private let systemPrompt: String
    private let requestTimeoutMs: Int
    private let maxOutputTokens: Int?
    private let reasoningEffort: String?
    private let verbose: Bool
    private let streamingEnabled: Bool
    private let httpClient: LLMHTTPClient
    private var disposed = false

    public init(config: LLMConfig, httpClient: LLMHTTPClient = URLSessionLLMHTTPClient()) throws {
        guard case let .azureOpenAI(apiKey, endpoint, deployment, apiVersion) = config.providerConfig else {
            throw UntypeError.invalidConfiguration("AzureOpenAIRefiner requires azure-openai provider configuration.")
        }
        self.endpoint = endpoint.trimmingTrailingSlashes()
        self.apiKey = apiKey
        self.deployment = deployment
        self.apiVersion = apiVersion
        self.systemPrompt = config.systemPrompt
        self.requestTimeoutMs = config.requestTimeoutMs
        self.maxOutputTokens = config.maxOutputTokens
        self.reasoningEffort = config.reasoningEffort
        self.verbose = config.verbose
        self.streamingEnabled = config.streamingEnabled
        self.httpClient = httpClient
    }

    public func refine(_ text: String) async throws -> String {
        guard !disposed else {
            throw LLMRefinementError("Azure OpenAI refiner has been disposed", kind: .network)
        }
        let request = try makeRequest(text: text)
        if verbose {
            FileHandle.standardError.writeData(
                "[untype] llm: refining \(text.count) chars via azure-openai/\(deployment)\n"
            )
        }
        let response = try await perform(request)
        try validateHTTP(response)
        return try parseContent(response.body)
    }

    public func refine(_ text: String, onProgress: ((String) -> Void)?) async throws -> String {
        // Streaming is silently inert unless explicitly enabled — delegate to the
        // one-shot path and NEVER invoke onProgress when disabled.
        guard streamingEnabled else {
            return try await refine(text)
        }
        guard !disposed else {
            throw LLMRefinementError("Azure OpenAI refiner has been disposed", kind: .network)
        }
        let request = try makeRequest(text: text, stream: true)
        if verbose {
            FileHandle.standardError.writeData(
                "[untype] llm: streaming \(text.count) chars via azure-openai/\(deployment)\n"
            )
        }
        let decoder = JSONDecoder()
        var accumulated = ""
        do {
            for try await payload in httpClient.stream(request, timeoutMs: requestTimeoutMs) {
                guard let chunk = try? decoder.decode(ChatCompletionChunk.self, from: Data(payload.utf8)) else {
                    continue // tolerate the (rare) non-chunk line / usage-only chunk defensively
                }
                if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                    accumulated += delta
                    onProgress?(accumulated)
                }
            }
        } catch let error as LLMRefinementError {
            throw error
        } catch {
            throw mapTransportError(error)
        }
        let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMRefinementError(
                "LLM response did not contain a non-empty choices[0].message.content",
                kind: .shape
            )
        }
        return trimmed
    }

    private struct ChatCompletionChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let role: String?
                let content: String?
            }
            let delta: Delta
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        let choices: [Choice]
    }

    public func dispose() {
        guard !disposed else {
            return
        }
        disposed = true
        httpClient.cancelAll()
    }

    private func makeRequest(text: String, stream: Bool = false) throws -> URLRequest {
        let deployment = percentEncodePathComponent(deployment)
        let apiVersion = percentEncodeQueryValue(apiVersion)
        let rawUrl = "\(endpoint)/openai/deployments/\(deployment)/chat/completions?api-version=\(apiVersion)"
        guard let url = URL(string: rawUrl) else {
            throw LLMRefinementError("Azure OpenAI URL is invalid: \(rawUrl)", kind: .network)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        if stream {
            // Only switch the response to SSE; no stream_options/usage telemetry in v1.
            body["stream"] = true
        }
        if let maxOutputTokens {
            body["max_completion_tokens"] = maxOutputTokens
        }
        if let reasoningEffort {
            body["reasoning_effort"] = reasoningEffort
        }
        // Reasoning-capable deployments reject sampling parameters unless
        // reasoning is off; send temperature only when no reasoning effort is
        // configured (non-reasoning deployments) or it is explicitly "none".
        if reasoningEffort == nil || reasoningEffort == "none" {
            body["temperature"] = 0.2
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> LLMHTTPResponse {
        do {
            return try await httpClient.perform(request, timeoutMs: requestTimeoutMs)
        } catch let error as LLMRefinementError {
            throw error
        } catch {
            throw mapTransportError(error)
        }
    }

    private func validateHTTP(_ response: LLMHTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            let kind: LLMRefinementFailureKind = [401, 403].contains(response.statusCode) ? .auth : .server
            throw LLMRefinementError(
                "LLM HTTP \(response.statusCode): \(truncate(response.body.utf8Text, max: 200))",
                kind: kind
            )
        }
    }

    private func parseContent(_ data: Data) throws -> String {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LLMRefinementError(
                "LLM response was not valid JSON: \(error.localizedDescription)",
                kind: .shape
            )
        }
        guard
            let object = json as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw LLMRefinementError(
                "LLM response did not contain a non-empty choices[0].message.content",
                kind: .shape
            )
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMRefinementError(
                "LLM response did not contain a non-empty choices[0].message.content",
                kind: .shape
            )
        }
        return trimmed
    }
}

public final class GoogleRefiner: TextRefining, StreamingTextRefining {
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let requestTimeoutMs: Int
    private let maxOutputTokens: Int?
    private let verbose: Bool
    private let streamingEnabled: Bool
    private let httpClient: LLMHTTPClient
    private var disposed = false

    public init(config: LLMConfig, httpClient: LLMHTTPClient = URLSessionLLMHTTPClient()) throws {
        guard case let .google(apiKey) = config.providerConfig else {
            throw UntypeError.invalidConfiguration("GoogleRefiner requires google provider configuration.")
        }
        self.apiKey = apiKey
        self.model = config.model
        self.systemPrompt = config.systemPrompt
        self.requestTimeoutMs = config.requestTimeoutMs
        self.maxOutputTokens = config.maxOutputTokens
        self.verbose = config.verbose
        self.streamingEnabled = config.streamingEnabled
        self.httpClient = httpClient
    }

    public func refine(_ text: String) async throws -> String {
        guard !disposed else {
            throw LLMRefinementError("Google refiner has been disposed", kind: .network)
        }
        let request = try makeRequest(text: text)
        if verbose {
            FileHandle.standardError.writeData(
                "[untype] llm: refining \(text.count) chars via google/\(model)\n"
            )
        }
        let response = try await perform(request)
        try validateHTTP(response)
        return try parseContent(response.body)
    }

    public func refine(_ text: String, onProgress: ((String) -> Void)?) async throws -> String {
        // Streaming is silently inert unless explicitly enabled — delegate to the
        // one-shot path and NEVER invoke onProgress when disabled.
        guard streamingEnabled else {
            return try await refine(text)
        }
        guard !disposed else {
            throw LLMRefinementError("Google refiner has been disposed", kind: .network)
        }
        let request = try makeRequest(text: text, stream: true)
        if verbose {
            FileHandle.standardError.writeData(
                "[untype] llm: streaming \(text.count) chars via google/\(model)\n"
            )
        }
        let decoder = JSONDecoder()
        var accumulated = ""
        var sawAnyText = false
        var lastFinishReason: String?
        do {
            for try await payload in httpClient.stream(request, timeoutMs: requestTimeoutMs) {
                guard let chunk = try? decoder.decode(GeminiStreamChunk.self, from: Data(payload.utf8)) else {
                    continue // each data: line is a complete object; skip an unexpected malformed line
                }
                if let reason = chunk.promptFeedback?.blockReason {
                    throw LLMRefinementError("LLM prompt was blocked: \(reason)", kind: .server)
                }
                guard let candidate = chunk.candidates?.first else {
                    continue // usage-only / metadata-only chunk — nothing to render
                }
                if let parts = candidate.content?.parts {
                    for part in parts where part.thought != true {
                        if let text = part.text, !text.isEmpty {
                            accumulated += text
                            sawAnyText = true
                            onProgress?(accumulated)
                        }
                    }
                }
                if let reason = candidate.finishReason {
                    lastFinishReason = reason
                }
            }
        } catch let error as LLMRefinementError {
            throw error
        } catch {
            throw mapTransportError(error)
        }
        // EOF reached (Gemini has no [DONE]) — classify the result.
        let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sawAnyText, !trimmed.isEmpty else {
            if let reason = lastFinishReason, reason != "STOP" {
                throw LLMRefinementError("LLM output was blocked or truncated: \(reason)", kind: .server)
            }
            throw LLMRefinementError(
                "LLM response did not contain non-empty candidates[0].content.parts[].text",
                kind: .shape
            )
        }
        return trimmed
    }

    private struct GeminiStreamChunk: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                    let thought: Bool?
                }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct PromptFeedback: Decodable {
            let blockReason: String?
        }
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    public func dispose() {
        guard !disposed else {
            return
        }
        disposed = true
        httpClient.cancelAll()
    }

    private func makeRequest(text: String, stream: Bool = false) throws -> URLRequest {
        let model = percentEncodePathComponent(model)
        let apiKey = percentEncodeQueryValue(apiKey)
        // The streaming endpoint differs only in the method name and the alt=sse query;
        // the request body is byte-for-byte identical to :generateContent.
        let rawUrl = stream
            ? "\(Self.baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
            : "\(Self.baseURL)/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: rawUrl) else {
            throw LLMRefinementError("Google Gemini URL is invalid: \(rawUrl)", kind: .network)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": text]
                    ]
                ]
            ],
            "generationConfig": generationConfig()
        ])
        return request
    }

    private func generationConfig() -> [String: Any] {
        var config: [String: Any] = ["temperature": 0.2]
        if let maxOutputTokens {
            config["maxOutputTokens"] = maxOutputTokens
        }
        return config
    }

    private func perform(_ request: URLRequest) async throws -> LLMHTTPResponse {
        do {
            return try await httpClient.perform(request, timeoutMs: requestTimeoutMs)
        } catch let error as LLMRefinementError {
            throw error
        } catch {
            throw mapTransportError(error)
        }
    }

    private func validateHTTP(_ response: LLMHTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            let kind: LLMRefinementFailureKind = [401, 403].contains(response.statusCode) ? .auth : .server
            throw LLMRefinementError(
                "LLM HTTP \(response.statusCode): \(truncate(response.body.utf8Text, max: 200))",
                kind: kind
            )
        }
    }

    private func parseContent(_ data: Data) throws -> String {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LLMRefinementError(
                "LLM response was not valid JSON: \(error.localizedDescription)",
                kind: .shape
            )
        }
        guard
            let object = json as? [String: Any],
            let candidates = object["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw LLMRefinementError(
                "LLM response did not contain non-empty candidates[0].content.parts[].text",
                kind: .shape
            )
        }
        let joined = parts.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else {
            throw LLMRefinementError(
                "LLM response did not contain non-empty candidates[0].content.parts[].text",
                kind: .shape
            )
        }
        return joined
    }
}

public final class LLMCompositeRefineTranslator: CompositeRefineTranslating {
    private let refiner: TextRefining
    private let refinementPromptTemplate: String
    private let translationPromptTemplate: String

    public init(
        refiner: TextRefining,
        refinementPromptTemplate: String,
        translationPromptTemplate: String
    ) {
        self.refiner = refiner
        self.refinementPromptTemplate = refinementPromptTemplate
        self.translationPromptTemplate = translationPromptTemplate
    }

    public func refineAndTranslate(
        _ request: CompositeRefineTranslateRequest
    ) async throws -> CompositeRefineTranslateResult {
        try await refineAndTranslate(request, onProgress: nil)
    }

    public func refineAndTranslate(
        _ request: CompositeRefineTranslateRequest,
        onProgress: ((String) -> Void)?
    ) async throws -> CompositeRefineTranslateResult {
        let prompt = renderPrompt(request)
        let response: String
        // Stream only when a progress sink is provided AND the underlying refiner supports
        // streaming (azure-openai / google). The streaming overload is silently inert when
        // LLMConfig.streamingEnabled is false (it delegates to the one-shot path), so a
        // non-nil onProgress with streaming off still produces the one-shot result and never
        // invokes the sink.
        if let onProgress, let streamingRefiner = refiner as? StreamingTextRefining {
            // Drive progress with the accumulated raw JSON-in-progress; extract
            // refined_text/translated_text best-effort for DISPLAY ONLY. The committed result
            // is ALWAYS parsed strictly from the complete assembled response below — partial
            // JSON never reaches the final fields.
            response = try await streamingRefiner.refine(prompt) { accumulatedRawJSON in
                let refined = partialStringValue(forKey: "refined_text", in: accumulatedRawJSON)
                let translated = partialStringValue(forKey: "translated_text", in: accumulatedRawJSON)
                // Prefer the translated value once it begins; otherwise the refined value;
                // fall back to the raw accumulated text when neither field has started yet.
                let display = translated ?? refined ?? accumulatedRawJSON
                onProgress(display)
            }
        } else {
            response = try await refiner.refine(prompt)
        }
        return try Self.parseResponse(response)
    }

    public func dispose() {
        refiner.dispose()
    }

    public static func parseResponse(_ text: String) throws -> CompositeRefineTranslateResult {
        let data = Data(extractJSONObjectText(from: text).utf8)
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LLMRefinementError(
                "Composite LLM response was not valid JSON: \(error.localizedDescription)",
                kind: .shape
            )
        }
        guard
            let object = json as? [String: Any],
            let refinedText = object["refined_text"] as? String,
            let translatedText = object["translated_text"] as? String
        else {
            throw LLMRefinementError(
                "Composite LLM response must contain string fields refined_text and translated_text",
                kind: .shape
            )
        }
        let trimmedRefined = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslated = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRefined.isEmpty, !trimmedTranslated.isEmpty else {
            throw LLMRefinementError(
                "Composite LLM response fields refined_text and translated_text must not be empty",
                kind: .shape
            )
        }
        return CompositeRefineTranslateResult(
            refinedText: trimmedRefined,
            translatedText: trimmedTranslated
        )
    }

    private func renderPrompt(_ request: CompositeRefineTranslateRequest) -> String {
        let refinementPrompt = refinementPromptTemplate
            .replacingOccurrences(of: "{text}", with: request.rawText)
        let translationPrompt = translationPromptTemplate
            .replacingOccurrences(of: "{target_language}", with: request.targetLanguageName)
            .replacingOccurrences(of: "{text}", with: request.rawText)
        return """
        Source transcript:
        \(request.rawText)

        Refinement prompt:
        \(refinementPrompt)

        Translation prompt:
        \(translationPrompt)

        Return only JSON with refined_text and translated_text.
        """
    }

    private static func extractJSONObjectText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        guard
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}"),
            start <= end
        else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}

public enum LLMRefinerFactory {
    public static func makeRefiner(config: LLMConfig) throws -> TextRefining? {
        try make(config: config)
    }

    public static func makeTranslator(
        config: LLMConfig,
        systemPrompt: String = UntypePromptDefaults.translationSystemPrompt
    ) throws -> TextRefining? {
        guard config.enabled else {
            return nil
        }
        let translationConfig = LLMConfig(
            enabled: config.enabled,
            provider: config.provider,
            model: config.model,
            systemPrompt: systemPrompt,
            requestTimeoutMs: config.requestTimeoutMs,
            providerConfig: config.providerConfig,
            verbose: config.verbose,
            maxOutputTokens: config.maxOutputTokens,
            reasoningEffort: config.reasoningEffort,
            streamingEnabled: config.streamingEnabled
        )
        return try make(config: translationConfig)
    }

    public static func makeCompositeRefineTranslator(
        config: LLMConfig,
        prompts: PromptConfig
    ) throws -> CompositeRefineTranslating? {
        guard config.enabled else {
            return nil
        }
        let compositeConfig = LLMConfig(
            enabled: config.enabled,
            provider: config.provider,
            model: config.model,
            systemPrompt: prompts.compositeSystemPrompt,
            requestTimeoutMs: config.requestTimeoutMs,
            providerConfig: config.providerConfig,
            verbose: config.verbose,
            maxOutputTokens: config.maxOutputTokens,
            reasoningEffort: config.reasoningEffort,
            streamingEnabled: config.streamingEnabled
        )
        guard let refiner = try make(config: compositeConfig) else {
            return nil
        }
        return LLMCompositeRefineTranslator(
            refiner: refiner,
            refinementPromptTemplate: prompts.compositeRefinementPromptTemplate,
            translationPromptTemplate: prompts.compositeTranslationPromptTemplate
        )
    }

    private static func make(config: LLMConfig) throws -> TextRefining? {
        guard config.enabled else {
            return nil
        }
        switch config.providerConfig {
        case .azureOpenAI:
            return try AzureOpenAIRefiner(config: config)
        case .google:
            return try GoogleRefiner(config: config)
        case .unimplemented(let provider):
            throw UntypeError.invalidConfiguration(notImplementedHint(provider))
        }
    }

    private static func notImplementedHint(_ provider: LLMProvider) -> String {
        switch provider {
        case .openAI:
            return "Provider 'openai' is not implemented in v1. To enable, set OPENAI_API_KEY and add the OpenAI refiner. Use --llm-provider azure-openai for now."
        case .anthropic:
            return "Provider 'anthropic' is not implemented in v1. To enable, set ANTHROPIC_API_KEY and add the Anthropic refiner."
        case .azureAIInference:
            return "Provider 'azure-ai-inference' is not implemented in v1. To enable, set AZURE_AI_INFERENCE_ENDPOINT and AZURE_AI_INFERENCE_API_KEY and add the refiner."
        case .ollama:
            return "Provider 'ollama' is not implemented in v1. To enable, set OLLAMA_HOST and add the Ollama refiner."
        case .litellm:
            return "Provider 'litellm' is not implemented in v1. To enable, set LITELLM_BASE_URL and LITELLM_API_KEY and add the refiner."
        case .openAICompat:
            return "Provider 'openai-compat' is not implemented in v1. To enable, set OPENAI_COMPAT_BASE_URL and OPENAI_COMPAT_API_KEY and add the refiner."
        case .azureOpenAI, .google:
            return "Provider '\(provider.rawValue)' is implemented but was resolved as an unimplemented provider."
        }
    }
}

private func mapTransportError(_ error: Error) -> LLMRefinementError {
    if let urlError = error as? URLError {
        if urlError.code == .timedOut || urlError.code == .cancelled {
            return LLMRefinementError("LLM request timeout: \(urlError.localizedDescription)", kind: .timeout)
        }
        return LLMRefinementError("LLM request network: \(urlError.localizedDescription)", kind: .network)
    }
    let description = error.localizedDescription
    if description.localizedCaseInsensitiveContains("timed out") {
        return LLMRefinementError("LLM request timeout: \(description)", kind: .timeout)
    }
    return LLMRefinementError("LLM request network: \(description)", kind: .network)
}

/// Best-effort: returns the current (possibly partial) string value of `key` from an
/// in-progress JSON object. Returns nil if the key/value has not started yet. Escape-aware:
/// handles `\" \\ \/ \n \t \r \b \f` and complete `\uXXXX`; defers an incomplete `\uXXXX`
/// at the buffer tail; returns the decoded-so-far value for an unterminated string.
/// DISPLAY ONLY — must never feed the final committed result. `internal` (not `public`)
/// so it stays out of the module's public API while remaining reachable from
/// `@testable import` unit tests.
func partialStringValue(forKey key: String, in json: String) -> String? {
    let scalars = Array(json.unicodeScalars)
    var i = 0
    let n = scalars.count

    func skipWhitespace() {
        while i < n, scalars[i] == " " || scalars[i] == "\n" || scalars[i] == "\t" || scalars[i] == "\r" {
            i += 1
        }
    }

    // Read a JSON string starting at the opening quote scalars[i] == '"'.
    // `allowUnterminated` returns what has streamed so far if the closing quote
    // (or a complete escape) has not yet arrived.
    func readString(allowUnterminated: Bool) -> String? {
        guard i < n, scalars[i] == "\"" else {
            return nil
        }
        i += 1
        var out = String.UnicodeScalarView()
        while i < n {
            let c = scalars[i]
            if c == "\\" {
                i += 1
                guard i < n else {
                    return allowUnterminated ? String(out) : nil // dangling backslash mid-stream
                }
                let e = scalars[i]
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u":
                    // Need 4 hex digits; if not all arrived yet, stop best-effort.
                    guard i + 4 < n else {
                        return allowUnterminated ? String(out) : nil
                    }
                    let hex = String(String.UnicodeScalarView(scalars[(i + 1)...(i + 4)]))
                    if let v = UInt32(hex, radix: 16), let s = Unicode.Scalar(v) {
                        out.append(s)
                    }
                    i += 4
                default:
                    out.append(e) // unknown escape: keep literal
                }
                i += 1
            } else if c == "\"" {
                i += 1 // advance past the closing quote
                return String(out) // closed
            } else {
                out.append(c)
                i += 1
            }
        }
        return allowUnterminated ? String(out) : nil // ran out of bytes mid-value
    }

    // Walk the buffer looking for the `"key"` token immediately followed by `:`.
    while i < n {
        if scalars[i] == "\"" {
            let start = i
            if let k = readString(allowUnterminated: false), k == key {
                skipWhitespace()
                guard i < n, scalars[i] == ":" else {
                    continue
                }
                i += 1
                skipWhitespace()
                return readString(allowUnterminated: true)
            } else if i <= start {
                i += 1
            }
        } else {
            i += 1
        }
    }
    return nil
}

private func percentEncodePathComponent(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func percentEncodeQueryValue(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
}

private func truncate(_ value: String, max: Int) -> String {
    guard value.count > max else {
        return value
    }
    return String(value.prefix(max)) + "..."
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var result = self
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

private extension Data {
    var utf8Text: String {
        String(data: self, encoding: .utf8) ?? "<unreadable body>"
    }
}

private extension FileHandle {
    func writeData(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        write(data)
    }
}
