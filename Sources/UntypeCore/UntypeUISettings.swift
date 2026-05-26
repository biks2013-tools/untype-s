import Foundation

public struct UntypeUISettings: Codable, Equatable, Sendable {
    public var provider: String
    public var model: String
    public var languages: [String]
    public var sampleRate: Int
    public var endpointDetection: Bool
    public var protocolMode: String
    public var refine: Bool
    public var translate: Bool
    public var clipboard: Bool
    public var focusedInput: Bool
    public var translationPolicy: String
    public var llmEnabled: Bool
    public var llmProvider: String
    public var llmModel: String
    public var apiKeyName: String
    public var apiKeyStatus: String
    public var expiryStatus: String
    public var storageStatus: String
    public var inputStatus: String
    public var microphoneStatus: String
    public var accessibilityStatus: String
    public var hotkeyEnabled: Bool
    public var hotkey: String
    public var windowWidth: Double
    public var windowHeight: Double
    public var settingsExpanded: Bool
    public var selectedMonitorTab: String
    public var selectedEventsFilter: String
    public var compactWindow: Bool
    public var appearance: String

    public static let `default` = UntypeUISettings(
        provider: "soniox",
        model: "stt-rt-v4",
        languages: ["el", "en"],
        sampleRate: 16_000,
        endpointDetection: true,
        protocolMode: "dictation",
        refine: false,
        translate: false,
        clipboard: false,
        focusedInput: false,
        translationPolicy: TranslationPolicy.opposite.rawValue,
        llmEnabled: true,
        llmProvider: LLMProvider.azureOpenAI.rawValue,
        llmModel: "gpt-5.4",
        apiKeyName: "SONIOX_API_KEY",
        apiKeyStatus: "unknown",
        expiryStatus: "not set",
        storageStatus: "resolved config",
        inputStatus: "Off",
        microphoneStatus: "unknown",
        accessibilityStatus: "unknown",
        hotkeyEnabled: false,
        hotkey: "Control+`",
        windowWidth: 1180,
        windowHeight: 760,
        settingsExpanded: true,
        selectedMonitorTab: "transcript",
        selectedEventsFilter: "all",
        compactWindow: false,
        appearance: "system"
    )

    public func normalized() throws -> UntypeUISettings {
        let provider = try normalizeProvider(provider)
        let languages = try normalizeLanguages(languages)
        let protocolMode = try normalizeProtocolMode(protocolMode)
        let translationPolicy = try normalizeTranslationPolicy(translationPolicy)
        let llmProvider = try normalizeLLMProvider(llmProvider)
        let model = try normalizeNonEmpty(model, field: "model")
        let llmModel = try normalizeNonEmpty(llmModel, field: "llmModel")
        let hotkey = try normalizeHotkey(hotkey)
        let selectedMonitorTab = try normalizeMonitorTab(selectedMonitorTab)
        guard (8_000...48_000).contains(sampleRate) else {
            throw UntypeError.invalidConfiguration("sampleRate must be an integer between 8000 and 48000. Got: \(sampleRate).")
        }
        guard windowWidth >= 860 else {
            throw UntypeError.invalidConfiguration("windowWidth must be at least 860. Got: \(windowWidth).")
        }
        guard windowHeight >= 620 else {
            throw UntypeError.invalidConfiguration("windowHeight must be at least 620. Got: \(windowHeight).")
        }

        var next = self
        next.provider = provider
        next.model = model
        next.languages = languages
        next.sampleRate = sampleRate
        next.protocolMode = protocolMode
        next.translationPolicy = translationPolicy
        next.llmProvider = llmProvider
        next.llmModel = llmModel
        next.hotkey = hotkey
        next.selectedMonitorTab = selectedMonitorTab
        next.selectedEventsFilter = try normalizeEventsFilter(selectedEventsFilter)
        next.appearance = try normalizeAppearance(appearance)
        next.apiKeyName = provider == STTProvider.elevenlabs.rawValue ? "ELEVENLABS_API_KEY" : "SONIOX_API_KEY"
        next.apiKeyStatus = nonEmptyStatus(apiKeyStatus, fallback: "unknown")
        next.expiryStatus = nonEmptyStatus(expiryStatus, fallback: "not set")
        next.storageStatus = nonEmptyStatus(storageStatus, fallback: "resolved config")
        next.inputStatus = focusedInput ? "Ready" : "Off"
        next.microphoneStatus = nonEmptyStatus(microphoneStatus, fallback: "unknown")
        next.accessibilityStatus = nonEmptyStatus(accessibilityStatus, fallback: "unknown")
        return next
    }

