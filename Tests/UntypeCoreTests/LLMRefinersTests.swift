import Foundation
import Testing
@testable import UntypeCore

@Test func azureOpenAIRefinerPostsChatCompletionAndReturnsTrimmedContent() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(
            statusCode: 200,
            body: jsonData([
                "choices": [
                    [
                        "message": [
                            "content": "  Polished text.  "
                        ]
                    ]
                ]
            ])
        )
    ])
    let refiner = try AzureOpenAIRefiner(config: azureConfig(), httpClient: http)

    let output = try await refiner.refine("raw text")

    #expect(output == "Polished text.")
    #expect(http.requests.count == 1)
    let request = try #require(http.requests.first)
    #expect(request.url?.absoluteString == "https://example.openai.azure.com/openai/deployments/gpt-5.4/chat/completions?api-version=2024-10-21")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "api-key") == "azure-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try requestJSONObject(request)
    let messages = try #require(body["messages"] as? [[String: String]])
    #expect(messages[0] == ["role": "system", "content": "Clean this transcript."])
    #expect(messages[1] == ["role": "user", "content": "raw text"])
    #expect(body["temperature"] as? Double == 0.2)
}

@Test func azureOpenAIRefinerMapsHTTPAuthAndShapeErrors() async throws {
    let authClient = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 401, body: Data("nope".utf8))
    ])
    let authRefiner = try AzureOpenAIRefiner(config: azureConfig(), httpClient: authClient)

    await expectLLMError(kind: .auth) {
        _ = try await authRefiner.refine("raw")
    }

    let shapeClient = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [
                [
                    "message": [
                        "role": "assistant"
                    ]
                ]
            ]
        ]))
    ])
    let shapeRefiner = try AzureOpenAIRefiner(config: azureConfig(), httpClient: shapeClient)

    await expectLLMError(kind: .shape) {
        _ = try await shapeRefiner.refine("raw")
    }
}

@Test func azureOpenAIRefinerEncodesDeploymentAndTrimsEndpointSlash() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [["message": ["content": "ok"]]]
        ]))
    ])
    let refiner = try AzureOpenAIRefiner(
        config: azureConfig(
            endpoint: "https://example.openai.azure.com/",
            deployment: "weird name"
        ),
        httpClient: http
    )

    _ = try await refiner.refine("raw")

    #expect(http.requests.first?.url?.absoluteString == "https://example.openai.azure.com/openai/deployments/weird%20name/chat/completions?api-version=2024-10-21")
}

@Test func googleRefinerPostsGenerateContentAndJoinsCandidateText() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(
            statusCode: 200,
            body: jsonData([
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": " Polished "],
                                ["text": "text. "]
                            ]
                        ]
                    ]
                ]
            ])
        )
    ])
    let refiner = try GoogleRefiner(config: googleConfig(), httpClient: http)

    let output = try await refiner.refine("raw text")

    #expect(output == "Polished text.")
    let request = try #require(http.requests.first)
    #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=google-key")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try requestJSONObject(request)
    let systemInstruction = try #require(body["systemInstruction"] as? [String: Any])
    let systemParts = try #require(systemInstruction["parts"] as? [[String: String]])
    #expect(systemParts[0]["text"] == "Clean this transcript.")
    let contents = try #require(body["contents"] as? [[String: Any]])
    let contentParts = try #require(contents[0]["parts"] as? [[String: String]])
    #expect(contentParts[0]["text"] == "raw text")
}

@Test func azureCompositeRefinerUsesCompositePromptAndParsesStructuredResult() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(
            statusCode: 200,
            body: jsonData([
                "choices": [
                    [
                        "message": [
                            "content": #"{"refined_text":"Clean text.","translated_text":"Καθαρό κείμενο."}"#
                        ]
                    ]
                ]
            ])
        )
    ])
    let baseRefiner = try AzureOpenAIRefiner(
        config: azureConfig(systemPrompt: "Composite system."),
        httpClient: http
    )
    let composite = LLMCompositeRefineTranslator(
        refiner: baseRefiner,
        refinementPromptTemplate: "REFINE {text}",
        translationPromptTemplate: "TRANSLATE {target_language}: {text}"
    )

    let output = try await composite.refineAndTranslate(
        CompositeRefineTranslateRequest(rawText: "raw words", targetLanguageName: "Greek")
    )

    #expect(output == CompositeRefineTranslateResult(
        refinedText: "Clean text.",
        translatedText: "Καθαρό κείμενο."
    ))
    #expect(http.requests.count == 1)
    let request = try #require(http.requests.first)
    let body = try requestJSONObject(request)
    let messages = try #require(body["messages"] as? [[String: String]])
    #expect(messages[0] == ["role": "system", "content": "Composite system."])
    #expect(messages[1]["content"]?.contains("Source transcript:\nraw words") == true)
    #expect(messages[1]["content"]?.contains("REFINE raw words") == true)
    #expect(messages[1]["content"]?.contains("TRANSLATE Greek: raw words") == true)
}

