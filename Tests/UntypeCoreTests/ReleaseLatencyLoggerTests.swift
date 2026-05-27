import Foundation
import Testing
@testable import UntypeCore

@Test func releaseLatencyJsonlLoggerAppendsStructuredPrivacySafeRecords() throws {
    let temp = LatencyTemporaryDirectory()
    let path = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
        .appendingPathComponent("release-latency.jsonl")
        .path
    let logger = ReleaseLatencyJsonlLogger(path: path)
    let record = ReleaseLatencyLogRecord(
        turnId: "turn-1",
        releaseTimestamp: "2026-05-26T20:00:00.000Z",
        trigger: "ui-hotkey-release",
        sttProvider: "soniox",
        quickClose: true,
        textSource: "quick_close_partial",
        outcome: "delivered_to_focused_input",
        totalMs: 12.5,
        durationsMs: ReleaseLatencyDurations(
            providerCommitRequestMs: nil,
            providerFinalWaitMs: nil,
            protocolSubmissionMs: 8,
            protocolOperatorProcessingMs: 7,
            refineMs: 2,
            translateMs: nil,
            clipboardMs: nil,
            focusedInputMs: 3
        ),
        sectionsProcessed: 1,
        focusedInput: ReleaseLatencyFocusedInput(
            attempted: true,
            ok: true,
            method: "ax-value",
            accessibilityTrusted: true,
            focusedElementAvailable: true,
            targetRole: "AXTextArea"
        )
    )

    try logger.append(record)
    try logger.append(record)

    let text = try String(contentsOfFile: path, encoding: .utf8)
    let lines = text.split(separator: "\n")
    #expect(lines.count == 2)
    #expect(text.contains(#""text_source":"quick_close_partial""#))
    #expect(text.contains(#""focused_input":{"#))
    #expect(!text.contains("dictated secret"))
    #expect(!text.contains("processed secret"))
    #expect(!text.contains("api-key"))
}

@Test func releaseLatencyJsonlLoggerResetOnStartClearsExistingCustomPathOnce() throws {
    let temp = LatencyTemporaryDirectory()
    let path = temp.url
        .appendingPathComponent("custom")
        .appendingPathComponent("release-latency.jsonl")
        .path
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: path).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "old record\n".write(toFile: path, atomically: true, encoding: .utf8)

    try ReleaseLatencyJsonlLogger.resetOnStartIfNeeded(path: path)

    #expect(try String(contentsOfFile: path, encoding: .utf8) == "")

    let logger = ReleaseLatencyJsonlLogger(path: path)
    try logger.append(sampleReleaseLatencyRecord(turnId: "turn-1"))

    try "replacement record\n".write(toFile: path, atomically: true, encoding: .utf8)
    try ReleaseLatencyJsonlLogger.resetOnStartIfNeeded(path: path)

    #expect(try String(contentsOfFile: path, encoding: .utf8) == "replacement record\n")
}

@Test func releaseLatencyJsonlLoggerPreservesExistingLogWhenResetIsNotRequested() throws {
    let temp = LatencyTemporaryDirectory()
    let path = temp.url
        .appendingPathComponent("release-latency.jsonl")
        .path
    try "old record\n".write(toFile: path, atomically: true, encoding: .utf8)

    let logger = ReleaseLatencyJsonlLogger(path: path)
    try logger.append(sampleReleaseLatencyRecord(turnId: "turn-2"))

    let text = try String(contentsOfFile: path, encoding: .utf8)
    #expect(text.hasPrefix("old record\n"))
    #expect(text.contains(#""turn_id":"turn-2""#))
}

private func sampleReleaseLatencyRecord(turnId: String) -> ReleaseLatencyLogRecord {
    ReleaseLatencyLogRecord(
        turnId: turnId,
        releaseTimestamp: "2026-05-26T20:00:00.000Z",
        trigger: "ui-hotkey-release",
        sttProvider: "soniox",
        quickClose: false,
        textSource: "provider_final",
        outcome: "delivered_to_focused_input",
        totalMs: 20,
        durationsMs: ReleaseLatencyDurations(focusedInputMs: 3),
        sectionsProcessed: 1,
        focusedInput: .notAttempted()
    )
}

private final class LatencyTemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-latency-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
