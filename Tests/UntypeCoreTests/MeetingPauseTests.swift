import Foundation
import Testing
@testable import UntypeCore

// plan-074: the user pauses and resumes one side of a meeting recording.

@Test func aPausedSideGivesSilenceOfTheSameLength() {
    let gate = MeetingMicrophoneGate()
    let pcm = Data([1, 2, 3, 4, 5, 6])
    #expect(gate.filter(pcm) == pcm)
    gate.isPaused = true
    #expect(gate.filter(pcm) == Data(count: 6))
    gate.isPaused = false
    #expect(gate.filter(pcm) == pcm)
}

@Test func pauseAndDictationMuteAreIndependent() {
    let gate = MeetingMicrophoneGate()
    let pcm = Data([9, 9])
    gate.isPaused = true
    gate.isMuted = true
    // The dictation turn ends: the side stays paused.
    gate.isMuted = false
    #expect(gate.filter(pcm) == Data(count: 2))
    #expect(gate.isPaused)
    gate.isPaused = false
    #expect(gate.filter(pcm) == pcm)
}

@MainActor
@Test func theWindowAsksForAPauseOnlyWhileRecordingAndShowsTheAnswer() {
    let feed = MeetingTranscriptFeed()
    var requests: [String] = []
    feed.onPauseRequest = { side, paused in
        requests.append("\(side.rawValue):\(paused)")
        feed.setPaused(paused, side: side)
    }
    feed.togglePause(.you)
    #expect(requests.isEmpty)

    feed.begin(meetingName: "meeting")
    feed.togglePause(.you)
    #expect(feed.paused == [.you])
    feed.togglePause(.call)
    #expect(feed.paused == [.you, .call])
    feed.togglePause(.you)
    #expect(feed.paused == [.call])
    #expect(requests == ["you:true", "call:true", "you:false"])

    // A pause ends with the recording and never carries over.
    feed.end()
    #expect(feed.paused.isEmpty)
    feed.setPaused(true, side: .call)
    feed.begin(meetingName: "next")
    #expect(feed.paused.isEmpty)
}

@MainActor
@Test func aSideCannotBePausedWhenNothingIsRecorded() {
    let recorder = MeetingRecorder()
    #expect(recorder.setPaused(true, side: .you) == false)
    #expect(!recorder.isPaused(.you))
    #expect(!recorder.isPaused(.call))
}
