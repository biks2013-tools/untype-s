import Foundation
import Testing
@testable import UntypeCore

private func token(_ text: String, _ speaker: String?, _ start: Int?, final: Bool = true) -> MeetingToken {
    MeetingToken(text: text, isFinal: final, speaker: speaker, startMs: start, endMs: start.map { $0 + 200 })
}

@Test func meetingOnlyMyVoiceIsOffByDefaultAndStored() throws {
    #expect(!MeetingPreferences().keepsOnlyMyVoice)
    let old = try JSONDecoder().decode(MeetingPreferences.self, from: Data(#"{"language":"en","silenceMinutes":3}"#.utf8))
    #expect(old.onlyMyVoice == nil && !old.keepsOnlyMyVoice)
    var meeting = MeetingPreferences()
    meeting.onlyMyVoice = true
    let stored = try JSONDecoder().decode(MeetingPreferences.self, from: try JSONEncoder().encode(meeting))
    #expect(stored.keepsOnlyMyVoice)
}

@Test func theMicrophoneTranscriptKeepsTheSpeakerOfTheVoiceSample() {
    var filter = MeetingUserVoiceFilter(leadMs: 4_200)
    // The sample is recognised and finished: nothing reaches the transcript.
    let sample = filter.filter([token(" my", "2", 100), token(" voice", "2", 600), token(".", "2", nil), token("<fin>", nil, nil)])
    #expect(sample.map(\.text) == ["<fin>"])
    #expect(filter.userSpeaker == "2")

    // The call from the loudspeakers (speaker 1), then the user (speaker 2).
    let kept = filter.filter([
        token(" Hello", "1", 5_000), token(" everyone", "1", 5_300), token(".", "1", nil),
        token(" Yes", "2", 6_200), token(" agreed", "2", 6_500), token(".", "2", nil), token("<end>", nil, nil)
    ])
    #expect(kept.map(\.text) == [" Yes", " agreed", ".", "<end>"])
    // Times count from the microphone's start, not from the sample's.
    #expect(kept[0].startMs == 2_000 && kept[0].endMs == 2_200)
    #expect(filter.keptWords == 2 && filter.droppedWords == 2)
}

@Test func theSampleInProgressAlreadyNamesTheUserOfTheMeeting() {
    var filter = MeetingUserVoiceFilter(leadMs: 4_200)
    let kept = filter.filter([token(" my", "1", 100, final: false), token(" hi", "1", 4_500, final: false), token(" echo", "2", 4_900, final: false)])
    #expect(kept.map(\.text) == [" hi"])
    #expect(filter.keptWords == 0 && filter.droppedWords == 0)
}

@Test func nothingIsDroppedFromTheMeetingWhileTheSampleIsNotRecognised() {
    var filter = MeetingUserVoiceFilter(leadMs: 4_200)
    let kept = filter.filter([token(" one", "1", 4_500), token(" two", "2", 4_900), token(" three", nil, 5_300)])
    #expect(kept.count == 3)
    #expect(filter.userSpeaker == nil)
}

@Test func theVoiceSampleIsSentWithAShortSilenceAfterIt() {
    let sample = VoiceSample(pcm: Data(count: 32_000), sampleRate: 16_000)
    #expect(sample.leadMs == 1_200)
    #expect(sample.lead.count == 32_000 + 6_400)
}
