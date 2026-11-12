import Foundation
import Testing
@testable import UntypeCore

private func segment(_ side: MeetingSide, _ text: String, at ms: Int, speaker: String? = nil) -> MeetingSegment {
    MeetingSegment(startMs: ms, endMs: ms + 1_000, side: side, speaker: speaker, language: "en", text: text)
}

@Test func transcriptionChannelsChooseTheSides() {
    #expect(TranscriptionChannel.both.includes(.you) && TranscriptionChannel.both.includes(.call))
    #expect(TranscriptionChannel.microphone.includes(.you) && !TranscriptionChannel.microphone.includes(.call))
    #expect(TranscriptionChannel.system.includes(.call) && !TranscriptionChannel.system.includes(.you))
}

@MainActor
@Test func transcriptFeedAddsLinesAtTheEndAndFiltersBySide() {
    let feed = MeetingTranscriptFeed()
    #expect(!feed.isRecording && feed.lines.isEmpty)
    feed.begin(meetingName: "")
    feed.setMeetingName("recording-2026-11-12-21-44")
    #expect(feed.isRecording)
    feed.add(segment(.you, "hello", at: 1_000))
    feed.add(segment(.call, "hi there", at: 2_000, speaker: "1"))
    feed.add(segment(.you, "how are you", at: 3_000))
    // Lines keep their place and identity: new ones only go at the end.
    #expect(feed.lines.map(\.id) == [0, 1, 2])
    #expect(feed.lines(for: .both).map(\.segment.text) == ["hello", "hi there", "how are you"])
    #expect(feed.lines(for: .microphone).map(\.segment.text) == ["hello", "how are you"])
    #expect(feed.lines(for: .system).map(\.segment.text) == ["hi there"])
    #expect(feed.lines(for: .microphone).map(\.id) == [0, 2])

    // The transcript stays after the recording ends, until the next one.
    feed.end()
    #expect(!feed.isRecording && feed.lines.count == 3)
    #expect(feed.meetingName == "recording-2026-11-12-21-44")
    feed.begin(meetingName: "next")
    #expect(feed.lines.isEmpty)
}

@MainActor
@Test func transcriptFeedShowsTheWordsBeingSpokenPerSide() {
    let feed = MeetingTranscriptFeed()
    feed.begin(meetingName: "m")
    feed.setInProgress("  so the ", side: .you)
    feed.setInProgress("yes", side: .call)
    #expect(feed.inProgress[.you] == "so the")
    #expect(feed.inProgressSides(for: .both) == [.you, .call])
    #expect(feed.inProgressSides(for: .system) == [.call])
    // The finished sentence replaces its words in progress; the other side's stay.
    feed.add(segment(.you, "so the plan is ready", at: 1_000))
    #expect(feed.inProgress[.you] == nil)
    #expect(feed.inProgress[.call] == "yes")
    feed.setInProgress("", side: .call)
    #expect(feed.inProgressSides(for: .both).isEmpty)
    feed.setInProgress("left over", side: .call)
    feed.end()
    #expect(feed.inProgress.isEmpty)
}

@Test func aggregatorGivesTheWordsOfTheSentenceBeingSpoken() {
    var aggregator = MeetingTokenAggregator(side: .you)
    _ = aggregator.add([MeetingToken(text: "Budget", isFinal: true), MeetingToken(text: " revue", isFinal: false)])
    #expect(aggregator.inProgressText(with: [MeetingToken(text: " revue", isFinal: false)]) == "Budget revue")
    let frame = [MeetingToken(text: " review", isFinal: true), MeetingToken(text: " with", isFinal: false)]
    _ = aggregator.add(frame)
    #expect(aggregator.inProgressText(with: frame) == "Budget review with")
    // After the end of the sentence nothing is in progress.
    let end = [MeetingToken(text: "<end>", isFinal: true)]
    #expect(aggregator.add(end).count == 1)
    #expect(aggregator.inProgressText(with: end) == "")
}

@MainActor
@Test func transcriptFeedGivesTheTextOfTheChosenSideForCopying() {
    let feed = MeetingTranscriptFeed()
    #expect(feed.text(for: .both).isEmpty)
    feed.begin(meetingName: "m")
    feed.add(segment(.you, "hello", at: 1_000))
    feed.add(segment(.call, "hi there", at: 62_000, speaker: "2"))
    feed.add(segment(.you, "how are you", at: 3_723_000))
    // Words still being spoken are not copied.
    feed.setInProgress("and then", side: .call)
    #expect(feed.text(for: .both) == "[00:00:01] You: hello\n[00:01:02] Speaker 2: hi there\n[01:02:03] You: how are you")
    #expect(feed.text(for: .microphone) == "[00:00:01] You: hello\n[01:02:03] You: how are you")
    #expect(feed.text(for: .system) == "[00:01:02] Speaker 2: hi there")
}

@MainActor
@Test func clearingEmptiesTheWindowButNotTheRecording() {
    let feed = MeetingTranscriptFeed()
    feed.begin(meetingName: "m")
    feed.add(segment(.you, "one", at: 1_000))
    feed.add(segment(.call, "two", at: 2_000, speaker: "1"))
    feed.setInProgress("thr", side: .you)
    feed.clear()
    // Nothing shown or copied; the words being spoken stay, the recording goes on.
    #expect(feed.lines(for: .both).isEmpty)
    #expect(feed.text(for: .both).isEmpty)
    #expect(feed.isRecording)
    #expect(feed.inProgress[.you] == "thr")
    // New text appears after the clear, with the ids it would have had.
    feed.add(segment(.you, "three", at: 3_000))
    feed.add(segment(.call, "four", at: 4_000, speaker: "1"))
    #expect(feed.lines(for: .both).map(\.segment.text) == ["three", "four"])
    #expect(feed.lines(for: .both).map(\.id) == [2, 3])
    #expect(feed.lines(for: .system).map(\.segment.text) == ["four"])
    #expect(feed.text(for: .microphone) == "[00:00:03] You: three")
    // A new recording starts with an empty, uncleared window.
    feed.end()
    feed.begin(meetingName: "next")
    #expect(feed.clearedBefore == 0 && feed.lines.isEmpty)
    feed.add(segment(.you, "new", at: 1_000))
    #expect(feed.lines(for: .both).count == 1)
}