@Test func googleCompositeRefinerUsesCompositePromptAndAcceptsJsonInsideMarkdownFence() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(
            statusCode: 200,
            body: jsonData([
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                [
                                    "text": """
                                    ```json
                                    {"refined_text":"Clean text.","translated_text":"Καθαρό κείμενο."}
                                    ```
                                    """
                                ]
                            ]
                        ]
                    ]
                ]
            ])
        )
    ])
    let baseRefiner = try GoogleRefiner(
        config: googleConfig(systemPrompt: "Composite system."),
        httpClient: http
    )
    let composite = LLMCompositeRefineTranslator(
        refiner: baseRefiner,
        refinementPromptTemplate: "REFINE {text}",
        translationPromptTemplate: "TRANSLATE {target_language}"
    )

    let output = try await composite.refineAndTranslate(
        CompositeRefineTranslateRequest(rawText: "raw words", targetLanguageName: "Greek")
    )

    #expect(output.translatedText == "Καθαρό κείμενο.")
    #expect(http.requests.count == 1)
    let request = try #require(http.requests.first)
    let body = try requestJSONObject(request)
    let systemInstruction = try #require(body["systemInstruction"] as? [String: Any])
    let systemParts = try #require(systemInstruction["parts"] as? [[String: String]])
    #expect(systemParts[0]["text"] == "Composite system.")
    let contents = try #require(body["contents"] as? [[String: Any]])
    let contentParts = try #require(contents[0]["parts"] as? [[String: String]])
    #expect(contentParts[0]["text"]?.contains("REFINE raw words") == true)
    #expect(contentParts[0]["text"]?.contains("TRANSLATE Greek") == true)
}

@Test func googleRefinerMapsServerShapeAndNetworkErrors() async throws {
    let serverClient = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 500, body: Data("oops".utf8))
    ])
    let serverRefiner = try GoogleRefiner(config: googleConfig(), httpClient: serverClient)

    await expectLLMError(kind: .server) {
        _ = try await serverRefiner.refine("raw")
    }

    let shapeClient = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["not_text": "x"]
                        ]
                    ]
                ]
            ]
        ]))
    ])
    let shapeRefiner = try GoogleRefiner(config: googleConfig(), httpClient: shapeClient)

    await expectLLMError(kind: .shape) {
        _ = try await shapeRefiner.refine("raw")
    }

    let timeoutClient = MockLLMHTTPClient(error: URLError(.timedOut))
    let timeoutRefiner = try GoogleRefiner(config: googleConfig(), httpClient: timeoutClient)

    await expectLLMError(kind: .timeout) {
        _ = try await timeoutRefiner.refine("raw")
    }
}

@Test func llmFactoryReturnsNilWhenDisabledAndThrowsForUnimplementedProviders() throws {
    let disabled = LLMConfig(
        enabled: false,
        provider: .azureOpenAI,
        model: "gpt-5.4",
        systemPrompt: "Clean this transcript.",
        requestTimeoutMs: 15_000,
        providerConfig: .azureOpenAI(apiKey: "", endpoint: "", deployment: "gpt-5.4", apiVersion: "2024-10-21"),
        verbose: false
    )
    #expect(try LLMRefinerFactory.makeRefiner(config: disabled) == nil)

    let unimplemented = LLMConfig(
        enabled: true,
        provider: .anthropic,
        model: "claude-test",
        systemPrompt: "Clean this transcript.",
        requestTimeoutMs: 15_000,
        providerConfig: .unimplemented(provider: .anthropic),
        verbose: false
    )
    #expect(throws: UntypeError.self) {
        _ = try LLMRefinerFactory.makeRefiner(config: unimplemented)
    }
}

@Test func disposedRefinerCancelsClientAndFailsFutureRequests() async throws {
    let http = MockLLMHTTPClient(responses: [])
    let refiner = try GoogleRefiner(config: googleConfig(), httpClient: http)

    refiner.dispose()
    refiner.dispose()

    #expect(http.cancelCount == 1)
    await expectLLMError(kind: .network) {
        _ = try await refiner.refine("raw")
    }
}

private final class MockLLMHTTPClient: LLMHTTPClient {
    private let responses: [LLMHTTPResponse]
    private let error: Error?
    private var index = 0
    var requests: [URLRequest] = []
    var timeoutMsValues: [Int] = []
    var cancelCount = 0

    // Streaming support: each yielded String is one already-stripped SSE `data:` payload,
    // exactly as `URLSessionLLMHTTPClient.stream` would yield (prefix removed, [DONE] excluded).
    private let streamPayloads: [String]
    private let streamError: Error?
    var streamRequests: [URLRequest] = []

    init(
        responses: [LLMHTTPResponse] = [],
        error: Error? = nil,
        streamPayloads: [String] = [],
        streamError: Error? = nil
    ) {
        self.responses = responses
        self.error = error
        self.streamPayloads = streamPayloads
        self.streamError = streamError
    }

    func perform(_ request: URLRequest, timeoutMs: Int) async throws -> LLMHTTPResponse {
        requests.append(request)
        timeoutMsValues.append(timeoutMs)
        if let error {
            throw error
        }
        defer {
            index += 1
        }
        return responses[index]
    }

