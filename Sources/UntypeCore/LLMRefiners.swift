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
    func cancelAll()
}

public extension LLMHTTPClient {
    func cancelAll() {}
}

public final class URLSessionLLMHTTPClient: NSObject, LLMHTTPClient, URLSessionDataDelegate {
    private let session: URLSession

    public override init() {
        let configuration = URLSessionConfiguration.ephemeral
        session = URLSession(configuration: configuration)
        super.init()
    }

    public func perform(_ request: URLRequest, timeoutMs: Int) async throws -> LLMHTTPResponse {
        var request = request
        request.timeoutInterval = TimeInterval(timeoutMs) / 1000.0

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
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
            task.resume()
        }
    }

    public func cancelAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }
}

public final class AzureOpenAIRefiner: TextRefining {
    private let endpoint: String
    private let apiKey: String
    private let deployment: String
    private let apiVersion: String
    private let systemPrompt: String
    private let requestTimeoutMs: Int
    private let verbose: Bool
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
        self.verbose = config.verbose
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

    public func dispose() {
        guard !disposed else {
            return
        }
        disposed = true
        httpClient.cancelAll()
    }

    private func makeRequest(text: String) throws -> URLRequest {
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
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.2
        ])
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

public final class GoogleRefiner: TextRefining {
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let requestTimeoutMs: Int
    private let verbose: Bool
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
        self.verbose = config.verbose
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

    public func dispose() {
        guard !disposed else {
            return
        }
        disposed = true
        httpClient.cancelAll()
    }

    private func makeRequest(text: String) throws -> URLRequest {
        let model = percentEncodePathComponent(model)
        let apiKey = percentEncodeQueryValue(apiKey)
        let rawUrl = "\(Self.baseURL)/models/\(model):generateContent?key=\(apiKey)"
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
            "generationConfig": [
                "temperature": 0.2
            ]
        ])
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

public enum LLMRefinerFactory {
    private static let translationSystemPrompt = "You are a translation assistant for live dictated agent commands. Translate the user's text to the requested target language. Preserve technical terms, filenames, command names, and code identifiers. Respond with ONLY the translated text - no preamble, no quotes, no markdown, no explanation."

    public static func makeRefiner(config: LLMConfig) throws -> TextRefining? {
        try make(config: config)
    }

    public static func makeTranslator(config: LLMConfig) throws -> TextRefining? {
        guard config.enabled else {
            return nil
        }
        let translationConfig = LLMConfig(
            enabled: config.enabled,
            provider: config.provider,
            model: config.model,
            systemPrompt: translationSystemPrompt,
            requestTimeoutMs: config.requestTimeoutMs,
            providerConfig: config.providerConfig,
            verbose: config.verbose
        )
        return try make(config: translationConfig)
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
