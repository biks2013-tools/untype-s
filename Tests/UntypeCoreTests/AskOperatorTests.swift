import Foundation
import Testing
@testable import UntypeCore

private let askMarkers = MarkerConfig(
    commandPhrase: "command",
    sectionEndPhrase: "command send",
    sectionEndAliases: [],
    sectionCancelPhrase: "command cancel",
    literalNextPhrase: "literal phrase"
)

@Test func askOperatorReplacesTheRequestWithTheModelAnswer() async throws {
    let protocolOutput = MemoryOutput()
    let asker = AskMockRefiner { _ in "Three short tips for a good meeting." }
    let refiner = AskMockRefiner { _ in
        Issue.record("Refine must be skipped when Ask is on")
        return "refined"
    }
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: askMarkers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false, ask: true),
        translationPolicy: .opposite,
        refiner: refiner,
        asker: asker,
        askUserPromptTemplate: "Request: {text}"
    )

    try controller.startSession()
    try await controller.final("give me tips for a good meeting command send")

    let processed = try askProtocolEvents(protocolOutput.text).first { $0["type"] as? String == "section.processed" }
    #expect(asker.calls == ["Request: give me tips for a good meeting"])
    #expect(processed?["output_text"] as? String == "Three short tips for a good meeting.")
    #expect((processed?["operators"] as? [String])?.contains("ask") == true)
    #expect(refiner.calls.isEmpty)
}

@Test func askWithTranslateAnswersInTheTargetLanguageInOneCall() async throws {
    let protocolOutput = MemoryOutput()
    let asker = AskMockRefiner { _ in "An answer in English." }
    let translator = AskMockRefiner { _ in
        Issue.record("Translate must not run a second call when Ask is on")
        return "translated"
    }
    let composite = AskMockComposite()
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: askMarkers,
        initialOperators: OperatorState(refine: true, translate: true, clipboard: false, input: false, ask: true),
        translationPolicy: .opposite,
        translator: translator,
        compositeRefineTranslator: composite,
        asker: asker,
        askTranslatedUserPromptTemplate: "{text} -> {target_language}"
    )

    try controller.startSession()
    try await controller.final("γράψε μια περίληψη command send")

    let processed = try askProtocolEvents(protocolOutput.text).first { $0["type"] as? String == "section.processed" }
    #expect(asker.calls == ["γράψε μια περίληψη -> English"])
    #expect(processed?["output_text"] as? String == "An answer in English.")
    #expect(processed?["target_language"] as? String == "en")
    #expect(translator.calls.isEmpty)
    #expect(composite.requests == 0)
}

@Test func askFailureKeepsTheDictatedTextAndWarns() async throws {
    let protocolOutput = MemoryOutput()
    let diagnostics = MemoryOutput()
    let asker = AskMockRefiner { _ in throw LLMRefinementError("network down", kind: .network) }
    let controller = VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: protocolOutput),
        markers: askMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true),
        translationPolicy: .opposite,
        asker: asker,
        diagnostics: ProtocolControllerDiagnostics(write: { line, _ in diagnostics.write(line + "\n") }),
        visibleOperatorDiagnostics: true
    )

    try controller.startSession()
    try await controller.final("what is the capital of France command send")

    let processed = try askProtocolEvents(protocolOutput.text).first { $0["type"] as? String == "section.processed" }
    #expect(processed?["output_text"] as? String == "what is the capital of France")
    #expect(diagnostics.text.contains("ask operator failed: network down"))
}

@Test func askIsASpokenOperatorAndPersistsBackwardCompatibly() throws {
    let machine = VoiceCommandStateMachine(
        markers: askMarkers,
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    let result = machine.processFinal("command ask on")
    #expect(result.actions == [.stateChanged(key: .ask, value: true, targetPolicy: nil)])
    #expect(machine.state.ask)

    let legacy = #"{"refine":true,"translate":false,"clipboard":true,"input":true}"#
    let decoded = try JSONDecoder().decode(OperatorState.self, from: Data(legacy.utf8))
    #expect(decoded == OperatorState(refine: true, translate: false, clipboard: true, input: true, ask: false))
    let roundTrip = try JSONDecoder().decode(OperatorState.self, from: JSONEncoder().encode(machine.state))
    #expect(roundTrip.ask)
}

@Test func askDefaultFlagAndPromptFilesResolve() throws {
    let temp = AskTemporaryDirectory()
    let config = try ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
        .resolve(argv: ["--api-key", "test-key", "--no-refine", "--ask-default", "on"])
    #expect(config.protocolConfig.initialOperators.ask)
    #expect(config.protocolConfig.settingSources.ask == .configured)
    #expect(config.prompts.askSystemPrompt == UntypePromptDefaults.askSystemPrompt)
    #expect(config.prompts.askUserPromptTemplate.contains("{text}"))

    let prompts = PromptFileStore.userDirectory(home: temp.url)
    try "Answer: {text}".write(to: prompts.appendingPathComponent("012-ask-translated-user-template.txt"), atomically: true, encoding: .utf8)
    #expect(throws: UntypeError.self) {
        try ConfigResolver(cwd: temp.url, home: temp.url, shell: [:]).resolve(argv: ["--api-key", "test-key", "--no-refine"])
    }
}

@Test func uiSettingsCarryTheAskOperatorIntoSessionArguments() throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(ask: true))
    let args = try settings.sessionArguments()
    let index = try #require(args.firstIndex(of: "--ask-default"))
    #expect(args[index + 1] == "on")
}

private final class AskMockRefiner: TextRefining, @unchecked Sendable {
    private let handler: (String) async throws -> String
    private(set) var calls: [String] = []

    init(handler: @escaping (String) async throws -> String) {
        self.handler = handler
    }

    func refine(_ text: String) async throws -> String {
        calls.append(text)
        return try await handler(text)
    }
}

private final class AskMockComposite: CompositeRefineTranslating, @unchecked Sendable {
    private(set) var requests = 0

    func refineAndTranslate(_ request: CompositeRefineTranslateRequest) async throws -> CompositeRefineTranslateResult {
        requests += 1
        Issue.record("The composite call must be skipped when Ask is on")
        return CompositeRefineTranslateResult(refinedText: "r", translatedText: "t")
    }
}

private final class AskTemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-s-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func askProtocolEvents(_ text: String) throws -> [[String: Any]] {
    try text.split(separator: "\n").map { line in
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        return object as? [String: Any] ?? [:]
    }
}
