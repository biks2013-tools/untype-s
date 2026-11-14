import Foundation
import Testing
@testable import UntypeCore

@Test func microphoneGatePassesAudioUntilMuted() {
    let gate = MeetingMicrophoneGate()
    let pcm = Data([1, 2, 3, 4, 5, 6])
    #expect(!gate.isMuted)
    #expect(gate.filter(pcm) == pcm)
}

@Test func mutedMicrophoneGateGivesSilenceOfTheSameLength() {
    let gate = MeetingMicrophoneGate()
    let pcm = Data([1, 2, 3, 4, 5, 6])
    gate.isMuted = true
    #expect(gate.filter(pcm) == Data(count: 6))
    gate.isMuted = false
    #expect(gate.filter(pcm) == pcm)
}

@Test func dictationIsKeptOutOfTheMeetingByDefault() throws {
    #expect(MeetingPreferences().mutesMicrophoneWhileDictating)
    // A settings file written before the switch existed.
    let old = try JSONDecoder().decode(MeetingPreferences.self, from: Data(#"{"language":"en","silenceMinutes":3}"#.utf8))
    #expect(old.muteWhileDictating == nil)
    #expect(old.mutesMicrophoneWhileDictating)
}

@Test func muteWhileDictatingSwitchIsStored() throws {
    var meeting = MeetingPreferences()
    meeting.muteWhileDictating = false
    let stored = try JSONDecoder().decode(MeetingPreferences.self, from: try JSONEncoder().encode(meeting))
    #expect(stored.muteWhileDictating == false)
    #expect(!stored.mutesMicrophoneWhileDictating)
}

@MainActor
@Test func meetingRecorderMutesItsMicrophoneOnRequest() {
    let recorder = MeetingRecorder()
    recorder.setMicrophoneMuted(true)
    #expect(recorder.microphoneGate.isMuted)
    recorder.setMicrophoneMuted(false)
    #expect(!recorder.microphoneGate.isMuted)
}
