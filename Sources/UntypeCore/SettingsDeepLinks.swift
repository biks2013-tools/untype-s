import Foundation

/// Deep links into the macOS System Settings privacy panes.
///
/// macOS 27 renamed the Accessibility pane to "Device Control and Data Access"
/// and stopped honouring the legacy `com.apple.preference.security` scheme. The
/// legacy URL still opens System Settings — `open` and `NSWorkspace.open` both
/// report success — but it lands on General instead of the requested pane, so
/// there is no runtime signal to detect the failure and retry with the other
/// scheme. The scheme has to be chosen up front, by OS version.
///
/// The pre-27 branch is the exact string that shipped before, so behaviour on
/// macOS 14-26 is unchanged.
///
/// Every entry point takes the choice as a parameter that defaults to this
/// Mac's own macOS, so tests can exercise both branches on either OS instead of
/// only the one the test machine happens to run.
public enum UntypeSettingsDeepLink {
    /// Privacy panes untype links to. The raw values are the anchors both URL
    /// schemes use; only the prefix differs between them.
    public enum Pane: String, Sendable, CaseIterable {
        case microphone = "Privacy_Microphone"
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
        case screenCapture = "Privacy_ScreenCapture"
    }

    static let legacyPrefix = "x-apple.systempreferences:com.apple.preference.security?"
    static let modernPrefix = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?"

    /// First macOS version that renamed the Accessibility pane and dropped the
    /// legacy scheme.
    static let modernSettingsMajorVersion = 27

    static func usesModernScheme(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= modernSettingsMajorVersion
    }

    static var usesModernScheme: Bool {
        usesModernScheme(on: ProcessInfo.processInfo.operatingSystemVersion)
    }

    public static func url(for pane: Pane) -> String {
        url(for: pane, modernScheme: usesModernScheme)
    }

    static func url(for pane: Pane, modernScheme: Bool) -> String {
        (modernScheme ? modernPrefix : legacyPrefix) + pane.rawValue
    }

    /// What the Accessibility pane is called in System Settings on this macOS,
    /// so the on-screen instructions match what the user actually sees.
    public static var accessibilityPaneName: String {
        accessibilityPaneName(modernScheme: usesModernScheme)
    }

    static func accessibilityPaneName(modernScheme: Bool) -> String {
        modernScheme ? "Device Control and Data Access" : "Accessibility"
    }

    /// Title of the onboarding card for this permission. Before macOS 27 the
    /// card said "Accessibility trust"; the renamed pane already reads as a
    /// capability, so it stands alone.
    public static var accessibilityCardTitle: String {
        accessibilityCardTitle(modernScheme: usesModernScheme)
    }

    static func accessibilityCardTitle(modernScheme: Bool) -> String {
        modernScheme ? accessibilityPaneName(modernScheme: true) : "Accessibility trust"
    }

    /// `System Settings › Privacy & Security › <pane>` for the Accessibility
    /// pane, in the wording of this macOS.
    public static var accessibilityPanePath: String {
        accessibilityPanePath(modernScheme: usesModernScheme)
    }

    static func accessibilityPanePath(modernScheme: Bool) -> String {
        "System Settings › Privacy & Security › \(accessibilityPaneName(modernScheme: modernScheme))"
    }
}
