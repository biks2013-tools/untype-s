import Foundation
import Security
import Testing
@testable import UntypeCore

// plan-079: untype looks for a newer release and installs it.

private let latestJSON = """
{"tag_name":"v0.1.0-b90","html_url":"https://github.com/biks2013-tools/untype-s/releases/tag/v0.1.0-b90","draft":false,"prerelease":false,
 "body":"untype 0.1.0, build 90.\\n\\n## Download\\n\\nstuff\\n\\n## Changes in build 90\\n\\n- **One.** First.\\n- Two.\\n\\nFor older changes see b89.\\n\\n## Install\\n\\nmore",
 "assets":[{"name":"SHA256SUMS","browser_download_url":"https://example.invalid/SHA256SUMS"},
           {"name":"untype-0.1.0-notarized.zip","browser_download_url":"https://example.invalid/untype-0.1.0-notarized.zip"},
           {"name":"untype-0.1.0.dmg","browser_download_url":"https://example.invalid/untype-0.1.0.dmg"}]}
"""

@Test func aReleaseIsReadFromGitHubsAnswer() throws {
    let release = try #require(UntypeRelease.parse(latestRelease: Data(latestJSON.utf8)))
    #expect(release.tag == "v0.1.0-b90")
    #expect(release.version == "0.1.0")
    #expect(release.build == 90)
    #expect(release.archiveName == "untype-0.1.0-notarized.zip")
    #expect(release.archive.absoluteString == "https://example.invalid/untype-0.1.0-notarized.zip")
    #expect(release.checksums.absoluteString == "https://example.invalid/SHA256SUMS")
    // The offer shows what changed, not how to download or install.
    #expect(release.changes == "- **One.** First.\n- Two.\n\nFor older changes see b89.")

    #expect(UntypeRelease.parse(tag: "v0.1.0-b8")?.build == 8)
    #expect(UntypeRelease.parse(tag: "1.2.3-b100")?.version == "1.2.3")
    #expect(UntypeRelease.parse(tag: "pre-meeting-agent") == nil)
    #expect(UntypeRelease.parse(tag: "v0.1.0") == nil)
    // Not a release of the app: a draft, another tag, no notarized zip.
    #expect(UntypeRelease.parse(latestRelease: Data(latestJSON.replacingOccurrences(of: "\"draft\":false", with: "\"draft\":true").utf8)) == nil)
    #expect(UntypeRelease.parse(latestRelease: Data(latestJSON.replacingOccurrences(of: "v0.1.0-b90\",\"html", with: "deck-1\",\"html").utf8)) == nil)
    #expect(UntypeRelease.parse(latestRelease: Data(latestJSON.replacingOccurrences(of: "-notarized.zip", with: ".tar").utf8)) == nil)
    #expect(UntypeRelease.parse(latestRelease: Data("{\"message\":\"rate limit\"}".utf8)) == nil)
}

@Test func theDownloadIsCheckedAgainstThePublishedChecksum() throws {
    let sums = """
    cb3d5ebcc3c5430b80f0f06f904d1e9d94307aa87907adbc1fc848d03db5b82d  untype-0.1.0.dmg
    F9A922DA91E2C38030C50AF1C209C367A7A841C61849EA49CA8D7BDDC483734D  untype-0.1.0-notarized.zip
    """
    #expect(UntypeRelease.checksum(of: "untype-0.1.0-notarized.zip", in: sums) == "f9a922da91e2c38030c50af1c209c367a7a841c61849ea49ca8d7bddc483734d")
    #expect(UntypeRelease.checksum(of: "other.zip", in: sums) == nil)
    #expect(UntypeRelease.checksum(of: "untype-0.1.0.dmg", in: "short  untype-0.1.0.dmg") == nil)

    let file = FileManager.default.temporaryDirectory.appendingPathComponent("untype-sha-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("abc".utf8).write(to: file)
    #expect(try UntypeUpdateInstaller.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func aNewerBuildIsOfferedOncePerStartAndNeverInTheMiddleOfWork() throws {
    let release = try #require(UntypeRelease.parse(latestRelease: Data(latestJSON.utf8)))
    var policy = UntypeUpdatePolicy()
    #expect(policy.isCheckDue(now: Date()))
    policy.lastCheck = Date(timeIntervalSince1970: 1_000)
    #expect(!policy.isCheckDue(now: Date(timeIntervalSince1970: 1_000 + 3_600)))
    #expect(policy.isCheckDue(now: Date(timeIntervalSince1970: 1_000 + 6 * 3_600)))

    #expect(UntypeUpdatePolicy.isNewer(release, than: 89))
    #expect(!UntypeUpdatePolicy.isNewer(release, than: 90))
    #expect(!UntypeUpdatePolicy.isNewer(release, than: nil))

    #expect(policy.shouldOffer(release, currentBuild: 89, busy: false))
    // A meeting is being recorded: later.
    #expect(!policy.shouldOffer(release, currentBuild: 89, busy: true))
    policy.offeredBuild = 90
    #expect(!policy.shouldOffer(release, currentBuild: 89, busy: false))
    policy.offeredBuild = nil
    policy.skippedBuild = 90
    #expect(!policy.shouldOffer(release, currentBuild: 89, busy: false))
    policy.skippedBuild = 89
    #expect(policy.shouldOffer(release, currentBuild: 88, busy: false))
}

/// Runs the swap script on folders standing in for the apps, with the
/// process id of a process that has ended.
private func swap(newExists: Bool) throws -> (installed: String?, log: String, leftovers: [String]) {
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("untype swap's \(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let installed = work.appendingPathComponent("Applications/untype.app")
    let new = work.appendingPathComponent("unpacked/untype.app")
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: installed.appendingPathComponent("marker"))
    if newExists {
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: new.appendingPathComponent("marker"))
    }
    let ended = Process()
    ended.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try ended.run()
    ended.waitUntilExit()
    let log = work.appendingPathComponent("update.log")
    // `open` is replaced by a no-op: nothing is launched by the test.
    let script = UntypeUpdateInstaller.swapScript(pid: ended.processIdentifier, new: new, installed: installed, backup: work.appendingPathComponent("previous.app"), log: log)
        .replacingOccurrences(of: "/usr/bin/open ", with: "/usr/bin/true ")
    let file = work.appendingPathComponent("swap.sh")
    try script.write(to: file, atomically: true, encoding: .utf8)
    let run = Process()
    run.executableURL = URL(fileURLWithPath: "/bin/sh")
    run.arguments = [file.path]
    try run.run()
    run.waitUntilExit()
    return (
        try? String(contentsOf: installed.appendingPathComponent("marker"), encoding: .utf8),
        (try? String(contentsOf: log, encoding: .utf8)) ?? "",
        (try FileManager.default.contentsOfDirectory(atPath: work.path)).sorted()
    )
}