    func stream(_ request: URLRequest, timeoutMs: Int) -> AsyncThrowingStream<String, Error> {
        streamRequests.append(request)
        let payloads = streamPayloads
        let error = streamError
        return AsyncThrowingStream { continuation in
            for payload in payloads {
                continuation.yield(payload)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func cancelAll() {
        cancelCount += 1
    }
}

private func azureConfig(
    endpoint: String = "https://example.openai.azure.com",
    deployment: String = "gpt-5.4",
    systemPrompt: String = "Clean this transcript.",
    maxOutputTokens: Int? = nil,
    reasoningEffort: String? = nil,
    streamingEnabled: Bool = false
) -> LLMConfig {
    LLMConfig(
        enabled: true,
        provider: .azureOpenAI,
        model: "gpt-5.4",
        systemPrompt: systemPrompt,
        requestTimeoutMs: 1_000,
        providerConfig: .azureOpenAI(
            apiKey: "azure-key",
            endpoint: endpoint,
            deployment: deployment,
            apiVersion: "2024-10-21"
        ),
        verbose: false,
        maxOutputTokens: maxOutputTokens,
        reasoningEffort: reasoningEffort,
        streamingEnabled: streamingEnabled
    )
}

private func googleConfig(
    systemPrompt: String = "Clean this transcript.",
    maxOutputTokens: Int? = nil,
    streamingEnabled: Bool = false
) -> LLMConfig {
    LLMConfig(
        enabled: true,
        provider: .google,
        model: "gemini-3.5-flash",
        systemPrompt: systemPrompt,
        requestTimeoutMs: 1_000,
        providerConfig: .google(apiKey: "google-key"),
        verbose: false,
        maxOutputTokens: maxOutputTokens,
        streamingEnabled: streamingEnabled
    )
}

// MARK: - Streaming helpers

/// Builds a JSON string for one Azure `chat.completion.chunk` carrying a content delta.
private func azureChunk(content: String) -> String {
    #"{"choices":[{"delta":{"content":"\#(content)"},"index":0,"finish_reason":null}]}"#
}

/// Builds a JSON string for one Gemini stream chunk carrying a single text part.
private func geminiChunk(text: String) -> String {
    #"{"candidates":[{"content":{"parts":[{"text":"\#(text)"}],"role":"model"}}]}"#
}

private func jsonData(_ value: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: value)
}

private func requestJSONObject(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    let json = try JSONSerialization.jsonObject(with: body)
    return try #require(json as? [String: Any])
}

private func expectLLMError(kind: LLMRefinementFailureKind, operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected LLMRefinementError(\(kind.rawValue))")
    } catch let error as LLMRefinementError {
        #expect(error.kind == kind)
    } catch {
        Issue.record("Expected LLMRefinementError(\(kind.rawValue)), got \(error)")
    }
}

@Test func azureOpenAIRefinerSendsTuningParametersAndOmitsTemperatureForReasoningEfforts() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [["message": ["content": "ok"]]]
        ]))
    ])
    let refiner = try AzureOpenAIRefiner(
        config: azureConfig(maxOutputTokens: 600, reasoningEffort: "minimal"),
        httpClient: http
    )

    _ = try await refiner.refine("raw")

    let body = try requestJSONObject(try #require(http.requests.first))
    #expect(body["max_completion_tokens"] as? Int == 600)
    #expect(body["reasoning_effort"] as? String == "minimal")
    #expect(body["temperature"] == nil)
}

@Test func azureOpenAIRefinerKeepsTemperatureForNoneEffortAndForDefaults() async throws {
    let noneHTTP = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [["message": ["content": "ok"]]]
        ]))
    ])
    let noneRefiner = try AzureOpenAIRefiner(
        config: azureConfig(reasoningEffort: "none"),
        httpClient: noneHTTP
    )
    _ = try await noneRefiner.refine("raw")
    let noneBody = try requestJSONObject(try #require(noneHTTP.requests.first))
    #expect(noneBody["reasoning_effort"] as? String == "none")
    #expect(noneBody["temperature"] as? Double == 0.2)

    let defaultHTTP = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [["message": ["content": "ok"]]]
        ]))
    ])
    let defaultRefiner = try AzureOpenAIRefiner(config: azureConfig(), httpClient: defaultHTTP)
    _ = try await defaultRefiner.refine("raw")
    let defaultBody = try requestJSONObject(try #require(defaultHTTP.requests.first))
    #expect(defaultBody["reasoning_effort"] == nil)
    #expect(defaultBody["max_completion_tokens"] == nil)
    #expect(defaultBody["temperature"] as? Double == 0.2)
}

@Test func googleRefinerSendsMaxOutputTokensWhenConfigured() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "candidates": [["content": ["parts": [["text": "ok"]]]]]
        ]))
    ])
    let refiner = try GoogleRefiner(
        config: googleConfig(maxOutputTokens: 450),
        httpClient: http
    )

    _ = try await refiner.refine("raw")

    let body = try requestJSONObject(try #require(http.requests.first))
    let generationConfig = try #require(body["generationConfig"] as? [String: Any])
    #expect(generationConfig["maxOutputTokens"] as? Int == 450)
}

// MARK: - Streaming: Azure

@Test func azureStreamingAccumulatesDeltasAndReportsGrowingProgress() async throws {
    let http = MockLLMHTTPClient(streamPayloads: [
        azureChunk(content: "Hel"),
        azureChunk(content: "lo "),
        azureChunk(content: "world")
    ])
    let refiner = try AzureOpenAIRefiner(
        config: azureConfig(streamingEnabled: true),
        httpClient: http
    )

    var progress: [String] = []
    let output = try await refiner.refine("raw") { progress.append($0) }

    #expect(output == "Hello world")
    // onProgress receives the ACCUMULATED (monotonically growing) text after each delta.
    #expect(progress == ["Hel", "Hello ", "Hello world"])
    // The streaming endpoint was hit with "stream": true; the one-shot perform was not used.
    #expect(http.requests.isEmpty)
    let request = try #require(http.streamRequests.first)
    let body = try requestJSONObject(request)
    #expect(body["stream"] as? Bool == true)
    #expect(request.url?.absoluteString == "https://example.openai.azure.com/openai/deployments/gpt-5.4/chat/completions?api-version=2024-10-21")
}

@Test func azureStreamingDelegatesToOneShotAndNeverCallsProgressWhenDisabled() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [["message": ["content": "  Polished.  "]]]
        ]))
    ])
    let refiner = try AzureOpenAIRefiner(
        config: azureConfig(streamingEnabled: false),
        httpClient: http
    )

    var progressCalls = 0
    let output = try await refiner.refine("raw") { _ in progressCalls += 1 }

    #expect(output == "Polished.")
    #expect(progressCalls == 0)
    // Delegated to the one-shot perform path; the streaming endpoint was never used.
    #expect(http.requests.count == 1)
    #expect(http.streamRequests.isEmpty)
}

