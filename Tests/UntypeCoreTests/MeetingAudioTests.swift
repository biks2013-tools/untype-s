import AVFoundation
import Foundation
import Testing
@testable import UntypeCore

private func tone(_ count: Int, amplitude: Int16 = 8_000) -> [Int16] {
    (0..<count).map { Int16(Double(amplitude) * sin(Double($0) * 2 * .pi * 440 / 16_000)) }
}

private func data(_ samples: [Int16]) -> Data {
    samples.withUnsafeBufferPointer { Data(buffer: $0) }
}

private func duration(of url: URL) throws -> Double {
    let file = try AVAudioFile(forReading: url)
    return Double(file.length) / file.fileFormat.sampleRate
}

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("untype-meeting-audio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func meetingFilesFollowTheNtakkerNames() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Athens"))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9, minute: 7)))
    let names = MeetingFileNames(start: start, calendar: calendar)
    #expect(names.stem == "recording-2026-11-05-09-07")
    #expect(names.microphoneAudio == "recording-2026-11-05-09-07.mic.m4a")
    #expect(names.systemAudio == "recording-2026-11-05-09-07.system.m4a")
    #expect(names.mixedAudio == "recording-2026-11-05-09-07.m4a")
    #expect(names.microphoneTranscript == "recording-2026-11-05-09-07.microphone.transcript.jsonl")
    #expect(names.systemTranscript == "recording-2026-11-05-09-07.system.transcript.jsonl")
    #expect(names.mainTranscript == "recording-2026-11-05-09-07.transcript.txt")
    #expect(names.originalTranscript == "recording-2026-11-05-09-07.transcript.original.txt")
    // untype's own file must not look like an ntakker transcript.
    #expect(!names.segments.hasSuffix(".transcript.jsonl"))

    #expect(names.audioFiles(.off).isEmpty)
    #expect(names.audioFiles(MeetingAudioSettings(sources: .microphone, layout: .mixed)) == [names.microphoneAudio])
    #expect(names.audioFiles(MeetingAudioSettings(sources: .system, layout: .separate)) == [names.systemAudio])
    #expect(names.audioFiles(MeetingAudioSettings(sources: .both, layout: .separate)) == [names.microphoneAudio, names.systemAudio])
    #expect(names.audioFiles(MeetingAudioSettings(sources: .both, layout: .mixed)) == [names.mixedAudio])
    // Mixed needs both sides.
    #expect(!MeetingAudioSettings(sources: .microphone, layout: .mixed).isMixed)
}

@Test func meetingSidecarLinesAreInTheNtakkerFormat() throws {
    let start = Date(timeIntervalSince1970: 1_794_000_000)
    let segments = [
        MeetingSegment(startMs: 1_500, endMs: 4_000, side: .you, speaker: nil, language: "el", text: "γεια"),
        MeetingSegment(startMs: 5_000, endMs: 6_250, side: .call, speaker: "2", language: "en", text: "hello")
    ]
    let microphone = MeetingSidecarLine.file(segments, side: .you, meetingStart: start)
    let system = MeetingSidecarLine.file(segments, side: .call, meetingStart: start)
    #expect(microphone.hasSuffix("\n") && microphone.split(separator: "\n").count == 1)

    let mic = try #require(JSONSerialization.jsonObject(with: Data(microphone.utf8)) as? [String: Any])
    #expect(Set(mic.keys) == ["id", "timestamp", "source", "text", "model", "durationSec", "language", "speaker"])
    #expect(mic["source"] as? String == "microphone")
    #expect(mic["speaker"] as? String == "1")
    #expect(mic["text"] as? String == "γεια")
    #expect(mic["durationSec"] as? Double == 2.5)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    #expect(formatter.date(from: try #require(mic["timestamp"] as? String)) == start.addingTimeInterval(1.5))

    let call = try #require(JSONSerialization.jsonObject(with: Data(system.utf8)) as? [String: Any])
    #expect(call["source"] as? String == "system")
    #expect(call["speaker"] as? String == "2")
    #expect(call["language"] as? String == "en")
}