    public func merged(_ patch: UntypeUISettingsPatch) throws -> UntypeUISettings {
        var next = self
        if let provider = patch.provider {
            next.provider = provider
        }
        if let model = patch.model {
            next.model = model
        }
        if let languages = patch.languages {
            next.languages = languages
        }
        if let sampleRate = patch.sampleRate {
            next.sampleRate = sampleRate
        }
        if let endpointDetection = patch.endpointDetection {
            next.endpointDetection = endpointDetection
        }
        if let protocolMode = patch.protocolMode {
            next.protocolMode = protocolMode
        }
        if let refine = patch.refine {
            next.refine = refine
        }
        if let translate = patch.translate {
            next.translate = translate
        }
        if let clipboard = patch.clipboard {
            next.clipboard = clipboard
        }
        if let focusedInput = patch.focusedInput {
            next.focusedInput = focusedInput
        }
        if let translationPolicy = patch.translationPolicy {
            next.translationPolicy = translationPolicy
        }
        if let llmEnabled = patch.llmEnabled {
            next.llmEnabled = llmEnabled
        }
        if let llmProvider = patch.llmProvider {
            next.llmProvider = llmProvider
        }
        if let llmModel = patch.llmModel {
            next.llmModel = llmModel
        }
        if let hotkeyEnabled = patch.hotkeyEnabled {
            next.hotkeyEnabled = hotkeyEnabled
        }
        if let hotkey = patch.hotkey {
            next.hotkey = hotkey
        }
        if let windowWidth = patch.windowWidth {
            next.windowWidth = windowWidth
        }
        if let windowHeight = patch.windowHeight {
            next.windowHeight = windowHeight
        }
        if let settingsExpanded = patch.settingsExpanded {
            next.settingsExpanded = settingsExpanded
        }
        if let selectedMonitorTab = patch.selectedMonitorTab {
            next.selectedMonitorTab = selectedMonitorTab
        }
        if let selectedEventsFilter = patch.selectedEventsFilter {
            next.selectedEventsFilter = selectedEventsFilter
        }
        if let compactWindow = patch.compactWindow {
            next.compactWindow = compactWindow
        }
        if let appearance = patch.appearance {
            next.appearance = appearance
        }
        return try next.normalized()
    }

    public func sessionArguments() throws -> [String] {
        let normalized = try normalized()
        var args = [
            "--stt-provider", normalized.provider,
            "--model", normalized.model,
            "--sample-rate", String(normalized.sampleRate),
            normalized.endpointDetection ? "--endpoint-detection" : "--no-endpoint-detection",
            "--interaction-mode", normalized.protocolMode,
            "--refine-default", normalized.refine ? "on" : "off",
            "--translate-default", normalized.translate ? "on" : "off",
            "--clipboard-default", normalized.clipboard ? "on" : "off",
            "--input-default", normalized.focusedInput ? "on" : "off",
            "--translation-policy", normalized.translationPolicy,
            normalized.llmEnabled ? "--refine" : "--no-refine",
            "--llm-provider", normalized.llmProvider,
            "--llm-model", normalized.llmModel
        ]
        for language in normalized.languages {
            args += ["--language", language]
        }
        return args
    }

