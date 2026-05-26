import Foundation
import Testing
@testable import UntypeCore

@Test func uiSettingsSessionArgumentsDoNotContainSecretsOrStatuses() throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        provider: "elevenlabs",
        languages: ["auto"],
        quickClose: true,
        refine: true,
        clipboard: true,
        hotkeyEnabled: true,
        hotkey: "Command+`"
    ))

    let args = try settings.sessionArguments()

    #expect(args.contains("--stt-provider"))
    #expect(args.contains("elevenlabs"))
    #expect(args.contains("--clipboard-default"))
    #expect(args.contains("on"))
    #expect(args.contains("--quick-close"))
    #expect(!args.contains("ELEVENLABS_API_KEY"))
    #expect(!args.contains(settings.apiKeyStatus))
    #expect(!args.contains(settings.storageStatus))
}

@Test func uiSettingsStorePersistsOnlyNonSecretFields() throws {
    let temp = UITemporaryDirectory()
    var settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        provider: "soniox",
        model: "stt-rt-v4",
        languages: ["el", "en"],
        quickClose: true,
        hotkeyEnabled: true,
        hotkey: "Control+`",
        windowWidth: 1320,
        windowHeight: 840,
        monitorSidebarExpanded: false,
        settingsExpanded: false,
        selectedMonitorTab: "events"
    ))
    settings.apiKeyName = "SONIOX_API_KEY"
    settings.apiKeyStatus = "configured"
    settings.storageStatus = "shell env"
    settings.expiryStatus = "2026-06-01"
    settings.microphoneStatus = "authorized"
    settings.accessibilityStatus = "trusted"

    try UntypeUISettingsStore.save(settings, home: temp.url)
    let statePath = UntypeUISettingsStore.path(home: temp.url)
    let raw = try String(contentsOf: statePath, encoding: .utf8)
    let loaded = try UntypeUISettingsStore.load(home: temp.url)

    #expect(loaded.provider == "soniox")
    #expect(loaded.hotkeyEnabled)
    #expect(loaded.quickClose)
    #expect(loaded.windowWidth == 1320)
    #expect(loaded.windowHeight == 840)
    #expect(!loaded.monitorSidebarExpanded)
    #expect(!loaded.settingsExpanded)
    #expect(loaded.selectedMonitorTab == "events")
    #expect(raw.contains("\"windowWidth\""))
    #expect(raw.contains("\"windowHeight\""))
    #expect(raw.contains("\"monitorSidebarExpanded\""))
    #expect(raw.contains("\"settingsExpanded\""))
    #expect(raw.contains("\"selectedMonitorTab\""))
    #expect(raw.contains("\"quickClose\""))
    #expect(!raw.contains("configured"))
    #expect(!raw.contains("shell env"))
    #expect(!raw.contains("2026-06-01"))
    #expect(!raw.contains("SONIOX_API_KEY"))
    #expect(!raw.contains("authorized"))
    #expect(!raw.contains("trusted"))
    #expect(raw.contains("\"push_to_talk\""))
}

@Test func uiSettingsStoreRejectsInvalidPersistedMonitorTab() throws {
    let temp = UITemporaryDirectory()
    let config = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    try """
    {
      "version" : 1,
      "saved_at" : "2026-05-25T10:00:00Z",
      "settings" : {
        "clipboard" : false,
        "endpointDetection" : true,
        "focusedInput" : false,
        "hotkey" : "Control+`",
        "hotkeyEnabled" : false,
        "languages" : [
          "el",
          "en"
        ],
        "llmEnabled" : true,
        "llmModel" : "gpt-5.4",
        "llmProvider" : "azure-openai",
        "model" : "stt-rt-v4",
        "protocolMode" : "dictation",
        "provider" : "soniox",
        "refine" : false,
        "sampleRate" : 16000,
        "selectedMonitorTab" : "diagnostics",
        "settingsExpanded" : true,
        "translate" : false,
        "translationPolicy" : "opposite",
        "windowHeight" : 760,
        "windowWidth" : 1180
      }
    }
    """.write(
        to: UntypeUISettingsStore.path(home: temp.url),
        atomically: true,
        encoding: .utf8
    )

    #expect(throws: UntypeError.self) {
        _ = try UntypeUISettingsStore.load(home: temp.url)
    }
}