@Test func meetingPreferencesAudioDefaultsToBothSidesAndRejectsUnknownValues() throws {
    #expect(try MeetingPreferences().audioSettings == MeetingAudioSettings(sources: .both, layout: .separate))
    #expect(try MeetingPreferences(audioSources: "none").audioSettings == .off)
    let chosen = MeetingPreferences(audioSources: "both", audioLayout: "mixed")
    #expect(try chosen.audioSettings == MeetingAudioSettings(sources: .both, layout: .mixed))
    #expect(throws: (any Error).self) { try MeetingPreferences(audioSources: "everything").audioSettings }
    #expect(throws: (any Error).self) { try MeetingPreferences(audioSources: "both", audioLayout: "stereo").audioSettings }

    // Preferences saved before the audio settings load with the default.
    let legacy = try JSONDecoder().decode(MeetingPreferences.self, from: Data(#"{"language":"en","silenceMinutes":3}"#.utf8))
    #expect(try legacy.audioSettings == MeetingAudioSettings(sources: .both, layout: .separate))
    let saved = try JSONDecoder().decode(MeetingPreferences.self, from: JSONEncoder().encode(chosen))
    #expect(saved == chosen)
}

@Test func meetingAudioTimelinePutsSilenceBeforeLateAudio() {
    var timeline = MeetingAudioTimeline(sampleRate: 16_000, start: 100)
    // First chunk (0.1 s long) arrives 1.1 s in: one second of silence first.
    #expect(timeline.place(sampleCount: 1_600, at: 101.1) == 16_000)
    // Back to back: no silence, also with a little jitter.
    #expect(timeline.place(sampleCount: 1_600, at: 101.2) == 0)
    #expect(timeline.place(sampleCount: 1_600, at: 101.35) == 0)
    #expect(timeline.position == 16_000 + 3 * 1_600)
    // A two-second hole becomes silence.
    #expect(timeline.place(sampleCount: 1_600, at: 103.5) == Int(3.4 * 16_000) - (16_000 + 3 * 1_600))
    #expect(timeline.position == Int(3.5 * 16_000))
}

@Test func meetingAudioMixerAddsBothSidesInPlace() {
    var mixer = MeetingAudioMixer(maxLag: 100)
    // Source 0 alone: nothing is complete until source 1 passes it.
    #expect(mixer.add([10, 10, 10, 10], at: 0, source: 0).isEmpty)
    #expect(mixer.add([1, 2], at: 0, source: 1) == [11, 12])
    #expect(mixer.add([5, 5, 5], at: 2, source: 1) == [15, 15])
    #expect(mixer.finish() == [5])
}

@Test func meetingAudioMixerClampsAndDoesNotWaitForASilentSide() {
    var mixer = MeetingAudioMixer(maxLag: 4)
    // Source 1 never speaks: everything older than maxLag is released.
    #expect(mixer.add([Int16](repeating: 7, count: 10), at: 0, source: 0) == [Int16](repeating: 7, count: 6))
    // Late audio for released samples is dropped, the rest is mixed.
    // (position 5 is gone; 6 and 7 are now passed by both sides and clamp).
    #expect(mixer.add([Int16.max, Int16.max, Int16.max], at: 5, source: 1) == [Int16.max, Int16.max])
    #expect(mixer.finish() == [7, 7])
}

@Test func meetingAudioRecorderWritesSeparatePlayableFiles() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = try MeetingAudioRecorder(
        folder: folder,
        names: MeetingFileNames(stem: "recording-2026-11-05-09-07"),
        settings: MeetingAudioSettings(sources: .both, layout: .separate),
        sampleRate: 16_000,
        startUptime: 0,
        onError: { message in Issue.record("audio error: \(message)") }
    )
    // Two seconds of microphone from the start; one second of call from 1 s.
    for index in 0..<20 {
        recorder.push(data(tone(1_600)), side: .you, at: Double(index + 1) * 0.1)
    }
    for index in 10..<20 {
        recorder.push(data(tone(1_600)), side: .call, at: Double(index + 1) * 0.1)
    }
    let urls = recorder.finish()
    #expect(urls.map(\.lastPathComponent) == ["recording-2026-11-05-09-07.mic.m4a", "recording-2026-11-05-09-07.system.m4a"])
    // Both files are as long as the meeting: the call's first second is silence.
    for url in urls {
        #expect(abs(try duration(of: url) - 2.0) < 0.2)
    }
}

@Test func meetingAudioRecorderWritesOneMixedFile() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = try MeetingAudioRecorder(
        folder: folder,
        names: MeetingFileNames(stem: "recording-2026-11-05-09-07"),
        settings: MeetingAudioSettings(sources: .both, layout: .mixed),
        sampleRate: 16_000,
        startUptime: 0,
        onError: { message in Issue.record("audio error: \(message)") }
    )
    for index in 0..<30 {
        recorder.push(data(tone(1_600)), side: .you, at: Double(index + 1) * 0.1)
        if index < 10 {
            recorder.push(data(tone(1_600, amplitude: 4_000)), side: .call, at: Double(index + 1) * 0.1)
        }
    }
    let urls = recorder.finish()
    #expect(urls.map(\.lastPathComponent) == ["recording-2026-11-05-09-07.m4a"])
    #expect(abs(try duration(of: urls[0]) - 3.0) < 0.2)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["recording-2026-11-05-09-07.m4a"])
}

