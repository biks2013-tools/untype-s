import Foundation
import Testing
@testable import UntypeCore

private let altMarkers = MarkerConfig(
    commandPhrase: "command",
    sectionEndPhrase: "command send",
    sectionEndAliases: [],
    sectionCancelPhrase: "command cancel",
    literalNextPhrase: "literal phrase"
)

private final class AltMockRefiner: TextRefining, @unchecked Sendable {
    private let reply: String
    private(set) var calls: [String] = []

    init(_ reply: String) {
        self.reply = reply
    }

    func refine(_ text: String) async throws -> String {
        calls.append(text)
        return reply
    }
}

private struct AltTemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-alt-llm-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private func altEvents(_ text: String) throws -> [[String: Any]] {
    try text.split(separator: "\n").map { line in
        try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] ?? [:]
    }
}

private func makeController(
    operators: OperatorState,
    primary: ProtocolLLMClients,
    alternative: ProtocolLLMClients?,
    output: MemoryOutput,
    diagnostics: MemoryOutput = MemoryOutput()
) -> VoiceAgentProtocolController {
    VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: output),
        markers: altMarkers,
        initialOperators: operators,
        translationPolicy: .opposite,
        refiner: primary.refiner,
        translator: primary.translator,
        compositeRefineTranslator: primary.compositeRefineTranslator,
        asker: primary.asker,
        alternativeLLM: alternative,
        askUserPromptTemplate: "Request: {text}",
        diagnostics: ProtocolControllerDiagnostics(write: { line, _ in diagnostics.write(line + "\n") })
    )
}

@Test func alternativeOperatorSendsRefineToTheAlternativeLLM() async throws {
    let output = MemoryOutput()
    let primary = AltMockRefiner("primary refined")
    let alternative = AltMockRefiner("alternative refined")
    let controller = makeController(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, alternative: true),
        primary: ProtocolLLMClients(refiner: primary, translator: nil, compositeRefineTranslator: nil, asker: nil),
        alternative: ProtocolLLMClients(refiner: alternative, translator: nil, compositeRefineTranslator: nil, asker: nil),
        output: output
    )

    try controller.startSession()
    try await controller.final("some dictated text command send")

    let processed = try altEvents(output.text).first { $0["type"] as? String == "section.processed" }
    #expect(primary.calls.isEmpty)
    #expect(alternative.calls == ["some dictated text"])
    #expect(processed?["output_text"] as? String == "alternative refined")
    #expect((processed?["operators"] as? [String])?.contains("alternative") == true)
}

@Test func withoutTheAlternativeOperatorThePrimaryLLMIsUsed() async throws {
    let output = MemoryOutput()
    let primary = AltMockRefiner("primary answer")
    let alternative = AltMockRefiner("alternative answer")
    let controller = makeController(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true),
        primary: ProtocolLLMClients(refiner: nil, translator: nil, compositeRefineTranslator: nil, asker: primary),
        alternative: ProtocolLLMClients(refiner: nil, translator: nil, compositeRefineTranslator: nil, asker: alternative),
        output: output
    )

    try controller.startSession()
    try await controller.final("what time is it command send")

    #expect(primary.calls == ["Request: what time is it"])
    #expect(alternative.calls.isEmpty)
}

@Test func alternativeOperatorSendsAskAndTranslateToTheAlternativeLLM() async throws {
    let output = MemoryOutput()
    let primaryAsker = AltMockRefiner("primary")
    let alternativeAsker = AltMockRefiner("alt answer")
    let alternativeTranslator = AltMockRefiner("alt translation")
    let askController = makeController(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true, alternative: true),
        primary: ProtocolLLMClients(refiner: nil, translator: nil, compositeRefineTranslator: nil, asker: primaryAsker),
        alternative: ProtocolLLMClients(refiner: nil, translator: nil, compositeRefineTranslator: nil, asker: alternativeAsker),
        output: output
    )
    try askController.startSession()
    try await askController.final("draft a note command send")
    #expect(primaryAsker.calls.isEmpty)
    #expect(alternativeAsker.calls == ["Request: draft a note"])

    let primaryTranslator = AltMockRefiner("primary translation")
    let translateController = makeController(
        operators: OperatorState(refine: false, translate: true, clipboard: false, input: false, alternative: true),
        primary: ProtocolLLMClients(refiner: nil, translator: primaryTranslator, compositeRefineTranslator: nil, asker: nil),
        alternative: ProtocolLLMClients(refiner: nil, translator: alternativeTranslator, compositeRefineTranslator: nil, asker: nil),
        output: MemoryOutput()
    )
    try translateController.startSession()
    try await translateController.final("καλημέρα σε όλους command send")
    #expect(primaryTranslator.calls.isEmpty)
    #expect(alternativeTranslator.calls.count == 1)
}