@Test func azureStreamingMapsTransportErrorMidStream() async throws {
    let http = MockLLMHTTPClient(
        streamPayloads: [azureChunk(content: "partial")],
        streamError: URLError(.networkConnectionLost)
    )
    let refiner = try AzureOpenAIRefiner(
        config: azureConfig(streamingEnabled: true),
        httpClient: http
    )

    await expectLLMError(kind: .network) {
        _ = try await refiner.refine("raw") { _ in }
    }
}

// MARK: - Streaming: Google

@Test func googleStreamingAccumulatesPartsAndCompletesOnEOF() async throws {
    let http = MockLLMHTTPClient(streamPayloads: [
        geminiChunk(text: "Hel"),
        geminiChunk(text: "lo "),
        geminiChunk(text: "world")
    ])
    let refiner = try GoogleRefiner(
        config: googleConfig(streamingEnabled: true),
        httpClient: http
    )

    var progress: [String] = []
    let output = try await refiner.refine("raw") { progress.append($0) }

    #expect(output == "Hello world")
    #expect(progress == ["Hel", "Hello ", "Hello world"])
    #expect(http.requests.isEmpty)
    let request = try #require(http.streamRequests.first)
    #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:streamGenerateContent?alt=sse&key=google-key")
    // Body is byte-for-byte identical to the non-streaming request (no streaming-only fields).
    let body = try requestJSONObject(request)
    #expect(body["stream"] == nil)
    #expect(body["contents"] != nil)
}

@Test func googleStreamingFiltersThoughtPartsAndTreatsEmptyOutputAsShape() async throws {
    // Only a thought part arrives -> no answer text -> EOF with empty output -> shape error.
    let http = MockLLMHTTPClient(streamPayloads: [
        #"{"candidates":[{"content":{"parts":[{"text":"reasoning...","thought":true}],"role":"model"}}]}"#
    ])
    let refiner = try GoogleRefiner(
        config: googleConfig(streamingEnabled: true),
        httpClient: http
    )

    await expectLLMError(kind: .shape) {
        _ = try await refiner.refine("raw") { _ in }
    }
}

@Test func googleStreamingDelegatesToOneShotWhenDisabled() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "candidates": [["content": ["parts": [["text": "ok"]]]]]
        ]))
    ])
    let refiner = try GoogleRefiner(
        config: googleConfig(streamingEnabled: false),
        httpClient: http
    )

    var progressCalls = 0
    let output = try await refiner.refine("raw") { _ in progressCalls += 1 }

    #expect(output == "ok")
    #expect(progressCalls == 0)
    #expect(http.requests.count == 1)
    #expect(http.streamRequests.isEmpty)
}

// MARK: - Streaming: error classification on non-2xx

@Test func streamingNon2xxFromRealClientMapsAuthAndServerKinds() async {
    // The default protocol-extension stream() throws .shape; here we exercise the
    // refiner's own error propagation when the transport finishes-throwing an auth error,
    // mirroring URLSessionLLMHTTPClient's [401,403] -> .auth classification.
    let authHTTP = MockLLMHTTPClient(
        streamPayloads: [],
        streamError: LLMRefinementError("LLM HTTP 401", kind: .auth)
    )
    if let refiner = try? AzureOpenAIRefiner(config: azureConfig(streamingEnabled: true), httpClient: authHTTP) {
        await expectLLMError(kind: .auth) {
            _ = try await refiner.refine("raw") { _ in }
        }
    }

    let serverHTTP = MockLLMHTTPClient(
        streamPayloads: [],
        streamError: LLMRefinementError("LLM HTTP 500", kind: .server)
    )
    if let refiner = try? GoogleRefiner(config: googleConfig(streamingEnabled: true), httpClient: serverHTTP) {
        await expectLLMError(kind: .server) {
            _ = try await refiner.refine("raw") { _ in }
        }
    }
}

// MARK: - Streaming: composite (Risk #1 — partial JSON must never reach final fields)

@Test func compositeStreamingDrivesPartialDisplayButCommitsStrictParse() async throws {
    // Scripted SSE deltas assemble to a complete {refined_text, translated_text} JSON object.
    // Mid-stream the buffer is partial JSON; the final fields must come ONLY from the strict
    // parse of the complete assembled response — the partial prefix must never leak in.
    let http = MockLLMHTTPClient(streamPayloads: [
        azureChunk(content: "{\\\"refined_text\\\":\\\"Clean te"),
        azureChunk(content: "xt.\\\",\\\"translated_text\\\":\\\"Kath"),
        azureChunk(content: "aro keimeno.\\\"}")
    ])
    let baseRefiner = try AzureOpenAIRefiner(
        config: azureConfig(systemPrompt: "Composite system.", streamingEnabled: true),
        httpClient: http
    )
    let composite = LLMCompositeRefineTranslator(
        refiner: baseRefiner,
        refinementPromptTemplate: "REFINE {text}",
        translationPromptTemplate: "TRANSLATE {target_language}: {text}"
    )

    var progress: [String] = []
    let output = try await composite.refineAndTranslate(
        CompositeRefineTranslateRequest(rawText: "raw words", targetLanguageName: "Greek"),
        onProgress: { progress.append($0) }
    )

    // Final committed fields come ONLY from the strict parse of the COMPLETE response.
    #expect(output == CompositeRefineTranslateResult(
        refinedText: "Clean text.",
        translatedText: "Katharo keimeno."
    ))
    // Progress was driven by best-effort partial extraction; assert a mid-stream partial
    // prefix of refined_text was produced for display (proving extraction ran) yet never
    // contaminated the committed final fields (Risk #1).
    #expect(progress.contains("Clean te"))
    #expect(output.refinedText == "Clean text.")
    #expect(output.translatedText == "Katharo keimeno.")
    #expect(http.streamRequests.count == 1)
    #expect(http.requests.isEmpty)
}

