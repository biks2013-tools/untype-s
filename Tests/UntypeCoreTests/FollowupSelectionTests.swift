import Foundation
import Testing
@testable import UntypeCore

private let markers = MarkerConfig(
    commandPhrase: "command",
    sectionEndPhrase: "command send",
    sectionEndAliases: [],
    sectionCancelPhrase: "command cancel",
    literalNextPhrase: "literal phrase"
)

private func controller(
    operators: OperatorState,
    output: MemoryOutput,
    refiner: TextRefining? = nil,
    translator: TextRefining? = nil,
    asker: TextRefining? = nil,
    turnContext: UntypeTurnContext? = nil,
    conversation: AskConversation? = nil
) -> VoiceAgentProtocolController {
    VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: output),
        markers: markers,
        initialOperators: operators,
        translationPolicy: .toEnglish,
        translationUserPromptTemplate: "To {target_language}: {text}",
        refiner: refiner,
        translator: translator,
        asker: asker,
        askUserPromptTemplate: "Request: {text}",
        turnContext: turnContext,
        askConversation: conversation,
        selectionContextTemplate: "REF[{selection}]",
        askSelectionTemplate: "SEL[{selection}]",
        askConversationTemplate: "HIST[{history}]"
    )
}

private func processedOutput(_ output: MemoryOutput) throws -> String? {
    let events = try output.text.split(separator: "\n").map {
        try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] ?? [:]
    }
    return events.last { $0["type"] as? String == "section.processed" }?["output_text"] as? String
}

@Test func selectionAsMaterialIsProcessedWithTheDictation() async throws {
    let output = MemoryOutput()
    let refiner = RecordingRefiner { "clean: \($0)" }
    let context = UntypeTurnContext(selectedText: "rough selected text", selectionRole: .material)
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, selection: true),
        output: output, refiner: refiner, turnContext: context
    )
    try sut.startSession()
    try await sut.final("and more command send")
    #expect(refiner.calls == ["rough selected text\n\nand more"])
    #expect(try processedOutput(output) == "clean: rough selected text\n\nand more")
}

@Test func selectionAsContextIsAReferenceBlockOnly() async throws {
    let output = MemoryOutput()
    let translator = RecordingRefiner { _ in "translated" }
    let context = UntypeTurnContext(selectedText: "glossary", selectionRole: .context)
    let sut = controller(
        operators: OperatorState(refine: false, translate: true, clipboard: false, input: false, selection: true),
        output: output, translator: translator, turnContext: context
    )
    try sut.startSession()
    try await sut.final("γεια σου command send")
    #expect(translator.calls == ["To English: γεια σου\n\nREF[glossary]"])
    #expect(try processedOutput(output) == "translated")
}

@Test func selectionIsIgnoredWhileTheOperatorIsOff() async throws {
    let output = MemoryOutput()
    let refiner = RecordingRefiner { $0 }
    let context = UntypeTurnContext(selectedText: "selected", selectionRole: .material)
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        output: output, refiner: refiner, turnContext: context
    )
    try sut.startSession()
    try await sut.final("dictated command send")
    #expect(refiner.calls == ["dictated"])
}

@Test func followupSendsTheConversationAndOffStartsANewOne() async throws {
    let conversation = AskConversation()
    let asker = RecordingRefiner { "answer to \($0.count)" }
    let first = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true),
        output: MemoryOutput(), asker: asker, conversation: conversation
    )
    try first.startSession()
    try await first.final("first question command send")
    #expect(asker.calls.last == "Request: first question")
    #expect(conversation.exchanges.count == 1)

    // A new runtime (next turn) with Follow-up on and a selection.
    let second = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true, followup: true, selection: true),
        output: MemoryOutput(), asker: asker,
        turnContext: UntypeTurnContext(selectedText: "the paragraph", selectionRole: .material),
        conversation: conversation
    )
    try second.startSession()
    try await second.final("make it shorter command send")
    let firstAnswer = conversation.exchanges[0].answer
    #expect(asker.calls.last == "HIST[User: first question\nAssistant: \(firstAnswer)]\n\nSEL[the paragraph]\n\nRequest: make it shorter")
    #expect(conversation.exchanges.count == 2)

    let third = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true),
        output: MemoryOutput(), asker: asker, conversation: conversation
    )
    try third.startSession()
    try await third.final("unrelated command send")
    #expect(asker.calls.last == "Request: unrelated")
    #expect(conversation.exchanges.map(\.request) == ["unrelated"])
}