@Test func unconfiguredAlternativeLLMNeverFallsBackToThePrimary() async throws {
    let output = MemoryOutput()
    let diagnostics = MemoryOutput()
    let primary = AltMockRefiner("primary refined")
    let controller = makeController(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, alternative: true),
        primary: ProtocolLLMClients(refiner: primary, translator: nil, compositeRefineTranslator: nil, asker: nil),
        alternative: nil,
        output: output,
        diagnostics: diagnostics
    )

    try controller.startSession()
    try await controller.final("keep this text command send")

    let processed = try altEvents(output.text).first { $0["type"] as? String == "section.processed" }
    #expect(primary.calls.isEmpty)
    #expect(processed?["output_text"] as? String == "keep this text")
    #expect(diagnostics.text.contains("no alternative LLM is configured"))
    #expect(!diagnostics.text.contains("no LLM refiner is configured"))
}

@Test func alternativeLLMIsResolvedFromItsOwnProviderAndModel() throws {
    let temp = AltTemporaryDirectory()
    let shell = [
        "AZURE_OPENAI_API_KEY": "azure-key",
        "AZURE_OPENAI_ENDPOINT": "https://example.openai.azure.com",
        "AZURE_OPENAI_DEPLOYMENT": "primary-deployment",
        "UNTYPE_ALT_LLM_PROVIDER": "azure-openai",
        "UNTYPE_ALT_LLM_MODEL": "gpt-5-mini"
    ]
    let config = try ConfigResolver(cwd: temp.url, home: temp.url, shell: shell)
        .resolve(argv: ["--api-key", "k", "--no-refine", "--alternative-default", "on"])

    let alternative = try #require(config.alternativeLLM)
    #expect(alternative.enabled)
    #expect(alternative.provider == .azureOpenAI)
    #expect(alternative.model == "gpt-5-mini")
    #expect(alternative.providerConfig == .azureOpenAI(
        apiKey: "azure-key",
        endpoint: "https://example.openai.azure.com",
        deployment: "gpt-5-mini",
        apiVersion: "2024-10-21"
    ))
    #expect(alternative.systemPrompt == config.llm.systemPrompt)
    #expect(config.protocolConfig.initialOperators.alternative)
}

@Test func alternativeLLMIsAbsentWhenNoProviderIsSet() throws {
    let temp = AltTemporaryDirectory()
    let config = try ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
        .resolve(argv: ["--api-key", "k", "--no-refine"])

    #expect(config.alternativeLLM == nil)
    #expect(config.protocolConfig.initialOperators.alternative == false)
}

@Test func alternativeLLMRequiresBothProviderAndModelAndItsCredentials() {
    let temp = AltTemporaryDirectory()
    let resolve: ([String: String], [String]) throws -> ResolvedConfig = { shell, extra in
        try ConfigResolver(cwd: temp.url, home: temp.url, shell: shell)
            .resolve(argv: ["--api-key", "k", "--no-refine"] + extra)
    }

    #expect(throws: UntypeError.self) { _ = try resolve([:], ["--alt-llm-provider", "google"]) }
    #expect(throws: UntypeError.self) { _ = try resolve([:], ["--alt-llm-model", "gemini-3"]) }
    #expect(throws: UntypeError.self) { _ = try resolve([:], ["--alt-llm-provider", "nope", "--alt-llm-model", "m"]) }
    #expect(throws: UntypeError.self) { _ = try resolve([:], ["--alt-llm-provider", "google", "--alt-llm-model", "gemini-3"]) }
    #expect(throws: Never.self) {
        _ = try resolve(["GOOGLE_API_KEY": "g"], ["--alt-llm-provider", "google", "--alt-llm-model", "gemini-3"])
    }
}

