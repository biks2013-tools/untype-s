import Foundation
import Testing
@testable import UntypeCore

@Test func experimentalOperatorsAreFollowupSelectionScreenshotWindowText() {
    #expect(OperatorKey.experimental == [.followup, .selection, .screenshot, .windowText])
    #expect(OperatorKey.allCases.filter(\.isExperimental) == OperatorKey.experimental)
    #expect(!OperatorKey.refine.isExperimental)
}

@Test func experimentalOperatorsDefaultOffAndUnavailable() {
    let settings = UntypeUISettings.default
    #expect(settings.experimentalOperators == false)
    for key in OperatorKey.allCases {
        #expect(settings.isAvailable(key) == !key.isExperimental)
    }
}

@Test func experimentalOperatorsStayOffWhileSwitchedOff() throws {
    var settings = UntypeUISettings.default
    for key in OperatorKey.experimental {
        settings = try settings.merged(UntypeUISettings.operatorPatch(key, true))
        #expect(settings.value(of: key) == false)
    }
    // The others are not touched.
    settings = try settings.merged(UntypeUISettings.operatorPatch(.refine, true))
    #expect(settings.refine)
}

@Test func experimentalOperatorsCanBeSwitchedOnWithTheSwitch() throws {
    var settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(experimentalOperators: true))
    for key in OperatorKey.experimental {
        #expect(settings.isAvailable(key))
        #expect(settings.value(of: key) == false)
        settings = try settings.merged(UntypeUISettings.operatorPatch(key, true))
        #expect(settings.value(of: key))
    }
}

@Test func switchingExperimentalOperatorsOffSwitchesThemOff() throws {
    let on = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        refine: true,
        followup: true,
        selection: true,
        screenshot: true,
        windowText: true,
        experimentalOperators: true
    ))
    #expect(on.followup && on.selection && on.screenshot && on.windowText)
    let off = try on.merged(UntypeUISettingsPatch(experimentalOperators: false))
    #expect(!off.followup && !off.selection && !off.screenshot && !off.windowText)
    #expect(off.refine)
    // Back on: they stay off until the user switches each one on.
    let again = try off.merged(UntypeUISettingsPatch(experimentalOperators: true))
    #expect(!again.followup && !again.selection && !again.screenshot && !again.windowText)
}

@Test func experimentalOperatorsSwitchRoundTripsThroughTheStore() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("untype-experimental-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let changed = try UntypeUISettings.default.merged(UntypeUISettingsPatch(selection: true, experimentalOperators: true))
    try UntypeUISettingsStore.save(changed, home: home)
    let loaded = try UntypeUISettingsStore.load(home: home)
    #expect(loaded.experimentalOperators)
    #expect(loaded.selection)
}