    public func refreshingCredentialStatus(
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: [String: String] = ProcessInfo.processInfo.environment,
        permissionStatus: @Sendable () -> UntypePermissionStatus = UntypePermissionStatus.current
    ) -> UntypeUISettings {
        var next = (try? normalized()) ?? self
        let provider = (try? normalizeProvider(next.provider)) ?? STTProvider.soniox.rawValue
        let keyName = provider == STTProvider.elevenlabs.rawValue ? "ELEVENLABS_API_KEY" : "SONIOX_API_KEY"
        let expiryName = provider == STTProvider.elevenlabs.rawValue ? "ELEVENLABS_API_KEY_EXPIRES_AT" : "SONIOX_API_KEY_EXPIRES_AT"
        next.apiKeyName = keyName
        do {
            let chain = try EnvChain(cwd: cwd, home: home, shell: shell)
            if let key = chain.get(keyName) {
                next.apiKeyStatus = "configured"
                next.storageStatus = uiSourceLabel(key.source)
            } else {
                next.apiKeyStatus = "missing"
                next.storageStatus = "not found"
            }
            next.expiryStatus = chain.get(expiryName)?.value ?? "not set"
        } catch {
            next.apiKeyStatus = "unknown"
            next.storageStatus = error.localizedDescription
            next.expiryStatus = "unknown"
        }
        next.inputStatus = next.focusedInput ? "Ready" : "Off"
        let permissions = permissionStatus()
        next.microphoneStatus = permissions.microphone
        next.accessibilityStatus = permissions.accessibility
        return next
    }
}

public struct UntypeUISettingsPatch: Sendable, Equatable {
    public var provider: String?
    public var model: String?
    public var languages: [String]?
    public var sampleRate: Int?
    public var endpointDetection: Bool?
    public var protocolMode: String?
    public var refine: Bool?
    public var translate: Bool?
    public var clipboard: Bool?
    public var focusedInput: Bool?
    public var translationPolicy: String?
    public var llmEnabled: Bool?
    public var llmProvider: String?
    public var llmModel: String?
    public var hotkeyEnabled: Bool?
    public var hotkey: String?
    public var windowWidth: Double?
    public var windowHeight: Double?
    public var settingsExpanded: Bool?
    public var selectedMonitorTab: String?
    public var selectedEventsFilter: String?
    public var compactWindow: Bool?
    public var appearance: String?

    public init(
        provider: String? = nil,
        model: String? = nil,
        languages: [String]? = nil,
        sampleRate: Int? = nil,
        endpointDetection: Bool? = nil,
        protocolMode: String? = nil,
        refine: Bool? = nil,
        translate: Bool? = nil,
        clipboard: Bool? = nil,
        focusedInput: Bool? = nil,
        translationPolicy: String? = nil,
        llmEnabled: Bool? = nil,
        llmProvider: String? = nil,
        llmModel: String? = nil,
        hotkeyEnabled: Bool? = nil,
        hotkey: String? = nil,
        windowWidth: Double? = nil,
        windowHeight: Double? = nil,
        settingsExpanded: Bool? = nil,
        selectedMonitorTab: String? = nil,
        selectedEventsFilter: String? = nil,
        compactWindow: Bool? = nil,
        appearance: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.languages = languages
        self.sampleRate = sampleRate
        self.endpointDetection = endpointDetection
        self.protocolMode = protocolMode
        self.refine = refine
        self.translate = translate
        self.clipboard = clipboard
        self.focusedInput = focusedInput
        self.translationPolicy = translationPolicy
        self.llmEnabled = llmEnabled
        self.llmProvider = llmProvider
        self.llmModel = llmModel
        self.hotkeyEnabled = hotkeyEnabled
        self.hotkey = hotkey
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.settingsExpanded = settingsExpanded
        self.selectedMonitorTab = selectedMonitorTab
        self.selectedEventsFilter = selectedEventsFilter
        self.compactWindow = compactWindow
        self.appearance = appearance
    }
}

public struct UntypeUIControlAvailability: Sendable, Equatable {
    public let sessionShapingControlsEnabled: Bool
    public let protocolOperatorControlsEnabled: Bool

    public init(isSessionActive: Bool) {
        sessionShapingControlsEnabled = !isSessionActive
        protocolOperatorControlsEnabled = true
    }
}

public enum UntypeUIAudioStatusFormatter {
    public static func label(for snapshot: AudioActivitySnapshot) -> String {
        let percent = Int((snapshot.peak * 100).rounded())
        if snapshot.mutedByGate {
            return "muted by push-to-talk \(percent)%"
        }
        if percent <= 1 {
            return "silent \(percent)%"
        }
        return "active \(percent)%"
    }
}

