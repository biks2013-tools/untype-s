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

    init(responses: [LLMHTTPResponse] = [], error: Error? = nil) {
        self.responses = responses
        self.error = error
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

    func cancelAll() {
        cancelCount += 1
    }
}

private func azureConfig(
    endpoint: String = "https://example.openai.azure.com",
    deployment: String = "gpt-5.4",
    systemPrompt: String = "Clean this transcript."
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
        verbose: false
    )
}

private func googleConfig(systemPrompt: String = "Clean this transcript.") -> LLMConfig {
    LLMConfig(
        enabled: true,
        provider: .google,
        model: "gemini-3.5-flash",
        systemPrompt: systemPrompt,
        requestTimeoutMs: 1_000,
        providerConfig: .google(apiKey: "google-key"),
        verbose: false
    )
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
