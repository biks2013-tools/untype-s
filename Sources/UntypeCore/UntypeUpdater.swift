#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import Security
import SwiftUI

// plan-079: untype looks for a newer build among its GitHub releases, from
// time to time, and offers to install it: the notarized zip of the release
// is downloaded, checked (its SHA-256 against the release's SHA256SUMS, its
// signature against this app's own designated requirement), put in the
// place of the running app, and untype starts again.

/// A release of untype on GitHub.
public struct UntypeRelease: Equatable, Sendable {
    public let tag: String
    public let version: String
    public let build: Int
    /// The release's notes (Markdown).
    public let notes: String
    public let page: URL
    /// The notarized zip of the app, and the file of checksums.
    public let archive: URL
    public let archiveName: String
    public let checksums: URL

    /// `v0.1.0-b88` → ("0.1.0", 88).
    public static func parse(tag: String) -> (version: String, build: Int)? {
        guard let match = tag.range(of: #"^v?(\d+(?:\.\d+)+)-b(\d+)$"#, options: .regularExpression), match == tag.startIndex..<tag.endIndex,
              let dash = tag.range(of: "-b", options: .backwards),
              let build = Int(tag[dash.upperBound...]) else {
            return nil
        }
        let version = tag[..<dash.lowerBound].drop(while: { $0 == "v" })
        return (String(version), build)
    }

    /// The release in GitHub's answer to `releases/latest` (nil when it is
    /// not a release of the app: another tag, a draft, no notarized zip).
    public static func parse(latestRelease data: Data) -> UntypeRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let parsed = parse(tag: tag),
              object["draft"] as? Bool != true,
              object["prerelease"] as? Bool != true,
              let page = (object["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = object["assets"] as? [[String: Any]] else {
            return nil
        }
        func asset(_ matches: (String) -> Bool) -> (name: String, url: URL)? {
            for asset in assets {
                if let name = asset["name"] as? String, matches(name),
                   let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) {
                    return (name, url)
                }
            }
            return nil
        }
        guard let archive = asset({ $0.hasSuffix("-notarized.zip") }),
              let checksums = asset({ $0 == "SHA256SUMS" }) else {
            return nil
        }
        return UntypeRelease(
            tag: tag,
            version: parsed.version,
            build: parsed.build,
            notes: object["body"] as? String ?? "",
            page: page,
            archive: archive.url,
            archiveName: archive.name,
            checksums: checksums.url
        )
    }