public struct UntypeUISettingsLoadResult: Sendable, Equatable {
    public let settings: UntypeUISettings
    public let errorMessage: String?

    public init(settings: UntypeUISettings, errorMessage: String? = nil) {
        self.settings = settings
        self.errorMessage = errorMessage
    }
}

public enum UntypeUISettingsStore {
    public static func path(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".tool-agents")
            .appendingPathComponent("untype")
            .appendingPathComponent("ui-state.json")
    }

    public static func loadForUI(
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: [String: String] = ProcessInfo.processInfo.environment,
        permissionStatus: @Sendable () -> UntypePermissionStatus = UntypePermissionStatus.current
    ) -> UntypeUISettingsLoadResult {
        let persisted: UntypeUISettings?
        do {
            persisted = try loadIfExists(home: home)
        } catch {
            return UntypeUISettingsLoadResult(
                settings: UntypeUISettings.default.refreshingCredentialStatus(
                    cwd: cwd,
                    home: home,
                    shell: shell,
                    permissionStatus: permissionStatus
                ),
                errorMessage: settingsDiagnosticLine(error)
            )
        }

        let current = persisted ?? UntypeUISettings.default
        let argv = (try? persisted?.sessionArguments()) ?? []
        do {
            let settings = try settingsFromConfiguration(
                argv: argv,
                current: current,
                cwd: cwd,
                home: home,
                shell: shell,
                validateLLMProviderConfig: true,
                permissionStatus: permissionStatus
            )
            return UntypeUISettingsLoadResult(settings: settings)
        } catch {
            let strictError = error
            do {
                let settings = try settingsFromConfiguration(
                    argv: argv,
                    current: current,
                    cwd: cwd,
                    home: home,
                    shell: shell,
                    validateLLMProviderConfig: false,
                    permissionStatus: permissionStatus
                )
                return UntypeUISettingsLoadResult(
                    settings: settings,
                    errorMessage: settingsDiagnosticLine(strictError)
                )
            } catch {
                return UntypeUISettingsLoadResult(
                    settings: current.refreshingCredentialStatus(
                        cwd: cwd,
                        home: home,
                        shell: shell,
                        permissionStatus: permissionStatus
                    ),
                    errorMessage: settingsDiagnosticLine(strictError)
                )
            }
        }
    }

    public static func loadIfExists(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> UntypeUISettings? {
        let url = path(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try load(home: home)
    }

    public static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> UntypeUISettings {
        let url = path(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return UntypeUISettings.default
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(PersistedUIStateFile.self, from: data)
            guard file.version == 1 else {
                throw UntypeError.invalidConfiguration("Invalid UI settings state at \(url.path): version must be 1. Delete or fix \(url.path).")
            }
            guard let settings = file.settings else {
                if let pushToTalk = file.pushToTalk {
                    return try UntypeUISettings.default.merged(UntypeUISettingsPatch(
                        hotkeyEnabled: pushToTalk.enabled,
                        hotkey: pushToTalk.hotkey
                    ))
                }
                throw UntypeError.invalidConfiguration("Invalid UI settings state at \(url.path): settings or push_to_talk must be present. Delete or fix \(url.path).")
            }
            return try settings.toRuntimeSettings(path: url.path).normalized()
        } catch let error as UntypeError {
            throw error
        } catch {
            throw UntypeError.invalidConfiguration("Failed to parse UI settings state at \(url.path): \(error.localizedDescription)")
        }
    }

    public static func save(_ settings: UntypeUISettings, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let normalized = try settings.normalized()
        let url = path(home: home)
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let file = PersistedUIStateFile(
                version: 1,
                savedAt: iso8601Now(),
                settings: PersistedUISettings(settings: normalized),
                pushToTalk: PersistedPushToTalkSettings(
                    enabled: normalized.hotkeyEnabled,
                    hotkey: normalized.hotkey
                )
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(file) + Data("\n".utf8)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch let error as UntypeError {
            throw error
        } catch {
            throw UntypeError.invalidConfiguration("Failed to write UI settings state at \(url.path): \(error.localizedDescription)")
        }
    }

    private static func settingsFromConfiguration(
        argv: [String],
        current: UntypeUISettings,
        cwd: URL,
        home: URL,
        shell: [String: String],
        validateLLMProviderConfig: Bool,
        permissionStatus: @Sendable () -> UntypePermissionStatus
    ) throws -> UntypeUISettings {
        let config = try ConfigResolver(
            cwd: cwd,
            home: home,
            shell: shell,
            requireProtocolOutputForHybrid: false,
            validateLLMProviderConfig: validateLLMProviderConfig
        ).resolve(argv: argv)
        let persistedProtocol = try loadPersistedProtocolSettings(options: ProtocolSettingsStoreOptions(home: home))
        let protocolConfig = applyPersistedProtocolSettings(config.protocolConfig, persisted: persistedProtocol)
        let operators = protocolConfig.initialOperators
        let settings = UntypeUISettings(
            provider: config.sttProvider.rawValue,
            model: config.model,
            languages: config.languages,
            sampleRate: config.sampleRate,
            endpointDetection: config.enableEndpointDetection,
            protocolMode: protocolConfig.interactionMode.rawValue,
            refine: operators.refine,
            translate: operators.translate,
            clipboard: operators.clipboard,
            focusedInput: operators.input,
            translationPolicy: protocolConfig.translationPolicy.rawValue,
            llmEnabled: config.llm.enabled,
            llmProvider: config.llm.provider.rawValue,
            llmModel: config.llm.model,
            apiKeyName: config.apiKeyEnvName,
            apiKeyStatus: "configured",
            expiryStatus: config.apiKeyExpiresAt ?? "not set",
            storageStatus: uiSourceLabel(config.apiKeySource),
            inputStatus: operators.input ? "Ready" : "Off",
            microphoneStatus: current.microphoneStatus,
            accessibilityStatus: current.accessibilityStatus,
            hotkeyEnabled: current.hotkeyEnabled,
            hotkey: current.hotkey,
            windowWidth: current.windowWidth,
            windowHeight: current.windowHeight,
            settingsExpanded: current.settingsExpanded,
            selectedMonitorTab: current.selectedMonitorTab,
            selectedEventsFilter: current.selectedEventsFilter,
            compactWindow: current.compactWindow,
            appearance: current.appearance
        )
        return try settings.normalized().refreshingCredentialStatus(
            cwd: cwd,
            home: home,
            shell: shell,
            permissionStatus: permissionStatus
        )
    }
}

private struct PersistedUIStateFile: Codable {
    let version: Int
    let savedAt: String
    let settings: PersistedUISettings?
    let pushToTalk: PersistedPushToTalkSettings?

    enum CodingKeys: String, CodingKey {
        case version
        case savedAt = "saved_at"
        case settings
        case pushToTalk = "push_to_talk"
    }
}

private struct PersistedPushToTalkSettings: Codable {
    let enabled: Bool
    let hotkey: String
}

private struct PersistedUISettings: Codable {
    let provider: String
    let model: String
    let languages: [String]
    let sampleRate: Int
    let endpointDetection: Bool
    let protocolMode: String
    let refine: Bool
    let translate: Bool
    let clipboard: Bool
    let focusedInput: Bool
    let translationPolicy: String
    let llmEnabled: Bool
    let llmProvider: String
    let llmModel: String
    let hotkeyEnabled: Bool
    let hotkey: String
    let windowWidth: Double?
    let windowHeight: Double?
    let settingsExpanded: Bool?
    let selectedMonitorTab: String?
    let selectedEventsFilter: String?
    let compactWindow: Bool?
    let appearance: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case languages
        case sampleRate
        case endpointDetection
        case protocolMode
        case refine
        case translate
        case clipboard
        case focusedInput
        case translationPolicy
        case llmEnabled
        case llmProvider
        case llmModel
        case hotkeyEnabled
        case hotkey
        case windowWidth
        case windowHeight
        case settingsExpanded
        case selectedMonitorTab
        case selectedEventsFilter
        case compactWindow
        case appearance
    }

    init(settings: UntypeUISettings) {
        self.provider = settings.provider
        self.model = settings.model
        self.languages = settings.languages
        self.sampleRate = settings.sampleRate
        self.endpointDetection = settings.endpointDetection
        self.protocolMode = settings.protocolMode
        self.refine = settings.refine
        self.translate = settings.translate
        self.clipboard = settings.clipboard
        self.focusedInput = settings.focusedInput
        self.translationPolicy = settings.translationPolicy
        self.llmEnabled = settings.llmEnabled
        self.llmProvider = settings.llmProvider
        self.llmModel = settings.llmModel
        self.hotkeyEnabled = settings.hotkeyEnabled
        self.hotkey = settings.hotkey
        self.windowWidth = settings.windowWidth
        self.windowHeight = settings.windowHeight
        self.settingsExpanded = settings.settingsExpanded
        self.selectedMonitorTab = settings.selectedMonitorTab
        self.selectedEventsFilter = settings.selectedEventsFilter
        self.compactWindow = settings.compactWindow
        self.appearance = settings.appearance
    }

    func toRuntimeSettings(path: String) throws -> UntypeUISettings {
        let defaults = UntypeUISettings.default
        do {
            return try UntypeUISettings.default.merged(UntypeUISettingsPatch(
                provider: provider,
                model: model,
                languages: languages,
                sampleRate: sampleRate,
                endpointDetection: endpointDetection,
                protocolMode: protocolMode,
                refine: refine,
                translate: translate,
                clipboard: clipboard,
                focusedInput: focusedInput,
                translationPolicy: translationPolicy,
                llmEnabled: llmEnabled,
                llmProvider: llmProvider,
                llmModel: llmModel,
                hotkeyEnabled: hotkeyEnabled,
                hotkey: hotkey,
                windowWidth: windowWidth ?? defaults.windowWidth,
                windowHeight: windowHeight ?? defaults.windowHeight,
                settingsExpanded: settingsExpanded ?? defaults.settingsExpanded,
                selectedMonitorTab: selectedMonitorTab ?? defaults.selectedMonitorTab,
                selectedEventsFilter: selectedEventsFilter ?? defaults.selectedEventsFilter,
                compactWindow: compactWindow ?? defaults.compactWindow,
                appearance: appearance ?? defaults.appearance
            ))
        } catch {
            throw UntypeError.invalidConfiguration("Invalid UI settings state at \(path): \(error.localizedDescription). Delete or fix \(path).")
        }
    }
}

private func normalizeProvider(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == STTProvider.soniox.rawValue || normalized == STTProvider.elevenlabs.rawValue {
        return normalized
    }
    throw UntypeError.invalidConfiguration("Unsupported STT provider: \(value).")
}

private func normalizeProtocolMode(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if InteractionMode(rawValue: normalized) != nil {
        return normalized
    }
    throw UntypeError.invalidConfiguration("Unsupported protocol mode: \(value).")
}

private func normalizeTranslationPolicy(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if TranslationPolicy(rawValue: normalized) != nil {
        return normalized
    }
    throw UntypeError.invalidConfiguration("Unsupported translation policy: \(value).")
}

private func normalizeLLMProvider(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if LLMProvider(rawValue: normalized) != nil {
        return normalized
    }
    throw UntypeError.invalidConfiguration("Unsupported LLM provider: \(value).")
}

private func normalizeLanguages(_ values: [String]) throws -> [String] {
    let normalized = values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !normalized.isEmpty else {
        throw UntypeError.invalidConfiguration("At least one language hint is required.")
    }
    return normalized
}

private func normalizeNonEmpty(_ value: String, field: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
        throw UntypeError.invalidConfiguration("\(field) must not be empty.")
    }
    return normalized
}

