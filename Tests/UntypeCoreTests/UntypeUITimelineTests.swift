import Testing
@testable import UntypeCore

@Test func uiTimelineGroupsFinalAndProcessedOutputByTurn() {
    var timeline = UntypeUITimelineState()

    timeline.updatePartial("open the")
    timeline.commitFinal("Open the design docs.", status: "en", time: "10:00:00")
    timeline.commitProcessed("Open the design documentation.", status: "refined", time: "10:00:01")

    #expect(timeline.partial == nil)
    #expect(timeline.turns.count == 1)
    #expect(timeline.turns[0].sealed == false)
    #expect(timeline.turns[0].bubbles.map(\.kind) == [.raw, .processed])
    #expect(timeline.turns[0].bubbles[0].label == "Dictated text")
    #expect(timeline.turns[0].bubbles[1].label == "Processed output")
}

@Test func uiTimelineAppendsFinalSegmentsAndSealsOnTurnBoundary() {
    var timeline = UntypeUITimelineState()

    timeline.commitFinal("Open the design docs.", status: "en", time: "10:00:00")
    timeline.commitFinal("Check provider status.", status: "en", time: "10:00:01")
    timeline.sealCurrentTurn()
    timeline.commitFinal("Start a new turn.", status: "en", time: "10:00:02")

    #expect(timeline.turns.count == 2)
    #expect(timeline.turns[0].sealed)
    #expect(timeline.turns[0].bubbles.count == 1)
    #expect(timeline.turns[0].bubbles[0].text == "Open the design docs. Check provider status.")
    #expect(timeline.turns[1].bubbles[0].text == "Start a new turn.")
}

@Test func uiTimelineClearRemovesVisibleTranscriptWithoutAcceptingDanglingProcessedOutput() {
    var timeline = UntypeUITimelineState()

    timeline.commitFinal("Keep this visible.", status: "en", time: "10:00:00")
    timeline.clear()
    timeline.commitProcessed("This should not reappear.", status: "refined", time: "10:00:01")

    #expect(timeline.turns.isEmpty)
    #expect(timeline.partial == nil)
    #expect(timeline.visibleItemCount == 0)
    #expect(timeline.clearedSinceRaw)
}
