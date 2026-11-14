import Foundation
import Testing
@testable import UntypeCore

private func context(_ before: String, endsLine: Bool? = true) -> LiveCaretContext {
    LiveCaretContext(before: before, endsLine: endsLine)
}

@Test func theProvidersClosingFullStopIsDropped() {
    #expect(LiveUtteranceShaper.withoutClosingPeriod(" The plan is ready. ") == "The plan is ready")
    #expect(LiveUtteranceShaper.withoutClosingPeriod("Is it ready?") == "Is it ready?")
    #expect(LiveUtteranceShaper.withoutClosingPeriod("And then...") == "And then...")
    #expect(LiveUtteranceShaper.withoutClosingPeriod("Version 2.5 is out.") == "Version 2.5 is out")
}

@Test func aCapitalOnlyAfterAFullStopOrAtTheStartOfTheText() {
    #expect(LiveUtteranceShaper.shape("The plan is ready.", context: context("")) == "The plan is ready")
    #expect(LiveUtteranceShaper.shape("The plan is ready.", context: context("We met today. ")) == "The plan is ready")
    #expect(LiveUtteranceShaper.shape("the plan is ready.", context: context("We met today. ")) == "The plan is ready")
    #expect(LiveUtteranceShaper.shape("The plan is ready.", context: context("We met today and ")) == "the plan is ready")
    #expect(LiveUtteranceShaper.shape("Το σχέδιο είναι έτοιμο.", context: context("Συναντηθήκαμε και ")) == "το σχέδιο είναι έτοιμο")
    #expect(LiveUtteranceShaper.shape("Έτοιμο είναι.", context: context("Τι λες; ")) == "Έτοιμο είναι")
    // A semicolon is not the end of an English sentence.
    #expect(LiveUtteranceShaper.shape("The plan is ready.", context: context("We met; ")) == "the plan is ready")
    // A new line after an unfinished sentence does not start a sentence.
    #expect(LiveUtteranceShaper.shape("The plan.", context: context("We met and\n")) == "the plan")
    #expect(LiveUtteranceShaper.shape("The plan.", context: context("We met.\n")) == "The plan")
}

@Test func aSpaceOnlyWhenTheCaretStandsRightAfterText() {
    #expect(LiveUtteranceShaper.shape("The plan.", context: context("We met today.")) == " The plan")
    #expect(LiveUtteranceShaper.shape("The plan.", context: context("We met today")) == " the plan")
    #expect(LiveUtteranceShaper.shape("The plan.", context: context("We met today ")) == "the plan")
    #expect(LiveUtteranceShaper.shape("The plan.", context: context("We met today.\n")) == "The plan")
    #expect(LiveUtteranceShaper.shape("The plan.", context: context("")) == "The plan")
    #expect(LiveUtteranceShaper.shape("The plan.", context: context("see (")) == "the plan")
}

@Test func wordsThatCarryTheirOwnCapitalKeepIt() {
    #expect(LiveUtteranceShaper.shape("I think so.", context: context("and ")) == "I think so")
    #expect(LiveUtteranceShaper.shape("I'm sure.", context: context("and ")) == "I'm sure")
    #expect(LiveUtteranceShaper.shape("API keys are set.", context: context("the ")) == "API keys are set")
    #expect(LiveUtteranceShaper.shape("It works.", context: context("and ")) == "it works")
}

@Test func aFieldThatDoesNotTellKeepsTheWordsAsRecognised() {
    #expect(LiveUtteranceShaper.shape("The plan is ready.", context: nil) == "The plan is ready")
}

@Test func handsFreeFlowFollowsWhatTheUserTypedBetweenUtterances() {
    var flow = HandsFreeTextFlow()
    var field = ""
    func read() -> LiveCaretContext? { context(field) }

    flow.updatePartial("We tested", now: 0, context: read)
    #expect(flow.text == "We tested")
    flow.commitFinal("We tested the new version.", now: 1, context: read)
    #expect(flow.text == "We tested the new version")

    // No full stop was typed: the next words continue the sentence.
    field = "We tested the new version"
    flow.updatePartial("With three", now: 2, context: read)
    #expect(flow.text == "We tested the new version with three")
    flow.commitFinal("With three teams.", now: 3, context: read)
    #expect(flow.text == "We tested the new version with three teams")

    // The user typed a full stop: a space and a capital follow.
    field = "We tested the new version with three teams."
    flow.commitFinal("The results look good.", now: 4, context: read)
    #expect(flow.text == "We tested the new version with three teams The results look good")
    // (the full stop is the user's, in the field, not in what untype typed)
}

@Test func handsFreeFlowReadsTheFieldOncePerUtterance() {
    var flow = HandsFreeTextFlow()
    var reads = 0
    func read() -> LiveCaretContext? { reads += 1; return context("Done. ") }
    flow.updatePartial("the", now: 0, context: read)
    flow.updatePartial("the next", now: 0.2, context: read)
    flow.commitFinal("The next step.", now: 1, context: read)
    #expect(reads == 1)
    #expect(flow.text == "The next step")
    flow.updatePartial("", now: 1.5, context: read)
    #expect(reads == 1)
}

@Test func handsFreeFlowUsesItsOwnTextWhenTheFieldDoesNotTell() {
    var flow = HandsFreeTextFlow()
    flow.commitFinal("The plan is ready.", now: 1, context: { nil })
    flow.commitFinal("And it works.", now: 2, context: { nil })
    #expect(flow.text == "The plan is ready and it works")
}