@Test func meetingAudioRecorderSavesOnlyTheChosenSide() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = try MeetingAudioRecorder(
        folder: folder,
        names: MeetingFileNames(stem: "recording-2026-11-05-09-07"),
        settings: MeetingAudioSettings(sources: .system, layout: .mixed),
        sampleRate: 16_000,
        startUptime: 0,
        onError: { message in Issue.record("audio error: \(message)") }
    )
    for index in 0..<10 {
        recorder.push(data(tone(1_600)), side: .you, at: Double(index + 1) * 0.1)
        recorder.push(data(tone(1_600)), side: .call, at: Double(index + 1) * 0.1)
    }
    let urls = recorder.finish()
    #expect(urls.map(\.lastPathComponent) == ["recording-2026-11-05-09-07.system.m4a"])
    #expect(abs(try duration(of: urls[0]) - 1.0) < 0.2)
}

@Test func meetingAudioIsOnDiskAndPlayableWhileRecording() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("recording-2026-11-05-09-07.mic.m4a")
    let writer = try MeetingAudioFileWriter(url: url, sampleRate: 16_000)
    // Ten seconds of audio, never closed: what a killed recording leaves.
    for _ in 0..<100 {
        try writer.write(tone(1_600))
    }
    try await Task.sleep(nanoseconds: 500_000_000)
    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    #expect(size > 10_000)
    let copy = folder.appendingPathComponent("copy.m4a")
    try FileManager.default.copyItem(at: url, to: copy)
    let seconds = try await AVURLAsset(url: copy).load(.duration).seconds
    // All but the fragment still being filled.
    #expect(seconds >= 6 && seconds <= 10.2)
    writer.close()
    #expect(abs(try await AVURLAsset(url: url).load(.duration).seconds - 10) < 0.2)
}

@Test func meetingTextFilesAreWrittenAsSegmentsArrive() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let names = MeetingFileNames(stem: "recording-2026-11-05-09-07")
    let live = try MeetingLiveFiles(folder: folder, names: names, start: Date(timeIntervalSince1970: 1_794_000_000), language: .english)
    func lines(_ name: String) throws -> [String] {
        try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8).split(separator: "\n").map(String.init)
    }
    // Every file exists from the start, empty.
    for name in [names.mainTranscript, names.originalTranscript, names.microphoneTranscript, names.systemTranscript, names.segments] {
        #expect(try lines(name).isEmpty)
    }
    live.append(MeetingSegment(startMs: 1_000, endMs: 2_000, side: .you, speaker: nil, language: "el", text: "γεια"))
    // On disk at once, before the files are closed.
    #expect(try lines(names.originalTranscript).count == 1)
    #expect(try lines(names.mainTranscript).count == 1)
    #expect(try lines(names.microphoneTranscript).count == 1)
    #expect(try lines(names.systemTranscript).isEmpty)
    #expect(try lines(names.segments).count == 1)
    live.append(MeetingSegment(startMs: 3_000, endMs: 4_000, side: .call, speaker: "1", language: "en", text: "hello"))
    #expect(try lines(names.mainTranscript).count == 2)
    #expect(try lines(names.systemTranscript).count == 1)
    #expect(try lines(names.segments).count == 2)
    live.close()
}