private func normalizeHotkey(_ value: String) throws -> String {
    let separator: Character = value.contains("+") ? "+" : "-"
    let parts = value
        .split(separator: separator)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !parts.isEmpty else {
        throw UntypeError.invalidConfiguration("hotkey must not be empty.")
    }
    var seenModifiers: Set<String> = []
    var modifiers: [String] = []
    var key: String?
    for part in parts {
        let modifier: String?
        switch part.lowercased() {
        case "commandorcontrol", "cmdorctrl", "commandorctrl":
            modifier = "CommandOrControl"
        case "control", "ctrl":
            modifier = "Control"
        case "command", "cmd", "meta", "super":
            modifier = "Command"
        case "option", "alt":
            modifier = "Option"
        case "shift":
            modifier = "Shift"
        default:
            modifier = nil
        }
        if let modifier {
            guard !seenModifiers.contains(modifier) else {
                throw UntypeError.invalidConfiguration("Duplicate hotkey modifier: \(part).")
            }
            seenModifiers.insert(modifier)
            modifiers.append(modifier)
            continue
        }
        guard key == nil else {
            throw UntypeError.invalidConfiguration("hotkey must contain exactly one non-modifier key: \(value).")
        }
        key = try normalizeHotkeyKey(part)
    }
    guard let key else {
        throw UntypeError.invalidConfiguration("hotkey must include a non-modifier key: \(value).")
    }
    if seenModifiers.contains("CommandOrControl") &&
        (seenModifiers.contains("Control") || seenModifiers.contains("Command"))
    {
        throw UntypeError.invalidConfiguration("CommandOrControl cannot be combined with explicit Command or Control modifiers.")
    }
    return (modifiers + [key]).joined(separator: "+")
}

