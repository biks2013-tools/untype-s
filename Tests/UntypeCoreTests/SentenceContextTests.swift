import Foundation
import Testing
@testable import UntypeCore

private func span(_ marked: String) -> SentenceSpan? {
    let parts = marked.components(separatedBy: "|")
    precondition(parts.count == 2)
    return SentenceSpan.around(caret: parts[0].utf16.count, in: parts[0] + parts[1])
}

@Test func sentenceSpanTakesBothPartsOfTheSentenceAroundTheCaret() {
    let found = span("First one. I want |to go home. Last one.")
    #expect(found == SentenceSpan(location: 11, before: "I want ", after: "to go home."))
}

@Test func sentenceSpanStopsAtLineBreaks() {
    let found = span("Title\nthe quick |brown fox\nnext line")
    #expect(found == SentenceSpan(location: 6, before: "the quick ", after: "brown fox"))
}

@Test func sentenceSpanAtTheEndOfAnUnfinishedSentenceHasOnlyTheBeginning() {
    #expect(span("Done. My name is |") == SentenceSpan(location: 6, before: "My name is ", after: ""))
}

@Test func sentenceSpanIsNilOutsideASentence() {
    #expect(span("|") == nil)
    #expect(span("Finished sentence.|") == nil)
    #expect(span("Finished sentence. |") == nil)
    #expect(span("Finished sentence.\n|") == nil)
}

@Test func sentenceSpanKeepsDecimalsAndGreekPunctuation() {
    #expect(span("Κάτι άλλο; Η τιμή είναι 3.5 |ευρώ· ναι.") == SentenceSpan(location: 11, before: "Η τιμή είναι 3.5 ", after: "ευρώ· ναι."))
}

@Test func sentenceSpanIncludesClosingQuotesAndIgnoresTooLongText() {
    #expect(span("He said \"go |now.\" Then left.")?.after == "now.\"")
    let long = String(repeating: "word ", count: 400)
    #expect(span(long + "|") == nil)
}

@Test func sentenceComposePutsTheDictationAtTheCaretWithSpaces() {
    let sentence = SentenceSpan(location: 0, before: "I want", after: "to go home.")
    #expect(sentence.compose(dictation: " Really. ") == "I want Really to go home.")
    let ending = SentenceSpan(location: 0, before: "My name is ", after: "")
    #expect(ending.compose(dictation: "George.") == "My name is George.")
    let beforeComma = SentenceSpan(location: 0, before: "Hello ", after: ", how are you?")
    #expect(beforeComma.compose(dictation: "George") == "Hello George, how are you?")
}

@Test func sentenceDictationOnlyNeedsBothPartsUnchanged() {
    let sentence = SentenceSpan(location: 0, before: "I want ", after: "to go home.")
    #expect(sentence.dictationOnly(from: "I want really to go home.") == "really")
    #expect(sentence.dictationOnly(from: "I really want to go home.") == nil)
    #expect(sentence.dictationOnly(from: "I want to go home.") == nil)
}

private final class EchoRefiner: TextRefining, @unchecked Sendable {
    var calls: [String] = []
    func refine(_ text: String) async throws -> String {
        calls.append(text)
        return "refined: \(text)"
    }
}

private func controller(
    operators: OperatorState,
    refiner: TextRefining?,
    asker: TextRefining? = nil,
    turnContext: UntypeTurnContext,
    delivered: @escaping @Sendable (String) -> Void = { _ in }
) -> VoiceAgentProtocolController {
    VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
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
        turnContext: turnContext,
        inputWriter: { text in delivered(text) }
    )
}

@Test func refineProcessesTheWholeSentenceAroundTheCaret() async throws {
    let refiner = EchoRefiner()
    let context = UntypeTurnContext()
    context.setSentence(SentenceSpan(location: 4, before: "I want ", after: "to go home."))
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        refiner: refiner, turnContext: context
    )
    try sut.startSession()
    try await sut.final("really command send")
    #expect(refiner.calls == ["I want really to go home."])
    #expect(context.takeSentenceDelivery() == "really")
    #expect(context.takeSentenceDelivery() == nil)
    // The sentence is used once: later speech is processed alone.
    try await sut.final("more words command send")
    #expect(refiner.calls.last == "more words")
    #expect(context.takeSentenceDelivery() == nil)
}

@Test func sentenceIsLeftAloneWithoutRefineAndWithAsk() async throws {
    let refiner = EchoRefiner()
    let context = UntypeTurnContext()
    context.setSentence(SentenceSpan(location: 0, before: "I want ", after: "to go."))
    let plain = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        refiner: refiner, turnContext: context
    )
    try plain.startSession()
    try await plain.final("really command send")
    #expect(refiner.calls.isEmpty)
    #expect(context.takeSentenceDelivery() == nil)

    let asker = EchoRefiner()
    let asking = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, ask: true),
        refiner: refiner, asker: asker, turnContext: context
    )
    try asking.startSession()
    try await asking.final("what is this command send")
    #expect(refiner.calls.isEmpty)
    #expect(asker.calls.count == 1)
    #expect(asker.calls.first?.contains("I want") == false)
    #expect(context.takeSentenceDelivery() == nil)
}

@Test func aNewTurnForgetsTheSentence() {
    let context = UntypeTurnContext()
    context.setSentence(SentenceSpan(location: 0, before: "a ", after: "b"))
    context.begin(selectionRole: .material)
    #expect(context.takeSentence(dictation: "x") == nil)
}