@Test func aLongPauseClosesTheSentenceOnlyAtTheEndOfWhatWasDictated() {
    func flowAfterFirst() -> HandsFreeTextFlow {
        var flow = HandsFreeTextFlow(pausePeriodSeconds: 3)
        flow.commitFinal("The plan is ready.", now: 10, context: { context("") })
        return flow
    }
    // A long pause, the caret still after the dictated text: full stop.
    var flow = flowAfterFirst()
    flow.commitFinal("Next we test.", now: 14, context: { context("The plan is ready") })
    #expect(flow.text == "The plan is ready. Next we test")

    // A short pause: none.
    flow = flowAfterFirst()
    flow.commitFinal("Next we test.", now: 12, context: { context("The plan is ready") })
    #expect(flow.text == "The plan is ready next we test")

    // The caret was moved into other text: none.
    flow = flowAfterFirst()
    flow.commitFinal("Next we test.", now: 14, context: { context("Dear Maria", endsLine: false) })
    #expect(flow.text == "The plan is ready next we test")
    flow = flowAfterFirst()
    flow.commitFinal("Next we test.", now: 14, context: { context("some other text") })
    #expect(flow.text == "The plan is ready next we test")

    // The field does not tell where the caret is: none.
    flow = flowAfterFirst()
    flow.commitFinal("Next we test.", now: 14, context: { nil })
    #expect(flow.text == "The plan is ready next we test")

    // The switch is off: none.
    var plain = HandsFreeTextFlow()
    plain.commitFinal("The plan is ready.", now: 10, context: { context("") })
    plain.commitFinal("Next we test.", now: 20, context: { context("The plan is ready") })
    #expect(plain.text == "The plan is ready next we test")
}

@MainActor
@Test func untouchedDictationIsRecognisedWhateverTheSpacing() {
    #expect(LiveFocusedInputTyper.sameWords("The plan is ready. And it works.", " The plan is ready.  And it works.\n"))
    #expect(!LiveFocusedInputTyper.sameWords("The plan is ready.", "The plan is ready"))
}

@Test func handsFreePreferencesDefaultToOffAndSurviveOlderSettingsFiles() throws {
    #expect(!HandsFreePreferences().leavesPunctuationToUser)
    #expect(!HandsFreePreferences(periodAfterPause: true).addsPeriodAfterPause)
    #expect(HandsFreePreferences(userPunctuates: true, periodAfterPause: true).addsPeriodAfterPause)
    #expect(UntypeUISettings.default.handsFree == HandsFreePreferences())
    let merged = try UntypeUISettings.default.merged(UntypeUISettingsPatch(handsFree: HandsFreePreferences(userPunctuates: true)))
    #expect(merged.handsFree.leavesPunctuationToUser)
}

@Test func aFieldThatAnswersAsIfEmptyIsNotBelievedAfterUntypeWroteIntoIt() {
    var flow = HandsFreeTextFlow(pausePeriodSeconds: 3)
    // Some controls always report the caret at the start of an empty field.
    flow.commitFinal("We tested the new version.", now: 1, context: { context("") })
    flow.commitFinal("With three teams.", now: 2, context: { context("") })
    flow.commitFinal("And it works.", now: 9, context: { context("") })
    #expect(flow.text == "We tested the new version with three teams and it works")
}

@Test func aFullStopTypedByHandIsKnownFromItsKeyWhereTheFieldDoesNotTell() {
    var flow = HandsFreeTextFlow()
    flow.commitFinal("We tested the new version.", now: 1, context: { nil })
    flow.note(.text("."))
    flow.commitFinal("The results look good.", now: 2, context: { nil })
    // untype typed: the first phrase, then (after the user's full stop) a space and a capital.
    #expect(flow.text == "We tested the new version The results look good")

    // Full stop and a space typed by hand: no second space.
    flow.note(.text(". "))
    flow.commitFinal("Next we ship.", now: 3, context: { nil })
    #expect(flow.text.hasSuffix("goodNext we ship"))

    // A typed character that was erased again does not count.
    flow.note(.text("."))
    flow.note(.erase)
    flow.commitFinal("And then we rest.", now: 4, context: { nil })
    #expect(flow.text.hasSuffix("ship and then we rest"))
}

@Test func typedKeysAlsoCorrectAFieldThatAnswersAsIfEmpty() {
    var flow = HandsFreeTextFlow()
    // The user typed before speaking; the field claims to be empty.
    flow.note(.text("Note: "))
    flow.commitFinal("The plan is ready.", now: 1, context: { context("") })
    #expect(flow.text == "the plan is ready")
    flow.note(.text("."))
    flow.commitFinal("It works.", now: 2, context: { context("") })
    #expect(flow.text == "the plan is ready It works")
}

@Test func afterAClickOrAnArrowKeyTheTypedKeysAreNotTrusted() {
    var flow = HandsFreeTextFlow()
    flow.commitFinal("We tested the new version.", now: 1, context: { nil })
    flow.note(.text("."))
    flow.note(.move)
    flow.commitFinal("With three teams.", now: 2, context: { nil })
    #expect(flow.text == "We tested the new version with three teams")
    // The next phrase starts clean again.
    flow.note(.text("!"))
    flow.commitFinal("Great.", now: 3, context: { nil })
    #expect(flow.text.hasSuffix("teams Great"))
}

@Test func theTrailFollowsWhatTheUserErased() {
    var trail = UserTypingTrail()
    trail.note(.erase)
    trail.note(.erase)
    trail.note(.text("s."))
    #expect(trail.before(written: "three teams") == "three teas.")
    trail.note(.move)
    #expect(trail.before(written: "three teams") == nil)
}