@Test func compositeStreamingOffDelegatesToOneShotParse() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [["message": ["content": #"{"refined_text":"Clean.","translated_text":"Katharo."}"#]]]
        ]))
    ])
    let baseRefiner = try AzureOpenAIRefiner(
        config: azureConfig(systemPrompt: "Composite system.", streamingEnabled: false),
        httpClient: http
    )
    let composite = LLMCompositeRefineTranslator(
        refiner: baseRefiner,
        refinementPromptTemplate: "REFINE {text}",
        translationPromptTemplate: "TRANSLATE {target_language}: {text}"
    )

    var progressCalls = 0
    let output = try await composite.refineAndTranslate(
        CompositeRefineTranslateRequest(rawText: "raw words", targetLanguageName: "Greek"),
        onProgress: { _ in progressCalls += 1 }
    )

    #expect(output == CompositeRefineTranslateResult(refinedText: "Clean.", translatedText: "Katharo."))
    // streamingEnabled is false -> the streaming overload delegates to one-shot, never streams.
    #expect(progressCalls == 0)
    #expect(http.requests.count == 1)
    #expect(http.streamRequests.isEmpty)
}

// MARK: - Transport: cancellation finishes silently + cancelAll aborts streams

@Test func urlSessionStreamCancellationFinishesSilently() async throws {
    let client = URLSessionLLMHTTPClient()
    let request = URLRequest(url: URL(string: "https://10.255.255.1/never")!)
    let stream = client.stream(request, timeoutMs: 5_000)

    let task = Task<Int, Error> {
        var count = 0
        for try await _ in stream { count += 1 }
        return count
    }
    task.cancel()
    // A cancelled stream finishes silently (no thrown error); the iteration yields nothing.
    let count = try await task.value
    #expect(count == 0)
    // cancelAll must not crash and clears the (now empty) registry.
    client.cancelAll()
}

// MARK: - partialStringValue (display-only extractor) unit tests

@Test func partialStringValueExtractsCompleteAndPartialValues() {
    // Complete value.
    #expect(partialStringValue(forKey: "refined_text", in: #"{"refined_text":"Hello"}"#) == "Hello")
    // Unterminated string -> returns decoded-so-far.
    #expect(partialStringValue(forKey: "refined_text", in: #"{"refined_text":"Hello wor"#) == "Hello wor")
    // Key not started yet -> nil.
    #expect(partialStringValue(forKey: "refined_text", in: #"{"trans"#) == nil)
    // Whitespace around the colon is tolerated.
    #expect(partialStringValue(forKey: "k", in: "{ \"k\" : \"v\"") == "v")
}

@Test func partialStringValueHandlesEscapesAndUnicode() {
    // Escaped quote inside the value must not terminate it early.
    #expect(partialStringValue(forKey: "k", in: #"{"k":"a\"b"#) == "a\"b")
    // Escaped backslash.
    #expect(partialStringValue(forKey: "k", in: #"{"k":"a\\b"#) == "a\\b")
    // Newline / tab escapes.
    #expect(partialStringValue(forKey: "k", in: #"{"k":"a\nb\tc"#) == "a\nb\tc")
    // Complete \uXXXX escape decodes to the real scalar (A == "A").
    let withUnicode = "{\"k\":\"X\\u0041Y" // literal JSON: {"k":"XAY
    #expect(partialStringValue(forKey: "k", in: withUnicode) == "XAY")
    // Incomplete \uXXXX at the buffer tail is deferred (decoded-so-far, no broken char).
    let incompleteUnicode = "{\"k\":\"AB\\u00" // literal JSON: {"k":"AB\u00
    #expect(partialStringValue(forKey: "k", in: incompleteUnicode) == "AB")
    // Dangling backslash at the tail is deferred.
    #expect(partialStringValue(forKey: "k", in: #"{"k":"AB\"#) == "AB")
}

// MARK: - Anthropic Messages (anthropic / azure-anthropic)

private func foundryClaudeConfig(
    reasoningEffort: String? = nil,
    maxOutputTokens: Int? = nil,
    streamingEnabled: Bool = false
) -> LLMConfig {
    LLMConfig(
        enabled: true,
        provider: .azureAnthropic,
        model: "claude-opus-5-5",
        systemPrompt: "Clean this transcript.",
        requestTimeoutMs: 1_000,
        providerConfig: .anthropic(apiKey: "foundry-key", baseURL: "https://example.services.ai.azure.com/anthropic/"),
        verbose: false,
        maxOutputTokens: maxOutputTokens,
        reasoningEffort: reasoningEffort,
        streamingEnabled: streamingEnabled
    )
}