@Test func aReleaseWithoutDictationStillProcessesASelection() async throws {
    let output = MemoryOutput()
    let translator = RecordingRefiner { _ in "Hello" }
    let material = controller(
        operators: OperatorState(refine: false, translate: true, clipboard: false, input: false, selection: true),
        output: output, translator: translator,
        turnContext: UntypeTurnContext(selectedText: "Γεια σου", selectionRole: .material)
    )
    try material.startSession()
    let summary = try await material.submitWithoutDictation()
    #expect(summary?.sectionsProcessed == 1)
    #expect(translator.calls == ["To English: Γεια σου"])
    #expect(try processedOutput(output) == "Hello")

    let context = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, selection: true),
        output: MemoryOutput(), refiner: RecordingRefiner { $0 },
        turnContext: UntypeTurnContext(selectedText: "reference", selectionRole: .context)
    )
    try context.startSession()
    #expect(try await context.submitWithoutDictation() == nil)

    let noSelection = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true, selection: true),
        output: MemoryOutput(), asker: RecordingRefiner { $0 },
        turnContext: UntypeTurnContext()
    )
    try noSelection.startSession()
    #expect(try await noSelection.submitWithoutDictation() == nil)
}

@Test func askConversationKeepsTheLatestExchanges() {
    let conversation = AskConversation()
    for index in 0..<(AskConversation.maxExchanges + 3) {
        conversation.append(AskExchange(request: "q\(index)", answer: "a\(index)"))
    }
    #expect(conversation.exchanges.count == AskConversation.maxExchanges)
    #expect(conversation.exchanges.first?.request == "q3")
}

@Test func perTurnOperatorsSwitchOffAfterATurn() throws {
    var settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(translate: true, ask: true, selection: true))
    #expect(settings.perTurnOperators == ["ask", "followup", "selection"])
    let patch = try #require(settings.perTurnResetPatch())
    settings = try settings.merged(patch)
    #expect(!settings.ask && !settings.selection)
    #expect(settings.translate)
    #expect(settings.perTurnResetPatch() == nil)

    let persistentAsk = try settings.merged(UntypeUISettingsPatch(ask: true, perTurnOperators: settings.settingPerTurn(.ask, false)))
    #expect(persistentAsk.perTurnResetPatch() == nil)
    let perTurnTranslate = try settings.merged(UntypeUISettingsPatch(perTurnOperators: settings.settingPerTurn(.translate, true)))
    #expect(perTurnTranslate.perTurnResetPatch() == UntypeUISettingsPatch(translate: false))

    #expect(throws: UntypeError.self) { try UntypeUISettings.default.merged(UntypeUISettingsPatch(selectionRole: "both")) }
    #expect(throws: UntypeError.self) { try UntypeUISettings.default.merged(UntypeUISettingsPatch(perTurnOperators: ["nope"])) }
}

@Test func followupAndSelectionResolveFromFlagsAndPrompts() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("untype-s-tests").appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let config = try ConfigResolver(cwd: home, home: home, shell: ["UNTYPE_SELECTION_DEFAULT": "on"])
        .resolve(argv: ["--api-key", "k", "--no-refine", "--followup-default", "on"])
    #expect(config.protocolConfig.initialOperators.followup)
    #expect(config.protocolConfig.initialOperators.selection)
    #expect(config.prompts.askConversationTemplate.contains("{history}"))

    try "no placeholder".write(to: PromptFileStore.userDirectory(home: home).appendingPathComponent("013-selection-context-template.txt"), atomically: true, encoding: .utf8)
    #expect(throws: UntypeError.self) {
        try ConfigResolver(cwd: home, home: home, shell: [:]).resolve(argv: ["--api-key", "k", "--no-refine"])
    }

    let legacy = #"{"refine":true,"translate":false,"clipboard":false,"input":true,"ask":true}"#
    let decoded = try JSONDecoder().decode(OperatorState.self, from: Data(legacy.utf8))
    #expect(decoded.ask && !decoded.followup && !decoded.selection)
}

private final class RecordingRefiner: TextRefining, @unchecked Sendable {
    private let handler: (String) -> String
    private(set) var calls: [String] = []

    init(handler: @escaping (String) -> String) {
        self.handler = handler
    }

    func refine(_ text: String) async throws -> String {
        calls.append(text)
        return handler(text)
    }
}
