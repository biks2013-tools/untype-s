import Foundation
import Testing
@testable import UntypeCore

private func token(_ text: String, final: Bool = true, speaker: String? = nil, language: String? = "en", start: Int? = nil, end: Int? = nil) -> MeetingToken {
    MeetingToken(text: text, isFinal: final, speaker: speaker, language: language, startMs: start, endMs: end)
}

@Test func aggregatorEndsSegmentsAtMarkersAndIgnoresNonFinalTokens() {
    var aggregator = MeetingTokenAggregator(side: .you, offsetMs: 1_000)
    #expect(aggregator.add([token("Hel", start: 0, end: 200), token("lo", start: 200, end: 400), token(" there", final: false)]).isEmpty)
    let done = aggregator.add([token(" world", start: 400, end: 700), token("<end>")])
    #expect(done == [MeetingSegment(startMs: 1_000, endMs: 1_700, side: .you, speaker: nil, language: "en", text: "Hello world")])
    #expect(aggregator.flush() == nil)
}

@Test func aggregatorSplitsTheCallSideWhenTheSpeakerChanges() {
    var aggregator = MeetingTokenAggregator(side: .call)
    let done = aggregator.add([
        token("Yes,", speaker: "1", start: 0, end: 300),
        token(" agreed.", speaker: "1", start: 300, end: 600),
        token("Συμφωνώ", speaker: "2", language: "el", start: 700, end: 1_100)
    ])
    #expect(done.count == 1)
    #expect(done[0].speaker == "1")
    #expect(done[0].text == "Yes, agreed.")
    let last = aggregator.flush()
    #expect(last?.speaker == "2")
    #expect(last?.language == "el")
    #expect(last?.text == "Συμφωνώ")
}

@Test func tokensAreParsedFromSonioxFrames() {
    let parsed = MeetingToken.parse([
        ["text": "Γεια", "is_final": true, "speaker": "2", "language": "el", "start_ms": 120, "end_ms": 480],
        ["text": "<end>", "is_final": true],
        ["is_final": true]
    ])
    #expect(parsed.count == 2)
    #expect(parsed[0] == MeetingToken(text: "Γεια", isFinal: true, speaker: "2", language: "el", startMs: 120, endMs: 480))
    #expect(parsed[1].isMarker)
}

@Test func transcriptLinesNameTheSpeakersAndKeepTheLanguageInTheOriginal() {
    let call = MeetingSegment(startMs: 735_400, endMs: 737_000, side: .call, speaker: "spk:3", language: "el", text: "Συμφωνώ.", english: "I agree.")
    let you = MeetingSegment(startMs: 5_000, endMs: 6_000, side: .you, speaker: nil, language: "en", text: "Good morning.")
    #expect(MeetingTranscriptFormat.originalLine(call) == "[00:12:15] Speaker 3 [el]: Συμφωνώ.")
    #expect(MeetingTranscriptFormat.englishLine(call) == "[00:12:15] Speaker 3: I agree.")
    #expect(MeetingTranscriptFormat.englishLine(you) == "[00:00:05] You: Good morning.")
    #expect(MeetingTranscriptFormat.ordered([call, you]) == [you, call])
}

@Test func meetingFolderNamesFollowTheStartTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Athens"))
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 14, minute: 30)))
    #expect(MeetingTranscriptFormat.folderName(for: date, calendar: calendar) == "2026-11-11 14.30")
}

@Test func silenceMonitorStopsOnlyAfterTheLimitWithoutSpeech() {
    var monitor = MeetingSilenceMonitor(limit: 180, start: 100)
    #expect(!monitor.shouldStop(at: 279))
    monitor.speechHeard(at: 250)
    #expect(!monitor.shouldStop(at: 400))
    #expect(monitor.shouldStop(at: 430))
    #expect(!MeetingSilenceMonitor(limit: 0, start: 0).shouldStop(at: 10_000))
}

@Test func translationChunksRespectLimitsAndAnswersAreMatchedLineByLine() {
    let lines = (1...7).map { "line \($0)" }
    #expect(MeetingTranslationChunks.chunks(lines, maxCharacters: 1_000, maxLines: 3).map(\.count) == [3, 3, 1])
    #expect(MeetingTranslationChunks.chunks(["aaaa", "bbbb", "cccc"], maxCharacters: 8, maxLines: 10).map(\.count) == [2, 1])

    #expect(MeetingTranslationChunks.request(["Γεια", "Τι\nκάνεις"]) == "1|Γεια\n2|Τι κάνεις")
    #expect(MeetingTranslationChunks.parse("2|How are you\n1| Hello ", count: 2) == ["Hello", "How are you"])
    #expect(MeetingTranslationChunks.parse("1|Hello", count: 2) == nil)
}

