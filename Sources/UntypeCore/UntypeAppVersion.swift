import Foundation

/// The version and build of the running app, read from its bundle
/// (`CFBundleShortVersionString`, `CFBundleVersion`). A binary run outside
/// an app bundle (`swift run`, the CLI) has neither.
public struct UntypeAppVersion: Equatable, Sendable {
    public let version: String?
    public let build: String?

    public init(version: String?, build: String?) {
        self.version = version
        self.build = build
    }

    public init(infoDictionary: [String: Any]?) {
        self.init(
            version: infoDictionary?["CFBundleShortVersionString"] as? String,
            build: infoDictionary?["CFBundleVersion"] as? String
        )
    }

    public static let current = UntypeAppVersion(infoDictionary: Bundle.main.infoDictionary)

    /// "0.1.0 · build 50"; "not an app bundle" when the bundle has neither.
    public var label: String {
        switch (version, build) {
        case let (version?, build?): return "\(version) · build \(build)"
        case let (version?, nil): return version
        case let (nil, build?): return "build \(build)"
        case (nil, nil): return "not an app bundle"
        }
    }
}