@Test func uiSettingsAcceptsHistoryAsPersistedMonitorTab() throws {
    let temp = UITemporaryDirectory()
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        selectedMonitorTab: "history"
    ))

    try UntypeUISettingsStore.save(settings, home: temp.url)
    let loaded = try UntypeUISettingsStore.load(home: temp.url)

    #expect(loaded.selectedMonitorTab == "history")
}

@Test func uiSettingsLoadForUIPreservesPersistedWindowAndMonitorState() throws {
    let temp = UITemporaryDirectory()
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        windowWidth: 1440,
        windowHeight: 900,
        monitorSidebarExpanded: false,
        settingsExpanded: false,
        selectedMonitorTab: "events"
    ))
    try UntypeUISettingsStore.save(settings, home: temp.url)

    let result = UntypeUISettingsStore.loadForUI(
        cwd: temp.url,
        home: temp.url,
        shell: ["SONIOX_API_KEY": "secret-value"],
        permissionStatus: {
            UntypePermissionStatus(microphone: "authorized", accessibility: "trusted")
        }
    )

    #expect(result.settings.windowWidth == 1440)
    #expect(result.settings.windowHeight == 900)
    #expect(!result.settings.monitorSidebarExpanded)
    #expect(!result.settings.settingsExpanded)
    #expect(result.settings.selectedMonitorTab == "events")
}

@Test func uiSettingsLoadSupportsOlderPersistedStateWithoutQuickClose() throws {
    let temp = UITemporaryDirectory()
    let config = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    try """
    {
      "version" : 1,
      "saved_at" : "2026-05-26T10:00:00Z",
      "settings" : {
        "clipboard" : false,
        "endpointDetection" : true,
        "focusedInput" : false,
        "hotkey" : "Control+`",
        "hotkeyEnabled" : false,
        "languages" : [
          "el",
          "en"
        ],
        "llmEnabled" : true,
        "llmModel" : "gpt-5.4",
        "llmProvider" : "azure-openai",
        "model" : "stt-rt-v4",
        "protocolMode" : "dictation",
        "provider" : "soniox",
        "refine" : false,
        "sampleRate" : 16000,
        "selectedMonitorTab" : "transcript",
        "settingsExpanded" : true,
        "translate" : false,
        "translationPolicy" : "opposite",
        "windowHeight" : 760,
        "windowWidth" : 1180
      }
    }
    """.write(
        to: UntypeUISettingsStore.path(home: temp.url),
        atomically: true,
        encoding: .utf8
    )

    let loaded = try UntypeUISettingsStore.load(home: temp.url)

    #expect(loaded.quickClose == false)
}

@Test func uiSettingsCredentialRefreshReportsSourceWithoutSecretValue() throws {
    let temp = UITemporaryDirectory()
    try "SONIOX_API_KEY=secret-value\nSONIOX_API_KEY_EXPIRES_AT=2026-06-01\n".write(
        to: temp.url.appendingPathComponent(".env"),
        atomically: true,
        encoding: .utf8
    )

    let settings = UntypeUISettings.default.refreshingCredentialStatus(
        cwd: temp.url,
        home: temp.url,
        shell: [:]
    )

    #expect(settings.apiKeyName == "SONIOX_API_KEY")
    #expect(settings.apiKeyStatus == "configured")
    #expect(settings.storageStatus == "local .env")
    #expect(settings.expiryStatus == "2026-06-01")
}

@Test func uiSettingsCredentialRefreshIncludesTransientPermissionStatus() throws {
    let temp = UITemporaryDirectory()
    let settings = UntypeUISettings.default.refreshingCredentialStatus(
        cwd: temp.url,
        home: temp.url,
        shell: ["SONIOX_API_KEY": "secret-value"],
        permissionStatus: {
            UntypePermissionStatus(microphone: "authorized", accessibility: "not trusted")
        }
    )

    #expect(settings.apiKeyStatus == "configured")
    #expect(settings.microphoneStatus == "authorized")
    #expect(settings.accessibilityStatus == "not trusted")
}

