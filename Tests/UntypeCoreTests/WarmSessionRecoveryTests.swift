import Foundation
import Testing
@testable import UntypeCore

@Test func warmSessionRecoveryTreatsOnlyRuntimeStopsAsUnexpected() {
    #expect(WarmSessionRecovery.isRuntimeInitiatedStop("transcriber-error"))
    #expect(WarmSessionRecovery.isRuntimeInitiatedStop("mic-end"))
    #expect(!WarmSessionRecovery.isRuntimeInitiatedStop("ui-hotkey-release"))
    #expect(!WarmSessionRecovery.isRuntimeInitiatedStop("ui-hotkey-warm-restart"))
    #expect(!WarmSessionRecovery.isRuntimeInitiatedStop("ui-quit"))
    #expect(!WarmSessionRecovery.isRuntimeInitiatedStop("startup-error"))
    #expect(!WarmSessionRecovery.isRuntimeInitiatedStop(nil))
}

@Test func warmSessionRecoveryBacksOffWhileSessionsDieYoung() {
    var attempts = WarmSessionRecovery.attemptsAfterUnexpectedStop(previous: 0, lived: 111)
    #expect(attempts == 0)
    #expect(WarmSessionRecovery.delaySeconds(attempts: attempts) == 1)
    attempts = WarmSessionRecovery.attemptsAfterUnexpectedStop(previous: attempts, lived: 2)
    #expect(WarmSessionRecovery.delaySeconds(attempts: attempts) == 2)
    for _ in 0..<10 {
        attempts = WarmSessionRecovery.attemptsAfterUnexpectedStop(previous: attempts, lived: 1)
    }
    #expect(WarmSessionRecovery.delaySeconds(attempts: attempts) == 60)
    #expect(WarmSessionRecovery.attemptsAfterUnexpectedStop(previous: attempts, lived: 45) == 0)
}

@Test func warmSessionRecoveryDoesNotRetryConfigurationOrAuthFailures() {
    #expect(!WarmSessionRecovery.shouldRetryStartup(after: UntypeError.invalidConfiguration("x")))
    #expect(!WarmSessionRecovery.shouldRetryStartup(after: UntypeError.sonioxAuth("x")))
    #expect(WarmSessionRecovery.shouldRetryStartup(after: UntypeError.sonioxNetwork("x")))
    #expect(WarmSessionRecovery.shouldRetryStartup(after: URLError(.notConnectedToInternet)))
}

@Test func eventLogPersistsDiagnosticsButNeverDictatedText() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("untype-s-tests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = UntypeEventLogFile(url: directory.appendingPathComponent("events.log"))

    log.append("session.state: stopped (transcriber-error)")
    log.append("diagnostic.warning: [untype] push-to-talk session ended unexpectedly")
    log.append("transcript.final: my private sentence")
    log.append("protocol.event: {\"raw_text\":\"secret\"}")
    log.flush()

    let text = try String(contentsOf: log.url, encoding: .utf8)
    #expect(text.contains("session.state: stopped (transcriber-error)"))
    #expect(text.contains("ended unexpectedly"))
    #expect(!text.contains("private sentence"))
    #expect(!text.contains("secret"))
    let mode = try FileManager.default.attributesOfItem(atPath: log.url.path)[.posixPermissions] as? NSNumber
    #expect(mode?.intValue == 0o600)
}

@Test func eventLogRotatesPastItsLimit() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("untype-s-tests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = UntypeEventLogFile(url: directory.appendingPathComponent("events.log"))
    let line = "diagnostic.info: " + String(repeating: "x", count: 10_000)
    for _ in 0..<(UntypeEventLogFile.maxBytes / 10_000 + 5) {
        log.append(line)
    }
    log.flush()
    #expect(FileManager.default.fileExists(atPath: log.url.path + ".1"))
    let size = try FileManager.default.attributesOfItem(atPath: log.url.path)[.size] as? NSNumber
    #expect((size?.intValue ?? .max) <= UntypeEventLogFile.maxBytes)
}
