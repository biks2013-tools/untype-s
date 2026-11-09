import Foundation
import Testing
@testable import UntypeCore

@Test func overlayAlwaysVisibleDefaultsOffAndRoundTrips() throws {
    #expect(UntypeUISettings.default.overlayAlwaysVisible == false)

    let home = FileManager.default.temporaryDirectory.appendingPathComponent("untype-overlay-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let changed = try UntypeUISettings.default.merged(UntypeUISettingsPatch(overlayAlwaysVisible: true))
    #expect(changed.overlayAlwaysVisible)
    try UntypeUISettingsStore.save(changed, home: home)
    #expect(try UntypeUISettingsStore.load(home: home).overlayAlwaysVisible)

    // A state file written before the setting existed loads with it off.
    let path = UntypeUISettingsStore.path(home: home)
    var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    var settings = try #require(root["settings"] as? [String: Any])
    settings.removeValue(forKey: "overlayAlwaysVisible")
    root["settings"] = settings
    try JSONSerialization.data(withJSONObject: root).write(to: path)
    #expect(try UntypeUISettingsStore.load(home: home).overlayAlwaysVisible == false)
}