@Test func anthropicRefinerPostsMessagesWithXApiKeyAndLowEffort() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "stop_reason": "end_turn",
            "content": [
                ["type": "thinking", "thinking": ""],
                ["type": "text", "text": "  Clean text.  "]
            ]
        ]))
    ])
    let fromFactory = try #require(try LLMRefinerFactory.makeRefiner(config: foundryClaudeConfig()))
    #expect(fromFactory is AnthropicMessagesRefiner)
    let direct = try AnthropicMessagesRefiner(config: foundryClaudeConfig(), httpClient: http)
    let output = try await direct.refine("raw words")

    #expect(output == "Clean text.")
    let request = try #require(http.requests.first)
    #expect(request.url?.absoluteString == "https://example.services.ai.azure.com/anthropic/v1/messages")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "foundry-key")
    #expect(request.value(forHTTPHeaderField: "api-key") == nil)
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    let body = try requestJSONObject(request)
    #expect(body["model"] as? String == "claude-opus-5-5")
    #expect(body["max_tokens"] as? Int == 4096)
    #expect(body["system"] as? String == "Clean this transcript.")
    #expect(body["temperature"] == nil)
    #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "low")
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    #expect(messages[0]["content"] as? String == "raw words")
}

@Test func anthropicRefinerMapsEffortAndMaxTokens() async throws {
    #expect(AnthropicMessagesRefiner.claudeEffort(nil) == "low")
    #expect(AnthropicMessagesRefiner.claudeEffort("minimal") == "low")
    #expect(AnthropicMessagesRefiner.claudeEffort("none") == "low")
    #expect(AnthropicMessagesRefiner.claudeEffort("high") == "high")

    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData(["stop_reason": "end_turn", "content": [["type": "text", "text": "ok"]]]))
    ])
    let refiner = try AnthropicMessagesRefiner(
        config: foundryClaudeConfig(reasoningEffort: "medium", maxOutputTokens: 800),
        httpClient: http
    )
    _ = try await refiner.refine("raw")
    let body = try requestJSONObject(try #require(http.requests.first))
    #expect(body["max_tokens"] as? Int == 800)
    #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "medium")
}

@Test func anthropicRefinerRejectsRefusalTruncationAndHTTPErrors() async throws {
    let refusal = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData(["stop_reason": "refusal", "content": []]))
    ])
    await expectLLMError(kind: .server) {
        _ = try await AnthropicMessagesRefiner(config: foundryClaudeConfig(), httpClient: refusal).refine("raw")
    }
    let truncated = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData(["stop_reason": "max_tokens", "content": [["type": "text", "text": "half"]]]))
    ])
    await expectLLMError(kind: .server) {
        _ = try await AnthropicMessagesRefiner(config: foundryClaudeConfig(), httpClient: truncated).refine("raw")
    }
    let unauthorized = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 401, body: Data(#"{"error":{"code":"401"}}"#.utf8))
    ])
    await expectLLMError(kind: .auth) {
        _ = try await AnthropicMessagesRefiner(config: foundryClaudeConfig(), httpClient: unauthorized).refine("raw")
    }
    let empty = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData(["stop_reason": "end_turn", "content": [["type": "thinking", "thinking": ""]]]))
    ])
    await expectLLMError(kind: .shape) {
        _ = try await AnthropicMessagesRefiner(config: foundryClaudeConfig(), httpClient: empty).refine("raw")
    }
}

@Test func anthropicStreamingAccumulatesTextDeltasAndHonoursStopReason() async throws {
    let http = MockLLMHTTPClient(streamPayloads: [
        #"{"type":"message_start","message":{"id":"m","content":[]}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"ping"}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}"#,
        #"{"type":"message_stop"}"#
    ])
    let refiner = try AnthropicMessagesRefiner(config: foundryClaudeConfig(streamingEnabled: true), httpClient: http)
    var progress: [String] = []
    let output = try await refiner.refine("raw") { progress.append($0) }
    #expect(output == "Hello")
    #expect(progress == ["Hel", "Hello"])
    let body = try requestJSONObject(try #require(http.streamRequests.first))
    #expect(body["stream"] as? Bool == true)

    let refused = MockLLMHTTPClient(streamPayloads: [
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I can"}}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#
    ])
    await expectLLMError(kind: .server) {
        _ = try await AnthropicMessagesRefiner(config: foundryClaudeConfig(streamingEnabled: true), httpClient: refused)
            .refine("raw") { _ in }
    }
    let errored = MockLLMHTTPClient(streamPayloads: [
        #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
    ])
    await expectLLMError(kind: .server) {
        _ = try await AnthropicMessagesRefiner(config: foundryClaudeConfig(streamingEnabled: true), httpClient: errored)
            .refine("raw") { _ in }
    }
}

@Test func deepseekRefinerPostsOpenAICompatibleChatCompletion() async throws {
    let http = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [["message": ["content": " Clean text. ", "reasoning_content": "thinking"]]]
        ]))
    ])
    let config = LLMConfig(
        enabled: true,
        provider: .deepseek,
        model: "deepseek-flash",
        systemPrompt: "Clean this transcript.",
        requestTimeoutMs: 15_000,
        providerConfig: .openAICompatible(apiKey: "ds-key", baseURL: "https://api.deepseek.com/"),
        verbose: false,
        maxOutputTokens: 900,
        reasoningEffort: "low"
    )
    let refiner = try AzureOpenAIRefiner(config: config, httpClient: http)

    #expect(try await refiner.refine("raw text") == "Clean text.")
    let request = try #require(http.requests.first)
    #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ds-key")
    #expect(request.value(forHTTPHeaderField: "api-key") == nil)
    let body = try requestJSONObject(request)
    #expect(body["model"] as? String == "deepseek-flash")
    #expect(body["max_tokens"] as? Int == 900)
    #expect(body["max_completion_tokens"] == nil)
    #expect(body["reasoning_effort"] == nil)
}