@Test func meetingPreferencesDefaultToEnglishAndThreeMinutesAndRoundTrip() throws {
    let defaults = UntypeUISettings.default.meeting
    #expect(try defaults.transcriptLanguage == .english)
    #expect(defaults.silenceMinutes == 3)
    #expect(defaults.folderURL.lastPathComponent == "untype Meetings")

    let home = FileManager.default.temporaryDirectory.appendingPathComponent("untype-meeting-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let changed = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        meeting: MeetingPreferences(language: "original", silenceMinutes: 5, folder: "~/Calls")
    ))
    try UntypeUISettingsStore.save(changed, home: home)
    let loaded = try UntypeUISettingsStore.load(home: home).meeting
    #expect(try loaded.transcriptLanguage == .original)
    #expect(loaded.silenceMinutes == 5)
    #expect(loaded.folderURL.path.hasSuffix("/Calls"))

    // A state file written before the setting existed loads the defaults.
    let path = UntypeUISettingsStore.path(home: home)
    var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    var settings = try #require(root["settings"] as? [String: Any])
    settings.removeValue(forKey: "meeting")
    root["settings"] = settings
    try JSONSerialization.data(withJSONObject: root).write(to: path)
    #expect(try UntypeUISettingsStore.load(home: home).meeting == MeetingPreferences())

    #expect(throws: (any Error).self) { try MeetingPreferences(language: "fr").transcriptLanguage }
}

@Test func meetingNamesKeepTheDateAndAreSafeFileNames() {
    #expect(MeetingNaming.datePrefix(of: "2026-11-11 14.30 (2)") == "2026-11-11 14.30")
    #expect(MeetingNaming.datePrefix(of: "Notes") == nil)
    #expect(MeetingNaming.sanitize(" \"Budget: Q1/Q2 review\". ") == "Budget Q1 Q2 review")
    #expect(MeetingNaming.folderName(current: "2026-11-11 14.30", title: "Budget review with Maria") == "2026-11-11 14.30 – Budget review with Maria")
    #expect(MeetingNaming.folderName(current: "2026-11-11 14.30 – Old title", title: "New title") == "2026-11-11 14.30 – New title")
    #expect(MeetingNaming.folderName(current: "2026-11-11 14.30", title: "  ") == "2026-11-11 14.30")
}

@Test func renamingMovesTheFolderAndItsMainTranscript() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("untype-naming-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("2026-11-11 14.30")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "english".write(to: folder.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
    try "original".write(to: folder.appendingPathComponent("transcript.original.txt"), atomically: true, encoding: .utf8)

    let named = try MeetingNaming.rename(folder: folder, title: "Budget review with Maria")
    #expect(named.lastPathComponent == "2026-11-11 14.30 – Budget review with Maria")
    #expect(MeetingNaming.mainTranscript(in: named).lastPathComponent == "2026-11-11 14.30 – Budget review with Maria.txt")
    #expect(try String(contentsOf: MeetingNaming.mainTranscript(in: named), encoding: .utf8) == "english")
    #expect(FileManager.default.fileExists(atPath: named.appendingPathComponent("transcript.original.txt").path))

    let renamed = try MeetingNaming.rename(folder: named, title: "Q1 numbers with Nikos")
    #expect(renamed.lastPathComponent == "2026-11-11 14.30 – Q1 numbers with Nikos")
    #expect(try String(contentsOf: MeetingNaming.mainTranscript(in: renamed), encoding: .utf8) == "english")
}

@Test func titlesKeepTheTopicAndPeopleSeparator() {
    #expect(MeetingNaming.sanitize("HR training skills · Mina") == "HR training skills · Mina")
    #expect(MeetingNaming.folderName(current: "2026-11-11 22.59", title: "HR training skills · Mina") == "2026-11-11 22.59 – HR training skills · Mina")
}

@Test func liveTextKeepsFinalWordsAndReplacesPendingOnes() {
    var live = MeetingLiveText()
    #expect(live.add([MeetingToken(text: "Budget", isFinal: false)]) == "Budget")
    #expect(live.add([MeetingToken(text: "Budget", isFinal: true), MeetingToken(text: " revue", isFinal: false)]) == "Budget revue")
    #expect(live.add([MeetingToken(text: " review", isFinal: true), MeetingToken(text: "<end>", isFinal: true), MeetingToken(text: "  with Maria", isFinal: false)]) == "Budget review with Maria")
    #expect(live.add([]) == "Budget review")
    #expect(live.text == "Budget review")
}

@Test func friendlyDateReadsTheFolderDateAsPeopleSayIt() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Athens"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 23, minute: 30)))
    #expect(MeetingNaming.friendlyDate(of: "2026-11-11 22.38", now: now, calendar: calendar) == "Today 22:38")
    #expect(MeetingNaming.friendlyDate(of: "2026-11-10 09.05 – Budget", now: now, calendar: calendar) == "Yesterday 09:05")
    #expect(MeetingNaming.friendlyDate(of: "2026-10-02 14.00", now: now, calendar: calendar) == "2 Oct 14:00")
    #expect(MeetingNaming.friendlyDate(of: "Budget review", now: now, calendar: calendar) == nil)
}