private func normalizeHotkeyKey(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    switch lower {
    case " ", "space", "spacebar":
        return "Space"
    case "`", "grave", "backquote":
        return "`"
    case "'", "apostrophe", "quote", "singlequote":
        return "'"
    case "esc", "escape":
        return "Escape"
    case "return", "enter":
        return "Enter"
    case "tab":
        return "Tab"
    case "del", "delete":
        return "Delete"
    case "backspace":
        return "Backspace"
    case "up", "arrowup":
        return "ArrowUp"
    case "down", "arrowdown":
        return "ArrowDown"
    case "left", "arrowleft":
        return "ArrowLeft"
    case "right", "arrowright":
        return "ArrowRight"
    case "pageup":
        return "PageUp"
    case "pagedown":
        return "PageDown"
    default:
        break
    }
    if trimmed.count == 1,
       let scalar = trimmed.unicodeScalars.first,
       !CharacterSet.whitespacesAndNewlines.contains(scalar)
    {
        return String(trimmed).uppercased()
    }
    let upper = trimmed.uppercased()
    if upper.range(of: #"^F(?:[1-9]|1[0-9]|2[0-4])$"#, options: .regularExpression) != nil {
        return upper
    }
    if trimmed.capitalized == "Home" || trimmed.capitalized == "End" {
        return trimmed.capitalized
    }
    throw UntypeError.invalidConfiguration("Unsupported hotkey key: \(value).")
}

