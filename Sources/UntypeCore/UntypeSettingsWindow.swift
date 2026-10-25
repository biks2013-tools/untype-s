import AppKit
import SwiftUI

/// The Settings window: every setting (formerly the main window's inspector)
/// and the editable prompt files. Opened from the menu-bar dropdown, the main
/// window's gear button or ⌘,.
@MainActor
final class UntypeSettingsWindowController: NSObject {
    private static let frameAutosaveName = "untype.settingsWindow"
    private let model: UntypeUIModel
    private var window: NSWindow?

    init(model: UntypeUIModel) {
        self.model = model
    }

    func show(tab: String?) {
        if let tab {
            model.settingsTab = tab
        }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "untype Settings"
        window.contentMinSize = NSSize(width: 660, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UntypeSettingsView(model: model))
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }
}

@MainActor
struct UntypeSettingsView: View {
    @ObservedObject var model: UntypeUIModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            ScrollView {
                UntypeSettingsGeneralView(model: model)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag("general")

            UntypePromptSettingsView(model: model)
                .tabItem { Label("Prompts", systemImage: "text.bubble") }
                .tag("prompts")
        }
        .padding(.top, 8)
        .frame(minWidth: 660, minHeight: 520)
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

// MARK: - General

/// Provider, protocol, operators, LLM, push-to-talk, permissions and
/// credentials. Session-shaping controls are editable while idle or while the
/// hotkey session is only warm (`UntypeUIModel.canReshapeSession`).
@MainActor
private struct UntypeSettingsGeneralView: View {
    @ObservedObject var model: UntypeUIModel
    @State private var showCredentialsEditor = false
    @State private var showOnboarding = false