@Test func theNewAppTakesThePlaceOfTheOldOneAndTheOldOneComesBackWhenThatFails() throws {
    let done = try swap(newExists: true)
    #expect(done.installed == "new")
    #expect(done.log.contains("update: installed"))
    #expect(!done.leftovers.contains("previous.app"))

    let failed = try swap(newExists: false)
    #expect(failed.installed == "old")
    #expect(failed.log.contains("the previous one is back"))
    #expect(!failed.leftovers.contains("previous.app"))
}

@Test func onlyAnAppSignedAsUntypeIsAccepted() throws {
    // The installed untype stands in for a downloaded one; skipped where it is not installed.
    let app = URL(fileURLWithPath: "/Applications/untype.app")
    guard FileManager.default.fileExists(atPath: app.path) else {
        return
    }
    func requirement(_ text: String) throws -> SecRequirement {
        var requirement: SecRequirement?
        #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
        return try #require(requirement)
    }
    try UntypeUpdateInstaller.verify(app, satisfies: requirement(#"identifier "com.local.untype" and anchor apple generic and certificate leaf[subject.OU] = "9F9H8NCAUB""#))
    // Another developer's signature, or another app's identifier: refused.
    #expect(throws: UntypeUpdateError.self) {
        try UntypeUpdateInstaller.verify(app, satisfies: requirement(#"identifier "com.local.untype" and anchor apple generic and certificate leaf[subject.OU] = "AAAAAAAAAA""#))
    }
    #expect(throws: UntypeUpdateError.self) {
        try UntypeUpdateInstaller.verify(app, satisfies: requirement(#"identifier "com.example.other" and anchor apple generic"#))
    }
    // Something that is not an app at all.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("untype-notapp-\(UUID().uuidString).app", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(throws: UntypeUpdateError.self) {
        try UntypeUpdateInstaller.verify(folder, satisfies: requirement(#"identifier "com.local.untype" and anchor apple generic"#))
    }
}

@MainActor
@Test func aCopyThatIsNotAnInstalledAppDoesNotUpdateItself() {
    let defaults = UserDefaults(suiteName: "untype-updater-\(UUID().uuidString)")!
    let model = UntypeUpdateModel(defaults: defaults, current: UntypeAppVersion(version: nil, build: nil))
    #expect(!model.canUpdate)
    #expect(model.checksAutomatically)
    model.check(userAsked: true)
    #expect(model.phase == .idle)
    model.checksAutomatically = false
    #expect(UntypeUpdateModel(defaults: defaults, current: UntypeAppVersion(version: nil, build: nil)).checksAutomatically == false)
}

/// Against GitHub itself: the latest release is found, downloaded, checked
/// and unpacked next to a stand-in for the installed app. Only when asked
/// for (UNTYPE_UPDATE_LIVE_TEST=1): it downloads the whole release.
@Test(.enabled(if: ProcessInfo.processInfo.environment["UNTYPE_UPDATE_LIVE_TEST"] == "1"))
func theLatestReleaseIsDownloadedCheckedAndUnpacked() async throws {
    let release = try #require(try await UntypeUpdateInstaller.latestRelease())
    #expect(release.build >= 88)
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("untype-live-\(UUID().uuidString)", isDirectory: true)
    let installed = work.appendingPathComponent("untype.app", isDirectory: true)
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    var requirement: SecRequirement?
    #expect(SecRequirementCreateWithString(#"identifier "com.local.untype" and anchor apple generic and certificate leaf[subject.OU] = "9F9H8NCAUB""# as CFString, [], &requirement) == errSecSuccess)

    let new = try await UntypeUpdateInstaller.prepare(release, replacing: installed, currentBuild: release.build - 1, requirement: requirement) { _ in }
    defer { try? FileManager.default.removeItem(at: new.deletingLastPathComponent().deletingLastPathComponent()) }
    #expect(FileManager.default.isExecutableFile(atPath: new.appendingPathComponent("Contents/MacOS/untype").path))
    #expect(FileManager.default.isExecutableFile(atPath: new.appendingPathComponent("Contents/MacOS/untype-node").path))

    // The same download is refused as "not newer" by a copy already on that build,
    // and as wrongly signed when another developer's signature is asked for.
    await #expect(throws: UntypeUpdateError.notNewer) {
        _ = try await UntypeUpdateInstaller.prepare(release, replacing: installed, currentBuild: release.build, requirement: requirement) { _ in }
    }
}
