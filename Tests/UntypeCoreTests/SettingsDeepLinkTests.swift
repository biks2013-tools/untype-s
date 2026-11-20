import Foundation
import Testing
@testable import UntypeCore

private let legacyPrefix = "x-apple.systempreferences:com.apple.preference.security?"
private let modernPrefix = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?"
private var allPanes: [UntypeSettingsDeepLink.Pane] { UntypeSettingsDeepLink.Pane.allCases }

private func version(_ major: Int) -> OperatingSystemVersion {
    OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
}

// MARK: - the version gate itself

@Test(arguments: [14, 15, 23, 26])
func macOSUpTo26KeepsTheLegacyScheme(major: Int) {
    #expect(UntypeSettingsDeepLink.usesModernScheme(on: version(major)) == false)
}

@Test(arguments: [27, 28, 40])
func macOS27AndLaterUsesTheModernScheme(major: Int) {
    #expect(UntypeSettingsDeepLink.usesModernScheme(on: version(major)))
}

@Test func theGateTurnsExactlyAtMacOS27() {
    #expect(UntypeSettingsDeepLink.usesModernScheme(on: OperatingSystemVersion(majorVersion: 26, minorVersion: 9, patchVersion: 9)) == false)
    #expect(UntypeSettingsDeepLink.usesModernScheme(on: version(27)))
}

// MARK: - the URLs each branch produces

@Test func theLegacyBranchIsByteIdenticalToWhatShippedBefore() {
    // These four strings were hardcoded in the app before the gate existed.
    // macOS 14-26 must keep getting exactly them.
    #expect(UntypeSettingsDeepLink.url(for: .microphone, modernScheme: false)
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    #expect(UntypeSettingsDeepLink.url(for: .accessibility, modernScheme: false)
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    #expect(UntypeSettingsDeepLink.url(for: .inputMonitoring, modernScheme: false)
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    #expect(UntypeSettingsDeepLink.url(for: .screenCapture, modernScheme: false)
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
}

@Test func theModernBranchIsTheSchemeConfirmedOnMacOS27() {
    // Confirmed by hand on macOS 27.0.1: this one navigates, the legacy one
    // opens General.
    #expect(UntypeSettingsDeepLink.url(for: .accessibility, modernScheme: true)
        == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
    #expect(UntypeSettingsDeepLink.url(for: .inputMonitoring, modernScheme: true)
        == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")
}

@Test func bothBranchesKeepThePaneAnchorsAndDifferOnlyInThePrefix() {
    for pane in allPanes {
        let legacy = UntypeSettingsDeepLink.url(for: pane, modernScheme: false)
        let modern = UntypeSettingsDeepLink.url(for: pane, modernScheme: true)
        #expect(legacy == legacyPrefix + pane.rawValue)
        #expect(modern == modernPrefix + pane.rawValue)
        #expect(legacy != modern)
        #expect(URL(string: legacy) != nil)
        #expect(URL(string: modern) != nil)
    }
}

@Test func theFourPaneAnchorsAreTheOnesMacOSUnderstands() {
    #expect(UntypeSettingsDeepLink.Pane.microphone.rawValue == "Privacy_Microphone")
    #expect(UntypeSettingsDeepLink.Pane.accessibility.rawValue == "Privacy_Accessibility")
    #expect(UntypeSettingsDeepLink.Pane.inputMonitoring.rawValue == "Privacy_ListenEvent")
    #expect(UntypeSettingsDeepLink.Pane.screenCapture.rawValue == "Privacy_ScreenCapture")
}

// MARK: - the on-screen wording

@Test func thePaneIsNamedTheWayEachMacOSNamesIt() {
    #expect(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: false) == "Accessibility")
    #expect(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: true) == "Device Control and Data Access")
    #expect(UntypeSettingsDeepLink.accessibilityPanePath(modernScheme: false)
        == "System Settings › Privacy & Security › Accessibility")
    #expect(UntypeSettingsDeepLink.accessibilityPanePath(modernScheme: true)
        == "System Settings › Privacy & Security › Device Control and Data Access")
}

// MARK: - what this Mac actually gets

@Test func theHostResolvesToTheBranchItsMacOSNeeds() {
    let expectModern = UntypeSettingsDeepLink.usesModernScheme(on: ProcessInfo.processInfo.operatingSystemVersion)
    for pane in allPanes {
        #expect(UntypeSettingsDeepLink.url(for: pane)
            == UntypeSettingsDeepLink.url(for: pane, modernScheme: expectModern))
    }
    #expect(UntypeSettingsDeepLink.accessibilityPaneName
        == UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: expectModern))
}

// MARK: - macOS 26 and earlier must be untouched

/// Every user-visible string the gate feeds, as it read before the gate existed.
/// These are copied from the pre-gate source; if a change makes macOS 26 say
/// anything else, this fails.
@Test func pre27WordingIsExactlyWhatShippedBefore() {
    #expect(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: false) == "Accessibility")
    #expect(UntypeSettingsDeepLink.accessibilityCardTitle(modernScheme: false) == "Accessibility trust")
    #expect(UntypeSettingsDeepLink.accessibilityPanePath(modernScheme: false)
        == "System Settings › Privacy & Security › Accessibility")

    // The guide block title, step and button label are built from the pane name.
    #expect("\(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: false)) (push-to-talk hotkey and text insertion)"
        == "Accessibility (push-to-talk hotkey and text insertion)")
    #expect("Open \(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: false)) settings"
        == "Open Accessibility settings")
    #expect("Grant \(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: false))"
        == "Grant Accessibility")
    #expect("How to enable Microphone, \(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: false)) and Input Monitoring"
        == "How to enable Microphone, Accessibility and Input Monitoring")

    // WindowTextCapture keeps its own arrow separators, not the guide's.
    #expect("Accessibility permission is missing: allow untype in System Settings → Privacy & Security → \(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: false))."
        == "Accessibility permission is missing: allow untype in System Settings → Privacy & Security → Accessibility.")
}

@Test func macOS27GetsTheRenamedPaneEverywhere() {
    #expect(UntypeSettingsDeepLink.accessibilityPaneName(modernScheme: true) == "Device Control and Data Access")
    #expect(UntypeSettingsDeepLink.accessibilityCardTitle(modernScheme: true) == "Device Control and Data Access")
}
