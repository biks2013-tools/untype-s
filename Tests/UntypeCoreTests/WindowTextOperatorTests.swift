import Foundation
import Testing
@testable import UntypeCore

private func node(_ role: String, _ value: String? = nil, subrole: String? = nil, _ children: [WindowTextNode] = []) -> WindowTextNode {
    WindowTextNode(role: role, subrole: subrole, value: value, children: children)
}

@Test func windowTextCollectsTextElementsInReadingOrder() {
    let window = node("AXWindow", nil, [
        node("AXToolbar", nil, [node("AXStaticText", "Reply")]),
        node("AXGroup", "Subject line duplicated by the group", [node("AXStaticText", "  Subject line ")]),
        node("AXScrollArea", nil, [
            node("AXWebArea", nil, [
                node("AXStaticText", "First paragraph."),
                node("AXLink", nil, [node("AXStaticText", "a link")]),
                node("AXTextArea", "Draft reply", [node("AXStaticText", "Draft reply")])
            ])
        ]),
        node("AXButton", "Send")
    ])
    let result = WindowTextCollector.text(of: window)
    #expect(result.text == "Subject line\nFirst paragraph.\na link\nDraft reply")
    #expect(!result.truncated)
}

@Test func windowTextSkipsPasswordsEmptyValuesAndRepeats() {
    let window = node("AXWindow", nil, [
        node("AXTextField", "secret", subrole: "AXSecureTextField"),
        node("AXStaticText", "   "),
        node("AXStaticText", "Same"),
        node("AXStaticText", "Same"),
        node("AXStaticText", "Other")
    ])
    #expect(WindowTextCollector.text(of: window).text == "Same\nOther")
}

@Test func windowTextIsCutAtTheLimit() {
    let window = node("AXWindow", nil, [
        node("AXStaticText", "12345"),
        node("AXStaticText", "abcdefghij"),
        node("AXStaticText", "never reached")
    ])
    let result = WindowTextCollector.text(of: window, maxCharacters: 10)
    #expect(result.text == "12345\nabcd")
    #expect(result.truncated)
}

private final class EchoRefiner: TextRefining, @unchecked Sendable {
    var calls: [String] = []
    func refine(_ text: String) async throws -> String {
        calls.append(text)
        return "out"
    }
}

private func controller(
    operators: OperatorState,
    output: MemoryOutput = MemoryOutput(),
    refiner: TextRefining? = nil,
    asker: TextRefining? = nil,
    turnContext: UntypeTurnContext
) -> VoiceAgentProtocolController {
    VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: output),
        markers: MarkerConfig(
            commandPhrase: "command",
            sectionEndPhrase: "command send",
            sectionEndAliases: [],
            sectionCancelPhrase: "command cancel",
            literalNextPhrase: "literal phrase"
        ),
        initialOperators: operators,
        translationPolicy: .toEnglish,
        refiner: refiner,
        asker: asker,
        askUserPromptTemplate: "Request: {text}",
        turnContext: turnContext,
        windowTextContextTemplate: "WIN[{app}|{text}]",
        askWindowTextTemplate: "ASKWIN[{app}|{text}]"
    )
}

@Test func windowTextIsAReferenceBlockOfRefine() async throws {
    let refiner = EchoRefiner()
    let context = UntypeTurnContext(windowText: WindowText(text: "the whole email", appName: "Mail"))
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, windowText: true),
        refiner: refiner, turnContext: context
    )
    try sut.startSession()
    try await sut.final("my reply command send")
    #expect(refiner.calls == ["my reply\n\nWIN[Mail|the whole email]"])
}

@Test func windowTextGoesBeforeAnAskRequestAndAllowsAnAskWithoutDictation() async throws {
    let asker = EchoRefiner()
    let context = UntypeTurnContext(windowText: WindowText(text: "the whole email", appName: "Mail"))
    let sut = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true, windowText: true),
        asker: asker, turnContext: context
    )
    try sut.startSession()
    try await sut.final("summarise this command send")
    #expect(asker.calls == ["ASKWIN[Mail|the whole email]\n\nRequest: summarise this"])
    #expect(try await sut.submitWithoutDictation() != nil)
    #expect(asker.calls.last == "ASKWIN[Mail|the whole email]\n\nRequest: (no spoken request: respond to the text of the window)")
}

@Test func windowTextIsNotSentWhileTheOperatorIsOff() async throws {
    let refiner = EchoRefiner()
    let context = UntypeTurnContext(windowText: WindowText(text: "the whole email", appName: "Mail"))
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        refiner: refiner, turnContext: context
    )
    try sut.startSession()
    try await sut.final("my reply command send")
    #expect(refiner.calls == ["my reply"])
}

@Test func missingWindowTextSkipsTheLLMWithAWarning() async throws {
    let output = MemoryOutput()
    let refiner = EchoRefiner()
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, windowText: true),
        output: output, refiner: refiner, turnContext: UntypeTurnContext()
    )
    try sut.startSession()
    try await sut.final("my reply command send")
    #expect(refiner.calls.isEmpty)
    #expect(output.text.contains("Window text operator is enabled, but the text of the app's window was not captured"))
}

@Test func windowTextOperatorIsPersistedAndConfigurable() throws {
    let state = OperatorState(refine: true, translate: false, clipboard: false, input: true, windowText: true)
    let decoded = try JSONDecoder().decode(OperatorState.self, from: JSONEncoder().encode(state))
    #expect(decoded.windowText)
    let legacy = #"{"refine":true,"translate":false,"clipboard":false,"input":true}"#
    #expect(try !JSONDecoder().decode(OperatorState.self, from: Data(legacy.utf8)).windowText)
    #expect(OperatorKey(rawValue: "windowtext") == .windowText)
    #expect(UntypeUISettings.operatorPatch(.windowText, true).windowText == true)
}