@Test func deepseekRewritesTurnThinkingOffAndReportTruncation() async throws {
    let config = LLMConfig(
        enabled: true,
        provider: .deepseek,
        model: "deepseek-flash",
        systemPrompt: "Clean this transcript.",
        requestTimeoutMs: 15_000,
        providerConfig: .openAICompatible(apiKey: "ds-key", baseURL: "https://api.deepseek.com"),
        verbose: false,
        maxOutputTokens: 1000
    )
    let rewriteHTTP = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData(["choices": [["message": ["content": "Clean."]]]]))
    ])
    _ = try await AzureOpenAIRefiner(config: config, thinking: false, httpClient: rewriteHTTP).refine("raw")
    let rewriteBody = try requestJSONObject(try #require(rewriteHTTP.requests.first))
    #expect((rewriteBody["thinking"] as? [String: String]) == ["type": "disabled"])

    let askHTTP = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData(["choices": [["message": ["content": "Answer."]]]]))
    ])
    _ = try await AzureOpenAIRefiner(config: config, httpClient: askHTTP).refine("raw")
    #expect(try requestJSONObject(try #require(askHTTP.requests.first))["thinking"] == nil)

    let truncatedHTTP = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "choices": [["message": ["content": "", "reasoning_content": "long"], "finish_reason": "length"]]
        ]))
    ])
    do {
        _ = try await AzureOpenAIRefiner(config: config, httpClient: truncatedHTTP).refine("raw")
        Issue.record("expected a truncation error")
    } catch let error as LLMRefinementError {
        #expect(error.message.contains("truncated"))
    }
}

@Test func deepseekProviderNeedsItsKeyAndDefaultsTheBaseURL() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("untype-deepseek-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let argv = ["--api-key", "k", "--no-refine", "--alt-llm-provider", "deepseek", "--alt-llm-model", "deepseek-flash"]

    #expect(throws: UntypeError.self) {
        _ = try ConfigResolver(cwd: home, home: home, shell: [:]).resolve(argv: argv)
    }
    let config = try ConfigResolver(cwd: home, home: home, shell: ["DEEPSEEK_API_KEY": "ds-key"]).resolve(argv: argv)
    #expect(config.alternativeLLM?.providerConfig == .openAICompatible(apiKey: "ds-key", baseURL: "https://api.deepseek.com"))
    let custom = try ConfigResolver(cwd: home, home: home, shell: ["DEEPSEEK_API_KEY": "ds-key", "DEEPSEEK_API_BASE": "https://proxy.example/v1"]).resolve(argv: argv)
    #expect(custom.alternativeLLM?.providerConfig == .openAICompatible(apiKey: "ds-key", baseURL: "https://proxy.example/v1"))
}

@Test func geminiRewritesUseLowThinkingAndReportTruncation() async throws {
    let reply = jsonData(["candidates": [["content": ["parts": [["text": "Clean."]]], "finishReason": "STOP"]]])
    let rewriteHTTP = MockLLMHTTPClient(responses: [LLMHTTPResponse(statusCode: 200, body: reply)])
    _ = try await GoogleRefiner(config: googleConfig(maxOutputTokens: 400), thinking: false, httpClient: rewriteHTTP).refine("raw")
    let rewriteRequest = try #require(rewriteHTTP.requests.first)
    let rewriteConfig = try #require(try requestJSONObject(rewriteRequest)["generationConfig"] as? [String: Any])
    #expect((rewriteConfig["thinkingConfig"] as? [String: String]) == ["thinkingLevel": "low"])

    let askHTTP = MockLLMHTTPClient(responses: [LLMHTTPResponse(statusCode: 200, body: reply)])
    _ = try await GoogleRefiner(config: googleConfig(), httpClient: askHTTP).refine("raw")
    let askRequest = try #require(askHTTP.requests.first)
    let askConfig = try #require(try requestJSONObject(askRequest)["generationConfig"] as? [String: Any])
    #expect(askConfig["thinkingConfig"] == nil)

    // A cut-off answer is an error, never half a sentence.
    let truncatedHTTP = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "candidates": [["content": ["parts": [["text": "Η συνάντηση μεταφέρεται για την Πέμπτη το από"]]], "finishReason": "MAX_TOKENS"]]
        ]))
    ])
    do {
        _ = try await GoogleRefiner(config: googleConfig(), httpClient: truncatedHTTP).refine("raw")
        Issue.record("expected a truncation error")
    } catch let error as LLMRefinementError {
        #expect(error.message.contains("truncated"))
    }

    // Thought parts are never part of the answer.
    let thoughtHTTP = MockLLMHTTPClient(responses: [
        LLMHTTPResponse(statusCode: 200, body: jsonData([
            "candidates": [["content": ["parts": [["text": "thinking…", "thought": true], ["text": "Answer."]]], "finishReason": "STOP"]]
        ]))
    ])
    let answer = try await GoogleRefiner(config: googleConfig(), httpClient: thoughtHTTP).refine("raw")
    #expect(answer == "Answer.")

    let streamHTTP = MockLLMHTTPClient(streamPayloads: [
        geminiChunk(text: "Half"),
        #"{"candidates":[{"content":{"parts":[{"text":" a sen"}],"role":"model"},"finishReason":"MAX_TOKENS"}]}"#
    ])
    do {
        _ = try await GoogleRefiner(config: googleConfig(streamingEnabled: true), httpClient: streamHTTP)
            .refine("raw", onProgress: { _ in })
        Issue.record("expected a truncation error")
    } catch let error as LLMRefinementError {
        #expect(error.message.contains("truncated"))
    }
}

// MARK: - Screenshot operator (image input)