@Test func uiSettingsLoadForUIDerivesInitialStateFromConfigChain() throws {
    let temp = UITemporaryDirectory()
    let userConfig = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
    try FileManager.default.createDirectory(at: userConfig, withIntermediateDirectories: true)
    try """
    ELEVENLABS_API_KEY=xi-user-key
    UNTYPE_STT_PROVIDER=elevenlabs
    UNTYPE_MODEL=scribe_custom
    UNTYPE_LANGUAGES=en
    UNTYPE_INTERACTION_MODE=agent-protocol
    UNTYPE_REFINE=false
    """.write(
        to: userConfig.appendingPathComponent(".env"),
        atomically: true,
        encoding: .utf8
    )
    try savePersistedProtocolSettings(
        ProtocolSettingsSnapshot(
            operators: OperatorState(refine: true, translate: true, clipboard: false, input: true),
            translationPolicy: .toEnglish
        ),
        options: ProtocolSettingsStoreOptions(home: temp.url)
    )

    let result = UntypeUISettingsStore.loadForUI(
        cwd: temp.url,
        home: temp.url,
        shell: [:],
        permissionStatus: {
            UntypePermissionStatus(microphone: "authorized", accessibility: "trusted")
        }
    )

    #expect(result.errorMessage == nil)
    #expect(result.settings.provider == "elevenlabs")
    #expect(result.settings.apiKeyName == "ELEVENLABS_API_KEY")
    #expect(result.settings.apiKeyStatus == "configured")
    #expect(result.settings.storageStatus == "user .env")
    #expect(result.settings.model == "scribe_custom")
    #expect(result.settings.languages == ["en"])
    #expect(result.settings.protocolMode == "agent-protocol")
    #expect(result.settings.refine)
    #expect(result.settings.translate)
    #expect(result.settings.focusedInput)
    #expect(result.settings.translationPolicy == "to-en")
    #expect(result.settings.llmEnabled == false)
    #expect(result.settings.microphoneStatus == "authorized")
    #expect(result.settings.accessibilityStatus == "trusted")
}

@Test func uiSettingsLoadForUIUsesInspectionModeWhenStrictLlmConfigIsMissing() throws {
    let temp = UITemporaryDirectory()

    let result = UntypeUISettingsStore.loadForUI(
        cwd: temp.url,
        home: temp.url,
        shell: ["SONIOX_API_KEY": "shell-key"],
        permissionStatus: {
            UntypePermissionStatus(microphone: "not determined", accessibility: "not trusted")
        }
    )

    #expect(result.errorMessage?.contains("Azure OpenAI is enabled") == true)
    #expect(result.settings.provider == "soniox")
    #expect(result.settings.apiKeyStatus == "configured")
    #expect(result.settings.storageStatus == "shell env")
    #expect(result.settings.llmEnabled)
    #expect(result.settings.llmProvider == "azure-openai")
    #expect(result.settings.microphoneStatus == "not determined")
    #expect(result.settings.accessibilityStatus == "not trusted")
}

@Test func uiSettingsNormalizesSourceStyleHotkeyAliases() throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        hotkey: "ctrl-Backquote"
    ))

    #expect(settings.hotkey == "Control+`")
}

@Test func uiSettingsRejectsAmbiguousHotkeyModifiers() throws {
    #expect(throws: UntypeError.invalidConfiguration("CommandOrControl cannot be combined with explicit Command or Control modifiers.")) {
        _ = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
            hotkey: "CommandOrControl+Command+`"
        ))
    }
}

@Test func uiControlAvailabilityKeepsOnlyProtocolOperatorsEditableWhileSessionRuns() {
    let idle = UntypeUIControlAvailability(isSessionActive: false)
    let active = UntypeUIControlAvailability(isSessionActive: true)

    #expect(idle.sessionShapingControlsEnabled)
    #expect(idle.protocolOperatorControlsEnabled)
    #expect(!active.sessionShapingControlsEnabled)
    #expect(active.protocolOperatorControlsEnabled)
}

@Test func uiAudioStatusLabelsPushToTalkMutedAudioExplicitly() {
    #expect(UntypeUIAudioStatusFormatter.label(for: AudioActivitySnapshot(
        peak: 0.42,
        byteCount: 2,
        mutedByGate: true
    )) == "muted by push-to-talk 42%")
    #expect(UntypeUIAudioStatusFormatter.label(for: AudioActivitySnapshot(
        peak: 0.01,
        byteCount: 2,
        mutedByGate: false
    )) == "silent 1%")
    #expect(UntypeUIAudioStatusFormatter.label(for: AudioActivitySnapshot(
        peak: 0.25,
        byteCount: 2,
        mutedByGate: false
    )) == "active 25%")
}

private final class UITemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-s-ui-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
