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

@Test func uiTimelineClearPartialPreservesReleaseTranscriptAndHistory() {
    var timeline = UntypeUITimelineState()

    timeline.commitFinal("This is what I said.", status: "committed", time: "10:00:00")
    timeline.commitProcessed("This is the refined output.", status: "refined", time: "10:00:01")
    timeline.updatePartial("stale warm-session partial")

    timeline.clearPartial()

    #expect(timeline.partial == nil)
    #expect(timeline.turns.count == 1)
    #expect(timeline.turns[0].bubbles.map(\.kind) == [.raw, .processed])
    #expect(timeline.turns[0].bubbles[0].text == "This is what I said.")
    #expect(timeline.turns[0].bubbles[1].text == "This is the refined output.")
    #expect(timeline.visibleItemCount == 2)

    let history = timeline.conversationHistory
    #expect(history.count == 1)
    #expect(history[0].userText == "This is what I said.")
    #expect(history[0].records.count == 1)
    #expect(history[0].records[0].text == "This is the refined output.")
}

@Test func uiTimelineExportsCommittedTurnsAndLivePartialInReadingOrder() {
    var timeline = UntypeUITimelineState()

    timeline.commitFinal("Open the design docs.", status: "en", time: "10:00:00")
    timeline.commitProcessed("Open the design documentation.", status: "refined", time: "10:00:01")
    timeline.sealCurrentTurn()
    timeline.updatePartial("starting next request")

    #expect(timeline.exportPlainText() == """
    Turn 1 | 10:00:00 | closed
    [Dictated text | en]
    Open the design docs.
    [Processed output | refined]
    Open the design documentation.

    Live partial | Live
    [Partial transcript | streaming]
    starting next request
    """)
}

@Test func uiTimelineBuildsConversationHistoryFromRawProcessedErrorsAndPartial() {
    var timeline = UntypeUITimelineState()

    timeline.commitFinal("Open the design docs.", status: "en", time: "10:00:00")
    timeline.commitProcessed("Open the design documentation.", status: "refined + translated", time: "10:00:01")
    timeline.commitError("[untype] Clipboard delivery failed.", status: "warning", time: "10:00:02")
    timeline.sealCurrentTurn()
    timeline.updatePartial("next request")

    let history = timeline.conversationHistory

    #expect(history.count == 2)
    #expect(history[0].title == "Conversation 1")
    #expect(history[0].time == "10:00:00")
    #expect(history[0].status == "closed")
    #expect(history[0].userText == "Open the design docs.")
    #expect(history[0].records.count == 2)
    #expect(history[0].records[0].kind == .output)
    #expect(history[0].records[0].label == "Refine / Translate record")
    #expect(history[0].records[0].status == "refined + translated")
    #expect(history[0].records[0].text == "Open the design documentation.")
    #expect(history[0].records[1].kind == .issue)
    #expect(history[0].records[1].label == "Session record")
    #expect(history[1].title == "Live conversation")
    #expect(history[1].userText == "next request")
    #expect(timeline.conversationHistoryItemCount == 4)
}

@Test func uiTimelineExportOmitsEmptyTimelineContent() {
    let timeline = UntypeUITimelineState()

    #expect(timeline.exportPlainText() == "")
    #expect(UntypeUIExportDocument.transcript(from: timeline) == nil)
    #expect(timeline.conversationHistory.isEmpty)
    #expect(timeline.conversationHistoryItemCount == 0)
}
