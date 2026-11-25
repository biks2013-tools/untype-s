import Foundation
import Testing
@testable import UntypeCore

private func token(_ text: String, _ speaker: String?, _ start: Int?, final: Bool = true) -> MeetingToken {
    MeetingToken(text: text, isFinal: final, speaker: speaker, startMs: start, endMs: start.map { $0 + 200 })
}

@Test func theMicrophoneIsOneSpeakerUnlessRoomSpeakersIsOn() {
    let tokens = [token(" Hello", "1", 0), token(".", "1", nil), token(" Hi", "2", 900), token(".", "2", nil), token("<end>", nil, nil)]

    var single = MeetingTokenAggregator(side: .you)
    let one = single.add(tokens)
    #expect(one.map(\.text) == ["Hello. Hi."])
    #expect(one.map(\.speaker) == [nil])
    #expect(one.map(MeetingTranscriptFormat.speakerLabel) == ["You"])

    var room = MeetingTokenAggregator(side: .you, roomSpeakers: true)
    let two = room.add(tokens)
    #expect(two.map(\.text) == ["Hello.", "Hi."])
    #expect(two.map(\.speaker) == ["1", "2"])
    #expect(two.map(MeetingTranscriptFormat.speakerLabel) == ["Person 1", "Person 2"])
}

@Test func withAVoiceSampleTheUserIsYouAndTheOthersAreNumberedFromTwo() {
    var filter = MeetingUserVoiceFilter(leadMs: 4_200, keepsOthers: true)
    // Soniox calls the user 3; the others are 1 and 5.
    _ = filter.filter([token(" my", "3", 100), token(" voice", "3", 600), token("<fin>", nil, nil)])
    #expect(filter.userSpeaker == "3")

    let heard = filter.filter([
        token(" Shall", "5", 5_000), token(" we", "5", 5_300), token("?", "5", nil),
        token(" Yes", "3", 6_200), token(".", "3", nil),
        token(" Fine", "1", 7_000), token(".", "1", nil),
        token(" Good", "5", 8_000), token(".", "5", nil), token("<end>", nil, nil)
    ])
    // Nobody is dropped.
    #expect(heard.count == 10)
    #expect(filter.droppedWords == 0 && filter.roomSpeakerCount == 2)

    var room = MeetingTokenAggregator(side: .you, roomSpeakers: true)
    let segments = room.add(heard)
    #expect(segments.map(\.text) == ["Shall we?", "Yes.", "Fine.", "Good."])
    #expect(segments.map(MeetingTranscriptFormat.speakerLabel) == ["Person 2", "You", "Person 3", "Person 2"])
    // Times count from the microphone's start.
    #expect(segments[0].startMs == 800)
    // The user stays speaker 1 of the microphone in the per-side files.
    let start = Date(timeIntervalSince1970: 0)
    #expect(segments.map { MeetingSidecarLine(segment: $0, meetingStart: start).speaker } == ["2", "1", "3", "2"])
}

@Test func theCallSideStillIgnoresTokensWithoutASpeaker() {
    var call = MeetingTokenAggregator(side: .call)
    let segments = call.add([token(" One", "1", 0), token(" two", nil, 300), token(" three", "1", 600), token("<end>", nil, nil)])
    #expect(segments.map(\.text) == ["One two three"])
    #expect(segments.map(MeetingTranscriptFormat.speakerLabel) == ["Speaker 1"])
}