@Test func uiSettingsPassTheAlternativeLLMOnlyWhenComplete() throws {
    #expect(UntypeUISettings.default.alternative == false)
    #expect(UntypeUISettings.default.altLlmProvider.isEmpty)
    #expect(!(try UntypeUISettings.default.sessionArguments().contains("--alt-llm-provider")))

    let providerOnly = try UntypeUISettings.default.merged(UntypeUISettingsPatch(altLlmProvider: "azure-openai"))
    #expect(!(try providerOnly.sessionArguments().contains("--alt-llm-provider")))

    let complete = try providerOnly.merged(UntypeUISettingsPatch(alternative: true, altLlmModel: " gpt-5-mini "))
    let args = try complete.sessionArguments()
    #expect(args.contains("--alt-llm-provider"))
    #expect(args.contains("gpt-5-mini"))
    #expect(args.contains("--alternative-default"))
    #expect(complete.value(of: .alternative))

    #expect(throws: UntypeError.self) {
        _ = try UntypeUISettings.default.merged(UntypeUISettingsPatch(altLlmProvider: "nope"))
    }
}

@Test func uiSettingsStoreRoundTripsTheAlternativeLLM() throws {
    let temp = AltTemporaryDirectory()
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        alternative: true,
        altLlmProvider: "google",
        altLlmModel: "gemini-3"
    ))

    try UntypeUISettingsStore.save(settings, home: temp.url)
    let loaded = try UntypeUISettingsStore.load(home: temp.url)

    #expect(loaded.alternative)
    #expect(loaded.altLlmProvider == "google")
    #expect(loaded.altLlmModel == "gemini-3")
}

@Test func secondAlternativeLLMIsResolvedIndependentlyAndReachesTheSessionArguments() throws {
    let temp = AltTemporaryDirectory()
    let shell = ["DEEPSEEK_API_KEY": "ds-key", "GOOGLE_API_KEY": "g-key"]
    let config = try ConfigResolver(cwd: temp.url, home: temp.url, shell: shell).resolve(argv: [
        "--api-key", "k", "--no-refine",
        "--alt-llm-provider", "deepseek", "--alt-llm-model", "deepseek-flash",
        "--alt2-llm-provider", "google", "--alt2-llm-model", "gemini-3.8-flash"
    ])
    #expect(config.alternativeLLM?.model == "deepseek-flash")
    let second = try #require(config.alternativeLLM2)
    #expect(second.provider == .google)
    #expect(second.model == "gemini-3.8-flash")
    #expect(second.providerConfig == .google(apiKey: "g-key"))
    #expect(second.systemPrompt == config.llm.systemPrompt)

    // Same rules as the first slot: both values, and the provider's key.
    #expect(throws: UntypeError.self) {
        _ = try ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
            .resolve(argv: ["--api-key", "k", "--no-refine", "--alt2-llm-model", "gemini-3.8-flash"])
    }
    #expect(throws: UntypeError.self) {
        _ = try ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
            .resolve(argv: ["--api-key", "k", "--no-refine", "--alt2-llm-provider", "google", "--alt2-llm-model", "gemini-3.8-flash"])
    }

    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        alt2LlmProvider: "google",
        alt2LlmModel: "gemini-3.8-flash"
    ))
    let args = try settings.sessionArguments()
    #expect(args.contains("--alt2-llm-provider") && args.contains("gemini-3.8-flash"))
    #expect(!args.contains("--alt-llm-provider"))
    let modelOnly = try UntypeUISettings.default.merged(UntypeUISettingsPatch(alt2LlmModel: "gemini-3.8-flash"))
    #expect(!(try modelOnly.sessionArguments().contains("--alt2-llm-provider")))
}

@Test func secondAlternativeLLMSettingsRoundTrip() throws {
    let temp = AltTemporaryDirectory()
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        alt2LlmProvider: "google",
        alt2LlmModel: "gemini-3.8-flash"
    ))
    try UntypeUISettingsStore.save(settings, home: temp.url)
    let loaded = try UntypeUISettingsStore.load(home: temp.url)
    #expect(loaded.alt2LlmProvider == "google")
    #expect(loaded.alt2LlmModel == "gemini-3.8-flash")
}