    /// What changed, for the offer: the "Changes in build N" part of the
    /// notes (everything when they have none), without Markdown headings.
    public var changes: String {
        var text = notes
        if let start = notes.range(of: #"(?m)^## Changes in build \d+\s*$"#, options: .regularExpression) {
            text = String(notes[start.upperBound...])
            if let next = text.range(of: #"(?m)^## "#, options: .regularExpression) {
                text = String(text[..<next.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The checksum of `name` in a `shasum -a 256` file.
    public static func checksum(of name: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name, parts[0].count == 64 {
                return parts[0].lowercased()
            }
        }
        return nil
    }
}

public enum UntypeUpdateError: LocalizedError, Equatable {
    case notAnApp
    case notWritable(String)
    case network(String)
    case checksum
    case unpack(String)
    case signature(String)
    case notNewer
    case busy(String)

    public var errorDescription: String? {
        switch self {
        case .notAnApp:
            return "This copy of untype is not an installed app, so it cannot update itself."
        case .notWritable(let folder):
            return "untype cannot write in \(folder). Download the new version from the release page and replace the app by hand."
        case .network(let message):
            return "The download failed: \(message)"
        case .checksum:
            return "The downloaded file does not match the checksum published with the release. Nothing was installed."
        case .unpack(let message):
            return "The downloaded file could not be opened: \(message)"
        case .signature(let message):
            return "The downloaded app is not signed as this untype is (\(message)). Nothing was installed."
        case .notNewer:
            return "The downloaded app is not newer than the one running. Nothing was installed."
        case .busy(let what):
            return "\(what) Install the update afterwards."
        }
    }
}

/// The steps of installing a release that do not need the user interface.
public enum UntypeUpdateInstaller {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/biks2013-tools/untype-s/releases/latest")!

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // A generic client name: nothing about the user or the Mac.
        request.setValue("untype-updater", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        return request
    }

    public static func latestRelease(session: URLSession = .shared) async throws -> UntypeRelease? {
        var request = request(latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UntypeUpdateError.network("GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return UntypeRelease.parse(latestRelease: data)
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The running app's own designated requirement: who signed it and as
    /// what. An app that satisfies it is the same app for macOS, so the
    /// permissions granted to untype stay.
    public static func ownRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else {
            throw UntypeUpdateError.signature("this untype has no signature to compare with")
        }
        return requirement
    }

    /// Checks that `app` is whole, signed, and signed as `requirement` says.
    public static func verify(_ app: URL, satisfies requirement: SecRequirement) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UntypeUpdateError.signature("it cannot be read as an app")
        }
        var error: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, &error)
        guard status == errSecSuccess else {
            let reason = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "status \(status)"
            throw UntypeUpdateError.signature(reason)
        }
    }

    static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Downloads, checks and unpacks `release` next to `installed` (same
    /// volume). Returns the new app, ready to take its place.
    public static func prepare(
        _ release: UntypeRelease,
        replacing installed: URL,
        currentBuild: Int,
        requirement givenRequirement: SecRequirement? = nil,
        session: URLSession = .shared,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        guard installed.pathExtension == "app" else {
            throw UntypeUpdateError.notAnApp
        }
        let parent = installed.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path), FileManager.default.isWritableFile(atPath: installed.path) else {
            throw UntypeUpdateError.notWritable(parent.path)
        }
        // The running app's own requirement, unless a test gives one.
        let requirement = try givenRequirement ?? ownRequirement()
        let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true)

        progress("Downloading build \(release.build)…")
        let archive = work.appendingPathComponent(release.archiveName)
        do {
            let (downloaded, response) = try await session.download(for: request(release.archive))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UntypeUpdateError.network("the server answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            try FileManager.default.moveItem(at: downloaded, to: archive)
            let (sums, sumsResponse) = try await session.data(for: request(release.checksums))
            guard (sumsResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw UntypeUpdateError.network("the checksums could not be read")
            }
            progress("Checking the download…")
            guard let expected = UntypeRelease.checksum(of: release.archiveName, in: String(decoding: sums, as: UTF8.self)),
                  try sha256(of: archive) == expected else {
                throw UntypeUpdateError.checksum
            }
        } catch let error as UntypeUpdateError {
            throw error
        } catch {
            throw UntypeUpdateError.network(error.localizedDescription)
        }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        let ditto = try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        guard ditto.status == 0 else {
            throw UntypeUpdateError.unpack(ditto.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let app = unpacked.appendingPathComponent(installed.lastPathComponent)
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw UntypeUpdateError.unpack("it does not hold \(installed.lastPathComponent)")
        }
        try verify(app, satisfies: requirement)
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let build = (info?["CFBundleVersion"] as? String).flatMap(Int.init), build > currentBuild, build == release.build else {
            throw UntypeUpdateError.notNewer
        }
        return app
    }

    /// The script that takes over when untype quits: it waits for the
    /// process to end, puts the new app in the place of the old one (which
    /// comes back if that fails) and opens it.
    public static func swapScript(pid: Int32, new: URL, installed: URL, backup: URL, log: URL) -> String {
        func quoted(_ url: URL) -> String {
            "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return """
        #!/bin/sh
        exec >> \(quoted(log)) 2>&1
        echo "$(date -u +%FT%TZ) update: waiting for untype (\(pid)) to quit"
        n=0
        while kill -0 \(pid) 2>/dev/null; do
          n=$((n + 1))
          if [ "$n" -gt 300 ]; then echo "update: untype did not quit; nothing was changed"; exit 1; fi
          sleep 0.2
        done
        if mv \(quoted(installed)) \(quoted(backup)); then
          if mv \(quoted(new)) \(quoted(installed)); then
            echo "$(date -u +%FT%TZ) update: installed"
            rm -rf \(quoted(backup))
          else
            echo "update: the new app could not be put in place; the previous one is back"
            mv \(quoted(backup)) \(quoted(installed))
          fi
        else
          echo "update: the installed app could not be moved; nothing was changed"
        fi
        /usr/bin/open \(quoted(installed))
        """
    }

    /// Starts the swap script, which outlives untype.
    public static func startSwap(new: URL, installed: URL, log: URL) throws {
        let work = new.deletingLastPathComponent().deletingLastPathComponent()
        let script = work.appendingPathComponent("swap.sh")
        let backup = work.appendingPathComponent("previous.app")
        try swapScript(pid: ProcessInfo.processInfo.processIdentifier, new: new, installed: installed, backup: backup, log: log)
            .write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

/// When to look for a release and when to offer it.
public struct UntypeUpdatePolicy: Equatable, Sendable {
    /// Between two looks at GitHub.
    public static let checkInterval: TimeInterval = 6 * 3600

    public var lastCheck: Date?
    /// The build the user said to skip.
    public var skippedBuild: Int?
    /// The build already offered since untype started.
    public var offeredBuild: Int?

    public init(lastCheck: Date? = nil, skippedBuild: Int? = nil, offeredBuild: Int? = nil) {
        self.lastCheck = lastCheck
        self.skippedBuild = skippedBuild
        self.offeredBuild = offeredBuild
    }

    public func isCheckDue(now: Date) -> Bool {
        guard let lastCheck else {
            return true
        }
        return now.timeIntervalSince(lastCheck) >= Self.checkInterval
    }

    /// Whether `release` is newer than the running build.
    public static func isNewer(_ release: UntypeRelease, than currentBuild: Int?) -> Bool {
        guard let currentBuild else {
            return false
        }
        return release.build > currentBuild
    }

    /// Whether to put the offer in front of the user now: once per build
    /// and start of untype, not a skipped build, and not in the middle of a
    /// meeting recording or a dictation.
    public func shouldOffer(_ release: UntypeRelease, currentBuild: Int?, busy: Bool) -> Bool {
        Self.isNewer(release, than: currentBuild)
            && release.build != skippedBuild
            && release.build != offeredBuild
            && !busy
    }
}

/// The updater as the app sees it.
@MainActor
public final class UntypeUpdateModel: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case installing(String)
        case failed(String)
    }

    private static let automaticKey = "untype.updates.automatic"
    private static let skippedKey = "untype.updates.skippedBuild"

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var release: UntypeRelease?
    @Published public private(set) var lastChecked: Date?
    /// Look for new versions without being asked (on until switched off).
    @Published public var checksAutomatically: Bool {
        didSet {
            defaults.set(checksAutomatically, forKey: Self.automaticKey)
        }
    }

    /// Log lines.
    public var onEvent: (String) -> Void = { _ in }
    /// Whether a meeting is being recorded or a dictation runs (and what
    /// to tell the user then).
    public var busyReason: () -> String? = { nil }
    /// Shows the offer window.
    public var showOffer: () -> Void = {}
    /// Quits untype (the swap script then installs and reopens it).
    public var quit: () -> Void = { NSApp.terminate(nil) }

    private let defaults: UserDefaults
    private let currentBuild: Int?
    private var policy: UntypeUpdatePolicy
    private var timer: Timer?

    public init(defaults: UserDefaults = .standard, current: UntypeAppVersion = .current) {
        self.defaults = defaults
        currentBuild = current.build.flatMap(Int.init)
        checksAutomatically = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        policy = UntypeUpdatePolicy(skippedBuild: defaults.object(forKey: Self.skippedKey) as? Int)
    }

    /// An installed app can update itself; a binary run from a build folder cannot.
    public var canUpdate: Bool {
        currentBuild != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    public var isUpdateAvailable: Bool {
        release.map { UntypeUpdatePolicy.isNewer($0, than: currentBuild) } ?? false
    }

    /// Looks a little after the start, then keeps looking.
    public func start() {
        guard canUpdate, timer == nil else {
            return
        }
        let timer = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.tick()
        }
    }

    private func tick() {
        guard checksAutomatically else {
            return
        }
        if policy.isCheckDue(now: Date()) {
            check(userAsked: false)
        } else {
            offerIfDue()
        }
    }

    /// Looks for a newer release now.
    public func check(userAsked: Bool) {
        guard canUpdate, phase != .checking else {
            return
        }
        if case .installing = phase {
            return
        }
        phase = .checking
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let latest = try await UntypeUpdateInstaller.latestRelease()
                self.policy.lastCheck = Date()
                self.lastChecked = self.policy.lastCheck
                if let latest, UntypeUpdatePolicy.isNewer(latest, than: self.currentBuild) {
                    let isNews = self.release?.build != latest.build
                    self.release = latest
                    self.phase = .available
                    if isNews {
                        self.onEvent("diagnostic.info: [untype] update: build \(latest.build) is available (this is build \(self.currentBuild ?? 0))")
                    }
                    if userAsked {
                        self.policy.offeredBuild = latest.build
                        self.showOffer()
                    } else {
                        self.offerIfDue()
                    }
                } else {
                    self.release = nil
                    self.phase = .upToDate
                }
            } catch {
                // An automatic look that fails is tried again later, quietly.
                self.phase = userAsked ? .failed("Could not look for updates: \(error.localizedDescription)") : .idle
                self.onEvent("diagnostic.warning: [untype] update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func offerIfDue() {
        guard let release, policy.shouldOffer(release, currentBuild: currentBuild, busy: busyReason() != nil) else {
            return
        }
        policy.offeredBuild = release.build
        showOffer()
    }

    /// "Skip this version": it is not offered again; the next one is.
    public func skip() {
        guard let release else {
            return
        }
        policy.skippedBuild = release.build
        defaults.set(release.build, forKey: Self.skippedKey)
        onEvent("diagnostic.info: [untype] update: build \(release.build) skipped on request")
    }

    /// Downloads, checks and installs the release, then restarts untype.
    public func install() {
        guard let release, let currentBuild else {
            return
        }
        if case .installing = phase {
            return
        }
        if let reason = busyReason() {
            phase = .failed(UntypeUpdateError.busy(reason).localizedDescription)
            return
        }
        phase = .installing("Starting…")
        onEvent("diagnostic.info: [untype] update: installing build \(release.build)")
        let installed = Bundle.main.bundleURL
        Task { @MainActor [weak self] in
            do {
                let new = try await UntypeUpdateInstaller.prepare(release, replacing: installed, currentBuild: currentBuild) { message in
                    Task { @MainActor in self?.phase = .installing(message) }
                }
                guard let self else {
                    return
                }
                // The download took a while: a recording may have started.
                if let reason = self.busyReason() {
                    throw UntypeUpdateError.busy(reason)
                }
                self.phase = .installing("Restarting untype…")
                let log = FileManager.default.untypeHomeDirectory.appendingPathComponent(".tool-agents/untype/update.log")
                try UntypeUpdateInstaller.startSwap(new: new, installed: installed, log: log)
                self.onEvent("diagnostic.info: [untype] update: build \(release.build) downloaded and checked; restarting")
                self.quit()
            } catch {
                self?.phase = .failed(error.localizedDescription)
                self?.onEvent("diagnostic.warning: [untype] update not installed: \(error.localizedDescription)")
            }
        }
    }
}

/// The offer: a small window, never in the way of a dictation.
@MainActor
final class UntypeUpdateWindowController: NSObject {
    private let model: UntypeUpdateModel
    private var window: NSWindow?

    init(model: UntypeUpdateModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // In front, without taking the keyboard from the app in use.
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "untype update"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: UntypeUpdateView(model: model, close: { [weak self] in self?.close() }))
        window.center()
        return window
    }
}

struct UntypeUpdateView: View {
    @ObservedObject var model: UntypeUpdateModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let release = model.release {
                Text("untype \(release.version) · build \(release.build) is available")
                    .font(.system(size: 15, weight: .semibold))
                Text("You have \(UntypeAppVersion.current.label).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(UntypeAssistantView.rendered(release.changes))
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08)))
                status
                HStack {
                    Button("Skip this version") {
                        model.skip()
                        close()
                    }
                    .disabled(isInstalling)
                    Button("Release page") {
                        NSWorkspace.shared.open(release.page)
                    }
                    Spacer()
                    Button("Later", action: close)
                        .disabled(isInstalling)
                    Button("Install and restart") {
                        model.install()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInstalling)
                }
            } else {
                Text("untype is up to date.")
                Button("Close", action: close)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    private var isInstalling: Bool {
        if case .installing = model.phase {
            return true
        }
        return false
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .installing(let message):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(UntypeDesignTokens.accentAmber)
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text("The download is checked against the release's checksum and this app's own signature before anything is replaced. untype restarts; your settings and permissions stay.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings → General → Updates.
struct UntypeUpdateSettingsRows: View {
    @ObservedObject var model: UntypeUpdateModel

    var body: some View {
        Toggle("Look for new versions automatically", isOn: $model.checksAutomatically)
            .disabled(!model.canUpdate)
        LabeledContent(statusText) {
            HStack {
                if model.isUpdateAvailable {
                    Button("Show…") { model.showOffer() }
                }
                Button("Check now") { model.check(userAsked: true) }
                    .disabled(!model.canUpdate || model.phase == .checking)
            }
        }
    }

    private var statusText: String {
        if !model.canUpdate {
            return "This copy of untype is not an installed app"
        }
        switch model.phase {
        case .checking: return "Looking…"
        case .available: return model.release.map { "Build \($0.build) is available" } ?? "A new version is available"
        case .installing(let message): return message
        case .failed(let message): return message
        case .upToDate: return "untype is up to date (\(UntypeAppVersion.current.label))"
        case .idle: return "untype \(UntypeAppVersion.current.label)"
        }
    }
}
#endif
