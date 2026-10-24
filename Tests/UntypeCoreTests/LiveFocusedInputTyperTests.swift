import CoreGraphics
import Foundation
import Testing
@testable import UntypeCore

@Test func liveInputEditAppendsWhenTargetExtendsTypedText() {
    let edit = LiveInputEdit.between(typed: "Hello", target: "Hello world")
    #expect(edit == LiveInputEdit(deleteCount: 0, insert: " world"))
}

@Test func liveInputEditDeletesOnlyTheChangedTail() {
    let edit = LiveInputEdit.between(typed: "Hello wort", target: "Hello word.")
    #expect(edit == LiveInputEdit(deleteCount: 1, insert: "d."))
}

@Test func liveInputEditReplacesEverythingWhenNothingIsShared() {
    let edit = LiveInputEdit.between(typed: "Καλημέρα", target: "Good morning")
    #expect(edit == LiveInputEdit(deleteCount: 8, insert: "Good morning"))
}

@Test func liveInputEditIsEmptyForIdenticalText() {
    #expect(LiveInputEdit.between(typed: "same", target: "same").isEmpty)
    #expect(LiveInputEdit.between(typed: "", target: "").isEmpty)
}

@Test func liveInputEditCountsGraphemeClustersNotCodeUnits() {
    let edit = LiveInputEdit.between(typed: "ok 👍🏽", target: "ok")
    #expect(edit == LiveInputEdit(deleteCount: 2, insert: ""))
}

@Test func liveTranscriptAccumulatesFinalsAndTracksTheCurrentPartial() {
    var transcript = LiveTranscriptText()
    transcript.updatePartial(" Hello")
    #expect(transcript.text == "Hello")
    transcript.commitFinal("Hello there.")
    #expect(transcript.text == "Hello there.")
    transcript.updatePartial(" How are")
    #expect(transcript.text == "Hello there. How are")
    transcript.updatePartial("How are you")
    #expect(transcript.text == "Hello there. How are you")
    transcript.commitFinal("How are you?")
    #expect(transcript.text == "Hello there. How are you?")
    #expect(transcript.partial.isEmpty)
}

@Test func liveKeyboardChunksNeverSplitACharacterOrExceedTheEventLimit() {
    let text = String(repeating: "ab👍🏽", count: 12)
    let chunks = LiveKeyboardPoster.unicodeChunks(text)
    #expect(chunks.allSatisfy { $0.count <= 20 })
    let rebuilt = chunks.map { String(utf16CodeUnits: $0, count: $0.count) }.joined()
    #expect(rebuilt == text)
    for chunk in chunks {
        #expect(String(utf16CodeUnits: chunk, count: chunk.count).unicodeScalars.allSatisfy { !(0xD800...0xDFFF).contains($0.value) })
    }
}

@Test func syntheticKeyboardEventsCarryTheUntypeMarker() throws {
    let source = try #require(CGEventSource(stateID: .privateState))
    let event = try #require(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true))
    #expect(!isUntypeSyntheticKeyboardEvent(event))
    event.setIntegerValueField(.eventSourceUserData, value: untypeSyntheticKeyboardEventMarker)
    #expect(isUntypeSyntheticKeyboardEvent(event))
}
