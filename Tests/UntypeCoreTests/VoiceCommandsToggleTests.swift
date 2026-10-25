import Foundation
import Testing
@testable import UntypeCore

private func voiceMarkers(enabled: Bool) -> MarkerConfig {
    MarkerConfig(
        commandPhrase: "command",
        sectionEndPhrase: "command send",
        sectionEndAliases: ["τέλος εντολής"],
        sectionCancelPhrase: "command cancel",
        literalNextPhrase: "literal phrase",
        voiceCommandsEnabled: enabled
    )
}

private struct VoiceCommandsTemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-voice-commands-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

@Test func voiceCommandsAreEnabledByDefault() throws {
    let temp = VoiceCommandsTemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: ["--api-key", "flag-key", "--no-refine"])

    #expect(config.protocolConfig.markers.voiceCommandsEnabled)
}

@Test func noVoiceCommandsFlagDisablesVoiceCommands() throws {
    let temp = VoiceCommandsTemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: ["--api-key", "flag-key", "--no-refine", "--no-voice-commands"])

    #expect(config.protocolConfig.markers.voiceCommandsEnabled == false)
}

@Test func voiceCommandsEnvironmentIsHonoredAndFlagOverridesIt() throws {
    let temp = VoiceCommandsTemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: ["UNTYPE_VOICE_COMMANDS": "false"])

    let fromEnv = try resolver.resolve(argv: ["--api-key", "flag-key", "--no-refine"])
    let fromFlag = try resolver.resolve(argv: ["--api-key", "flag-key", "--no-refine", "--voice-commands"])

    #expect(fromEnv.protocolConfig.markers.voiceCommandsEnabled == false)
    #expect(fromFlag.protocolConfig.markers.voiceCommandsEnabled)
}

@Test func voiceCommandsRejectInvalidEnvironmentBoolean() {
    let temp = VoiceCommandsTemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: ["UNTYPE_VOICE_COMMANDS": "maybe"])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: ["--api-key", "flag-key", "--no-refine"])
    }
}

@Test func disabledVoiceCommandsTreatSpokenCommandsAsText() {
    let stateMachine = VoiceCommandStateMachine(
        markers: voiceMarkers(enabled: false),
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )

    let result = stateMachine.processFinal("say command translate on and command send")

    #expect(result.actions.isEmpty)
    #expect(result.visibleText == "say command translate on and command send")
    #expect(stateMachine.state.translate == false)
    #expect(stateMachine.definitions.isEmpty)

    let drained = stateMachine.drainForShutdown(options: DrainForShutdownOptions(submitPending: true))
    #expect(drained.contains(.sectionSubmitted(
        sectionId: "sec_000001",
        rawText: "say command translate on and command send",
        operators: []
    )))
}

@Test func enabledVoiceCommandsStillChangeOperators() {
    let stateMachine = VoiceCommandStateMachine(
        markers: voiceMarkers(enabled: true),
        initialOperators: OperatorState(refine: false, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )

    _ = stateMachine.processFinal("command translate on")

    #expect(stateMachine.state.translate)
}

@Test func uiSettingsVoiceCommandsDefaultOnAndReachSessionArguments() throws {
    #expect(UntypeUISettings.default.voiceCommands)
    #expect(try UntypeUISettings.default.sessionArguments().contains("--voice-commands"))

    let off = try UntypeUISettings.default.merged(UntypeUISettingsPatch(voiceCommands: false))
    #expect(off.voiceCommands == false)
    #expect(try off.sessionArguments().contains("--no-voice-commands"))
}

@Test func uiSettingsStoreRoundTripsVoiceCommandsAndDefaultsOlderStateToOn() throws {
    let temp = VoiceCommandsTemporaryDirectory()
    let off = try UntypeUISettings.default.merged(UntypeUISettingsPatch(voiceCommands: false))

    try UntypeUISettingsStore.save(off, home: temp.url)
    #expect(try UntypeUISettingsStore.load(home: temp.url).voiceCommands == false)

    let path = UntypeUISettingsStore.path(home: temp.url)
    var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    var settings = try #require(root["settings"] as? [String: Any])
    settings.removeValue(forKey: "voiceCommands")
    root["settings"] = settings
    try JSONSerialization.data(withJSONObject: root).write(to: path)

    #expect(try UntypeUISettingsStore.load(home: temp.url).voiceCommands)
}
