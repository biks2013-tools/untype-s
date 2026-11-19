import Foundation
import Testing
@testable import UntypeCore

// plan-071: the user edits the text in the field while dictating; what
// stands in the field is processed, not what was spoken in spoken order.

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
    turnContext: UntypeTurnContext
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
        turnContext: turnContext
    )
}

private func processedOutput(_ output: MemoryOutput) throws -> String? {
    let events = try output.text.split(separator: "\n").map {
        try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] ?? [:]
    }
    return events.last { $0["type"] as? String == "section.processed" }?["output_text"] as? String
}

@Test func theTextEditedInTheFieldIsWhatGetsTranslated() async throws {
    let output = MemoryOutput()
    let translator = RecordingRefiner { _ in "translated" }
    let context = UntypeTurnContext()
    // Spoken: first sentence, an insertion made in the middle, last sentence.
    context.setFieldTextReader { "η αναφορά του Οκτωβρίου είναι έτοιμη. Τα αποτελέσματα είναι καλά." }
    let sut = controller(
        operators: OperatorState(refine: false, translate: true, clipboard: false, input: false),
        output: output, translator: translator, turnContext: context
    )
    try sut.startSession()
    try await sut.final("η αναφορά είναι έτοιμη. του Οκτωβρίου Τα αποτελέσματα είναι καλά. command send")
    #expect(translator.calls == ["To English: η αναφορά του Οκτωβρίου είναι έτοιμη. Τα αποτελέσματα είναι καλά."])
    #expect(try processedOutput(output) == "translated")
}

@Test func anUneditedTurnIsProcessedAsSpoken() async throws {
    let output = MemoryOutput()
    let translator = RecordingRefiner { _ in "translated" }
    let context = UntypeTurnContext()
    context.setFieldTextReader { nil }
    let sut = controller(
        operators: OperatorState(refine: false, translate: true, clipboard: false, input: false),
        output: output, translator: translator, turnContext: context
    )
    try sut.startSession()
    try await sut.final("γεια σου command send")
    #expect(translator.calls == ["To English: γεια σου"])
}

@Test func theFieldIsNotReadWhenNothingProcessesTheText() async throws {
    let output = MemoryOutput()
    let reads = Counter()
    let context = UntypeTurnContext()
    context.setFieldTextReader {
        reads.increment()
        return "edited"
    }
    let sut = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        output: output, turnContext: context
    )
    try sut.startSession()
    try await sut.final("as spoken command send")
    #expect(reads.value == 0)
    #expect(try processedOutput(output) == "as spoken")
}

@Test func anEditedTurnIsRefinedWithoutTheSentenceAroundTheCursor() async throws {
    let output = MemoryOutput()
    let refiner = RecordingRefiner { "clean: \($0)" }
    let context = UntypeTurnContext()
    context.setSentence(SentenceSpan(location: 0, before: "We met ", after: " yesterday."))
    context.setFieldTextReader { "the four teams" }
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        output: output, refiner: refiner, turnContext: context
    )
    try sut.startSession()
    try await sut.final("the three teams command send")
    #expect(refiner.calls == ["the four teams"])
    // The sentence was not taken, so the delivery does not replace it.
    #expect(context.takeSentenceDelivery() == nil)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

// MARK: Where the turn's text stands

@Test func theTurnsTextIsWhatStandsBetweenTheTextAroundTheCursorAtPress() {
    let value = "Dear Maria, the report for October is ready. Best, G."
    let range = TurnFieldRegion.inField(value, before: "Dear Maria, ", after: " Best, G.")
    #expect(range.map { (value as NSString).substring(with: $0) } == "the report for October is ready.")
    #expect(TurnFieldRegion.inField("", before: "", after: "") == NSRange(location: 0, length: 0))
}

@Test func aChangeOutsideTheTurnsTextIsNotFollowed() {
    #expect(TurnFieldRegion.inField("Dear Mary, hello Best", before: "Dear Maria, ", after: " Best") == nil)
    #expect(TurnFieldRegion.inField("short", before: "longer than the text", after: "") == nil)
}

@Test func inAPromptTheTurnsTextFollowsWhatWasThereAtPress() {
    let appended = TurnFieldRegion.inPrompt("fix the bug and add tests", atPress: "fix the bug")
    #expect(appended.kept == "fix the bug")
    #expect(appended.text == " and add tests")
    // An empty prompt, or one that showed a suggestion: the whole prompt.
    #expect(TurnFieldRegion.inPrompt("add tests", atPress: "").text == "add tests")
    let suggestion = TurnFieldRegion.inPrompt("add tests", atPress: "commit this")
    #expect(suggestion.kept == "")
    #expect(suggestion.text == "add tests")
    // Nothing of the turn is left.
    #expect(TurnFieldRegion.inPrompt("fix the bug", atPress: "fix the bug").text == "")
}

@Test func anEmptyPromptBoxIsNotTheSameAsNoPromptBox() {
    let rule = String(repeating: "─", count: 40)
    #expect(TerminalPromptParser.box(in: "⏺ Done.\n\(rule)\n❯ \n\(rule)\n  status") == "")
    #expect(TerminalPromptParser.box(in: "⏺ Done.\n\(rule)\n❯ add tests\n\(rule)\n  status") == "add tests")
    #expect(TerminalPromptParser.box(in: "$ ls\nfile.txt\n$ ") == nil)
    #expect(TerminalPromptParser.prompt(in: "⏺ Done.\n\(rule)\n❯ \n\(rule)\n  status") == nil)
}

// MARK: What the keys tell in a field that cannot be read

@Test func theTailFollowsUntypesKeysAndWhatTheUserTypesAtTheEnd() {
    var tail = TypedTailModel()
    tail.typed(LiveInputEdit(deleteCount: 0, insert: "three teams"))
    #expect(tail.text == "three teams")
    #expect(!tail.touched)
    tail.note(.erase)
    tail.note(.text("s."))
    #expect(tail.text == "three teams.")
    #expect(tail.touched)
    // untype revises its last words: Backspaces from the end.
    tail.typed(LiveInputEdit(deleteCount: 6, insert: "groups"))
    #expect(tail.text == "three groups")
}

@Test func afterTheCursorMovedTheTailIsNotKnown() {
    var tail = TypedTailModel()
    tail.typed(LiveInputEdit(deleteCount: 0, insert: "three teams"))
    tail.note(.move)
    #expect(tail.text == nil)
    tail.note(.text("x"))
    tail.typed(LiveInputEdit(deleteCount: 0, insert: " more"))
    #expect(tail.text == nil)
}

@Test func erasingPastTheStartOfTheTurnIsNotFollowed() {
    var tail = TypedTailModel()
    tail.typed(LiveInputEdit(deleteCount: 0, insert: "a"))
    tail.note(.erase)
    #expect(tail.text == "")
    tail.note(.erase)
    #expect(tail.text == nil)
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