    var body: some View {
        let availability = UntypeUIControlAvailability(isSessionActive: !model.canReshapeSession)
        let sessionShapingDisabled = !availability.sessionShapingControlsEnabled
        let operatorControlsDisabled = !availability.protocolOperatorControlsEnabled

        return VStack(alignment: .leading, spacing: 14) {
                // Session — read-only summary
                inspectorGroup("Session", accessory: {
                    Button {
                        showCredentialsEditor = true
                    } label: {
                        Label("Edit keys…", systemImage: "key")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Set provider API keys; stored in ~/.tool-agents/untype/.env")
                }) {
                    inspectorStatusRow("State", value: model.sessionState, tone: UntypeStatusToneMap.session(isRunning: model.isRunning, isHotkeyPressed: model.hotkeyPressed))
                    inspectorMonoRow("Mode", value: model.settings.protocolMode)
                    inspectorMonoRow("STT provider", value: model.settings.provider)
                    inspectorMonoRow("Model", value: model.settings.model)
                    inspectorMonoRow("Languages", value: model.settings.languages.joined(separator: " · "))
                    inspectorMonoRow("Sample rate", value: "\(model.settings.sampleRate) Hz")
                    inspectorMonoRow("Endpoint detection", value: model.settings.endpointDetection ? "on" : "off")
                    inspectorMonoRow("Quick Close", value: model.settings.quickClose ? "on" : "off")
                    inspectorMonoRow("Audio", value: model.audioStatus)
                }

                // Appearance — layout setting, never locked
                inspectorGroup("Appearance") {
                    inspectorFieldRow("Theme") {
                        Picker("", selection: Binding(
                            get: { model.settings.appearance },
                            set: { model.updateLayout(appearance: $0) }
                        )) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                // Provider
                inspectorGroup("Provider") {
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorFieldRow("STT") {
                            Picker("", selection: binding(\.provider)) {
                                Text("Soniox").tag("soniox")
                                Text("ElevenLabs").tag("elevenlabs")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        inspectorFieldRow("Model") {
                            TextField("", text: binding(\.model))
                                .textFieldStyle(.roundedBorder)
                        }
                        inspectorFieldRow("Languages") {
                            TextField("", text: languagesBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                        inspectorFieldRow("Sample") {
                            Stepper("\(model.settings.sampleRate) Hz", value: sampleRateBinding, in: 8_000...48_000, step: 1_000)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        inspectorToggleRow("Endpoint detection", isOn: binding(\.endpointDetection))
                    }
                    .disabled(sessionShapingDisabled)
                }

                // Protocol
                inspectorGroup("Protocol") {
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorFieldRow("Mode") {
                            Picker("", selection: binding(\.protocolMode)) {
                                Text("Dictation").tag("dictation")
                                Text("Agent").tag("agent-protocol")
                                Text("Hybrid").tag("hybrid")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(sessionShapingDisabled)
                        inspectorFieldRow("Translate") {
                            Picker("", selection: binding(\.translationPolicy)) {
                                Text("Opposite").tag("opposite")
                                Text("To English").tag("to-en")
                                Text("To Greek").tag("to-el")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(sessionShapingDisabled)
                    }
                }

                // Operators — always editable
                inspectorGroup("Operators") {
                    VStack(alignment: .leading, spacing: 6) {
                        operatorSettingRow("Refine", .refine)
                        operatorSettingRow("Translate", .translate)
                        operatorSettingRow("Ask (answer the request)", .ask)
                        operatorSettingRow("Follow-up (Ask continues the conversation)", .followup)
                        operatorSettingRow("Selection (include the selected text)", .selection)
                        inspectorFieldRow("Selected text is") {
                            Picker("Selected text is", selection: binding(\.selectionRole)) {
                                Text("Material — processed and replaced").tag(SelectionRole.material.rawValue)
                                Text("Context — reference only").tag(SelectionRole.context.rawValue)
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        operatorSettingRow("Clipboard", .clipboard)
                        operatorSettingRow("Focused input", .input)
                        Text("“This turn” switches an operator off again after each push-to-talk turn; “Until changed” keeps it as you set it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .disabled(operatorControlsDisabled)
                }

                // LLM
                inspectorGroup("Refinement (LLM)") {
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorToggleRow("Enabled", isOn: binding(\.llmEnabled))
                        inspectorFieldRow("Provider") {
                            Picker("", selection: binding(\.llmProvider)) {
                                ForEach(LLMProvider.allCases, id: \.rawValue) { provider in
                                    Text(provider.rawValue).tag(provider.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        inspectorFieldRow("Model") {
                            TextField("", text: binding(\.llmModel))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .disabled(sessionShapingDisabled)
                }

                // Push to talk
                inspectorGroup("Push to talk") {
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorToggleRow("Enabled", isOn: binding(\.hotkeyEnabled))
                            .disabled(sessionShapingDisabled)
                        inspectorFieldRow("Hotkey") {
                            HStack(spacing: 6) {
                                TextField("", text: binding(\.hotkey))
                                    .textFieldStyle(.roundedBorder)
                                UntypeKbd(model.settings.hotkey)
                            }
                        }
                        .disabled(sessionShapingDisabled)
                        inspectorToggleRow("Hold to talk", isOn: binding(\.hotkeyHoldToTalk))
                        Text(model.settings.hotkeyHoldToTalk
                             ? "Push-to-talk: hold the hotkey to record, release to submit."
                             : "Push-to-listen: press the hotkey to start, press again to stop and submit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        inspectorToggleRow("Quick Close", isOn: binding(\.quickClose))
                            .disabled(sessionShapingDisabled)
                        inspectorFieldRow("Action") {
                            Button(model.hotkeyPressed ? "Release Hotkey" : "Press Hotkey") {
                                model.hotkeyPressed
                                    ? model.stopHotkeySession(source: "ui-button")
                                    : model.startHotkeySession(source: "ui-button")
                            }
                            .disabled(!model.settings.hotkeyEnabled)
                        }
                        Text(hotkeyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Permissions — deep links into System Settings when not OK
                inspectorGroup("Permissions") {
                    VStack(alignment: .leading, spacing: 6) {
                        inspectorPermissionRow(
                            label: "Microphone",
                            value: model.settings.microphoneStatus,
                            tone: UntypeStatusToneMap.microphone(model.settings.microphoneStatus),
                            deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                        )
                        inspectorPermissionRow(
                            label: "Accessibility",
                            value: model.settings.accessibilityStatus,
                            tone: UntypeStatusToneMap.accessibility(model.settings.accessibilityStatus),
                            deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        )
                        inspectorPermissionRow(
                            label: "Input monitoring",
                            value: model.settings.inputStatus,
                            tone: model.settings.focusedInput ? .accent : .off,
                            deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                        )
                        Button {
                            model.refreshCredentials()
                            showOnboarding = true
                        } label: {
                            Label("Open Permission Setup", systemImage: "lock.shield")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .help("Open permission setup")
                    }
                }

                // Credentials
                inspectorGroup("Credentials") {
                    VStack(alignment: .leading, spacing: 6) {
                        inspectorStatusRow(model.settings.apiKeyName, value: model.settings.apiKeyStatus, tone: UntypeStatusToneMap.credential(model.settings.apiKeyStatus))
                        inspectorMonoRow("Source", value: model.settings.storageStatus)
                        inspectorMonoRow("Expiry", value: model.settings.expiryStatus)
                        if model.settings.storageStatus.lowercased().contains(".env") || model.settings.storageStatus.lowercased().contains("user") {
                            Text("~/.tool-agents/untype/.env")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCredentialsEditor) {
            UntypeCredentialsEditorView(model: model) {
                showCredentialsEditor = false
            }
        }
        .sheet(isPresented: $showOnboarding) {
            UntypeOnboardingView(model: model) {
                showOnboarding = false
            }
        }
    }

    private func inspectorGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        inspectorGroup(title, accessory: { EmptyView() }, content: content)
    }

    /// Inspector group whose header row carries a trailing accessory (e.g. a
    /// small action button aligned to the right of the title).
    private func inspectorGroup<Accessory: View, Content: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                UntypeSectionHeader(title)
                Spacer(minLength: 8)
                accessory()
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    /// An operator: how long a change lasts, and its current state.
    private func operatorSettingRow(_ label: String, _ key: OperatorKey) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer(minLength: 6)
            Picker("Lasts", selection: Binding(
                get: { model.settings.isPerTurn(key) },
                set: { model.setOperatorPerTurn(key, $0) }
            )) {
                Text("Until changed").tag(false)
                Text("This turn").tag(true)
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("“This turn”: switched off again after each push-to-talk turn")
            Toggle("", isOn: Binding(
                get: { model.settings.value(of: key) },
                set: { model.update(UntypeUISettings.operatorPatch(key, $0)) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorToggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer(minLength: 6)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorFieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorStatusRow(_ label: String, value: String, tone: UntypeStatusTone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                UntypeStatusDot(tone: tone, size: 7)
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inspectorMonoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inspectorPermissionRow(label: String, value: String, tone: UntypeStatusTone, deepLink: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            HStack(spacing: 6) {
                UntypeStatusDot(tone: tone, size: 7)
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if tone == .warn {
                    Button {
                        if let url = URL(string: deepLink) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open System Settings")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hotkeyStatus: String {
        if !model.settings.hotkeyEnabled {
            return "Disabled"
        }
        if model.hotkeyMonitorStatus != "disabled" {
            return model.hotkeyMonitorStatus
        }
        return "Accessibility/Input Monitoring may be required for release detection"
    }

    private var languagesBinding: Binding<String> {
        Binding(
            get: { model.settings.languages.joined(separator: ", ") },
            set: { value in
                model.update(UntypeUISettingsPatch(languages: value.split(separator: ",").map { String($0) }))
            }
        )
    }

    private var sampleRateBinding: Binding<Int> {
        Binding(
            get: { model.settings.sampleRate },
            set: { model.update(UntypeUISettingsPatch(sampleRate: $0)) }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<UntypeUISettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.update(patch(for: keyPath, value: value))
            }
        )
    }

    private func patch<T>(for keyPath: WritableKeyPath<UntypeUISettings, T>, value: T) -> UntypeUISettingsPatch {
        switch keyPath {
        case \UntypeUISettings.provider:
            return UntypeUISettingsPatch(provider: value as? String)
        case \UntypeUISettings.model:
            return UntypeUISettingsPatch(model: value as? String)
        case \UntypeUISettings.endpointDetection:
            return UntypeUISettingsPatch(endpointDetection: value as? Bool)
        case \UntypeUISettings.quickClose:
            return UntypeUISettingsPatch(quickClose: value as? Bool)
        case \UntypeUISettings.protocolMode:
            return UntypeUISettingsPatch(protocolMode: value as? String)
        case \UntypeUISettings.refine:
            return UntypeUISettingsPatch(refine: value as? Bool)
        case \UntypeUISettings.translate:
            return UntypeUISettingsPatch(translate: value as? Bool)
        case \UntypeUISettings.clipboard:
            return UntypeUISettingsPatch(clipboard: value as? Bool)
        case \UntypeUISettings.focusedInput:
            return UntypeUISettingsPatch(focusedInput: value as? Bool)
        case \UntypeUISettings.ask:
            return UntypeUISettingsPatch(ask: value as? Bool)
        case \UntypeUISettings.selectionRole:
            return UntypeUISettingsPatch(selectionRole: value as? String)
        case \UntypeUISettings.translationPolicy:
            return UntypeUISettingsPatch(translationPolicy: value as? String)
        case \UntypeUISettings.llmEnabled:
            return UntypeUISettingsPatch(llmEnabled: value as? Bool)
        case \UntypeUISettings.llmProvider:
            return UntypeUISettingsPatch(llmProvider: value as? String)
        case \UntypeUISettings.llmModel:
            return UntypeUISettingsPatch(llmModel: value as? String)
        case \UntypeUISettings.hotkeyEnabled:
            return UntypeUISettingsPatch(hotkeyEnabled: value as? Bool)
        case \UntypeUISettings.hotkeyHoldToTalk:
            return UntypeUISettingsPatch(hotkeyHoldToTalk: value as? Bool)
        case \UntypeUISettings.hotkey:
            return UntypeUISettingsPatch(hotkey: value as? String)
        default:
            return UntypeUISettingsPatch()
        }
    }
}