private func normalizeMonitorTab(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "transcript" || normalized == "history" || normalized == "events" {
        return normalized
    }
    throw UntypeError.invalidConfiguration("selectedMonitorTab must be transcript, history, or events. Got: \(value).")
}

private func normalizeEventsFilter(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let allowed: Set<String> = ["all", "warnings", "provider", "audio", "hotkey", "protocol"]
    if allowed.contains(normalized) {
        return normalized
    }
    throw UntypeError.invalidConfiguration("selectedEventsFilter must be one of \(allowed.sorted().joined(separator: ", ")). Got: \(value).")
}

private func normalizeAppearance(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "system" || normalized == "light" || normalized == "dark" {
        return normalized
    }
    throw UntypeError.invalidConfiguration("appearance must be system, light, or dark. Got: \(value).")
}

private func nonEmptyStatus(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func uiSourceLabel(_ source: EnvSource) -> String {
    switch source {
    case .flag:
        return "CLI flag"
    case .localEnv:
        return "local .env"
    case .userEnv:
        return "user .env"
    case .shellEnv:
        return "shell env"
    }
}

private func settingsDiagnosticLine(_ error: Error) -> String {
    if let error = error as? UntypeError {
        return error.diagnosticLine
    }
    return "unknown: \(error.localizedDescription)"
}

private func iso8601Now() -> String {
    ISO8601DateFormatter().string(from: Date())
}