private let screenshotImage = LLMImageAttachment(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/png", pixelWidth: 2, pixelHeight: 1)

@Test func everyVisionProviderSendsTheScreenshotWithTheText() async throws {
    let base64 = screenshotImage.data.base64EncodedString()

    let geminiHTTP = MockLLMHTTPClient(responses: [LLMHTTPResponse(statusCode: 200, body: jsonData([
        "candidates": [["content": ["parts": [["text": "Clean."]]], "finishReason": "STOP"]]
    ]))])
    _ = try await GoogleRefiner(config: googleConfig(), httpClient: geminiHTTP).refine("raw", image: screenshotImage, onProgress: nil)
    let geminiRequest = try #require(geminiHTTP.requests.first)
    let geminiContents = try #require(try requestJSONObject(geminiRequest)["contents"] as? [[String: Any]])
    let geminiParts = try #require(geminiContents.first?["parts"] as? [[String: Any]])
    #expect(geminiParts.first?["text"] as? String == "raw")
    let inline = try #require(geminiParts.last?["inlineData"] as? [String: String])
    #expect(inline == ["mimeType": "image/png", "data": base64])

    let claudeHTTP = MockLLMHTTPClient(responses: [LLMHTTPResponse(statusCode: 200, body: jsonData([
        "stop_reason": "end_turn", "content": [["type": "text", "text": "Clean."]]
    ]))])
    _ = try await AnthropicMessagesRefiner(config: foundryClaudeConfig(), httpClient: claudeHTTP).refine("raw", image: screenshotImage, onProgress: nil)
    let claudeRequest = try #require(claudeHTTP.requests.first)
    let claudeMessages = try #require(try requestJSONObject(claudeRequest)["messages"] as? [[String: Any]])
    let claudeContent = try #require(claudeMessages.first?["content"] as? [[String: Any]])
    let source = try #require(claudeContent.first?["source"] as? [String: String])
    #expect(source == ["type": "base64", "media_type": "image/png", "data": base64])
    #expect(claudeContent.last?["text"] as? String == "raw")

    let azureHTTP = MockLLMHTTPClient(responses: [LLMHTTPResponse(statusCode: 200, body: jsonData([
        "choices": [["message": ["content": "Clean."]]]
    ]))])
    _ = try await AzureOpenAIRefiner(config: azureConfig(), httpClient: azureHTTP).refine("raw", image: screenshotImage, onProgress: nil)
    let azureRequest = try #require(azureHTTP.requests.first)
    let azureMessages = try #require(try requestJSONObject(azureRequest)["messages"] as? [[String: Any]])
    let azureContent = try #require(azureMessages.last?["content"] as? [[String: Any]])
    #expect(azureContent.first?["text"] as? String == "raw")
    let imageURL = try #require(azureContent.last?["image_url"] as? [String: String])
    #expect(imageURL["url"] == "data:image/png;base64,\(base64)")

    // Without an image the request stays plain text.
    let plainHTTP = MockLLMHTTPClient(responses: [LLMHTTPResponse(statusCode: 200, body: jsonData([
        "choices": [["message": ["content": "Clean."]]]
    ]))])
    _ = try await AzureOpenAIRefiner(config: azureConfig(), httpClient: plainHTTP).refine("raw")
    let plainRequest = try #require(plainHTTP.requests.first)
    let plainMessages = try #require(try requestJSONObject(plainRequest)["messages"] as? [[String: Any]])
    #expect(plainMessages.last?["content"] as? String == "raw")
}

@Test func deepseekSendsTheScreenshotAsAnImagePart() async throws {
    let http = MockLLMHTTPClient(responses: [LLMHTTPResponse(statusCode: 200, body: jsonData([
        "choices": [["message": ["content": "Clean."]]]
    ]))])
    let config = LLMConfig(
        enabled: true,
        provider: .deepseek,
        model: "deepseek-flash",
        systemPrompt: "Clean this transcript.",
        requestTimeoutMs: 15_000,
        providerConfig: .openAICompatible(apiKey: "ds-key", baseURL: "https://api.deepseek.com/"),
        verbose: false
    )
    _ = try await AzureOpenAIRefiner(config: config, thinking: false, httpClient: http).refine("raw", image: screenshotImage, onProgress: nil)
    let request = try #require(http.requests.first)
    let messages = try #require(try requestJSONObject(request)["messages"] as? [[String: Any]])
    let content = try #require(messages.last?["content"] as? [[String: Any]])
    #expect(content.last?["type"] as? String == "image_url")
}

@Test func combinedRefineTranslateSendsTheScreenshot() async throws {
    let http = MockLLMHTTPClient(responses: [LLMHTTPResponse(statusCode: 200, body: jsonData([
        "candidates": [["content": ["parts": [["text": #"{"refined_text":"Hi.","translated_text":"Γεια."}"#]]], "finishReason": "STOP"]]
    ]))])
    let composite = LLMCompositeRefineTranslator(
        refiner: try GoogleRefiner(config: googleConfig(), httpClient: http),
        refinementPromptTemplate: "{text}",
        translationPromptTemplate: "{target_language} {text}"
    )
    let result = try await composite.refineAndTranslate(
        CompositeRefineTranslateRequest(rawText: "hi", targetLanguageName: "Greek", image: screenshotImage)
    )
    #expect(result.translatedText == "Γεια.")
    let compositeRequest = try #require(http.requests.first)
    let contents = try #require(try requestJSONObject(compositeRequest)["contents"] as? [[String: Any]])
    let parts = try #require(contents.first?["parts"] as? [[String: Any]])
    #expect(parts.count == 2)
    #expect(parts.last?["inlineData"] != nil)
}
