import AppKit
import SwiftUI

/// The Settings window: a sidebar of panes (like System Settings), each a
/// grouped form. Opened from the menu-bar dropdown, the main window's gear
/// button or ⌘,.
@MainActor
final class UntypeSettingsWindowController: NSObject {
    private static let frameAutosaveName = "untype.settingsWindow.v2"
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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The sidebar runs to the top of the window, under the traffic
        // lights; the pane title takes the place of the window title.
        window.title = "untype Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UntypeSettingsView(model: model))
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }
}

/// The panes of the Settings window, in sidebar order. The raw value is the
/// `UntypeUIModel.settingsTab` id.
enum UntypeSettingsPane: String, CaseIterable, Identifiable {
    case general
    case pushToTalk = "push-to-talk"
    case pushToAct = "push-to-act"
    case speech
    case operators
    case models
    case prompts
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .pushToTalk: return "Push-to-Talk"
        case .pushToAct: return "Push-to-Act"
        case .speech: return "Speech"
        case .operators: return "Operators"
        case .models: return "Language Models"
        case .prompts: return "Prompts"
        case .permissions: return "Permissions & Keys"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .pushToTalk: return "mic.fill"
        case .pushToAct: return "wand.and.stars"
        case .speech: return "waveform"
        case .operators: return "switch.2"
        case .models: return "brain"
        case .prompts: return "text.bubble.fill"
        case .permissions: return "lock.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .pushToTalk: return .red
        case .pushToAct: return .purple
        case .speech: return .blue
        case .operators: return .orange
        case .models: return .indigo
        case .prompts: return .teal
        case .permissions: return .green
        }
    }

    /// Sidebar groups, System Settings style.
    static let groups: [[UntypeSettingsPane]] = [
        [.general],
        [.pushToTalk, .pushToAct],
        [.speech, .operators, .models, .prompts],
        [.permissions]
    ]
}

@MainActor
struct UntypeSettingsView: View {
    @ObservedObject var model: UntypeUIModel
    @State private var showCredentialsEditor = false
    @State private var showOnboarding = false

    private static let sidebarWidth: CGFloat = 215
    private static let headerHeight: CGFloat = 52

    private var pane: UntypeSettingsPane {
        UntypeSettingsPane(rawValue: model.settingsTab) ?? .general
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
            Divider()
                .ignoresSafeArea()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
        .preferredColorScheme(preferredColorScheme)
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

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding(
            get: { pane },
            set: { model.settingsTab = $0.rawValue }
        )) {
            ForEach(Array(UntypeSettingsPane.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(systemName: item.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                        }
                        .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(pane.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if pane != .prompts, pane != .permissions, pane != .general, !model.canReshapeSession {
                    Label("Some settings are locked while a session is active", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: Self.headerHeight)
            Divider()
            ZStack {
                // Kept alive while other panes show, so unsaved prompt edits
                // survive a visit to another pane.
                UntypePromptSettingsView(model: model)
                    .opacity(pane == .prompts ? 1 : 0)
                    .allowsHitTesting(pane == .prompts)
                    .accessibilityHidden(pane != .prompts)
                if pane != .prompts {
                    Form {
                        paneContent
                    }
                    .formStyle(.grouped)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sessionShapingDisabled: Bool {
        !UntypeUIControlAvailability(isSessionActive: !model.canReshapeSession).sessionShapingControlsEnabled
    }

    private var operatorControlsDisabled: Bool {
        !UntypeUIControlAvailability(isSessionActive: !model.canReshapeSession).protocolOperatorControlsEnabled
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general: generalPane
        case .pushToTalk: pushToTalkPane
        case .pushToAct: pushToActPane
        case .speech: speechPane
        case .operators: operatorsPane
        case .models: modelsPane
        case .permissions: permissionsPane
        case .prompts: EmptyView()
        }
    }

    // MARK: General

    @ViewBuilder
    private var generalPane: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { model.settings.appearance },
                set: { model.updateLayout(appearance: $0) }
            )) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }

        Section {
            Toggle("Keep overlay visible", isOn: Binding(
                get: { model.settings.overlayAlwaysVisible },
                set: { model.updateLayout(overlayAlwaysVisible: $0) }
            ))
            LabeledContent("Position") {
                HStack(spacing: 8) {
                    Text(model.settings.overlayPosition == nil ? "Bottom centre" : "Custom")
                        .foregroundStyle(.secondary)
                    Button("Reset") {
                        model.resetOverlayPosition()
                    }
                    .disabled(model.settings.overlayPosition == nil)
                }
            }
        } header: {
            Text("Dictation overlay")
        } footer: {
            caption("The overlay shows the waveform and the operator chips. Kept visible, the chips can be clicked at any time. Drag its grip to move it; double-click the grip to reset.")
        }

        Section("Current session") {
            LabeledContent("State") {
                status(model.sessionState, tone: UntypeStatusToneMap.session(isRunning: model.isRunning, isHotkeyPressed: model.hotkeyPressed))
            }
            LabeledContent("Audio", value: model.audioStatus)
            LabeledContent("Speech") {
                mono("\(model.settings.provider) · \(model.settings.model)")
            }
            LabeledContent("Languages") {
                mono(model.settings.languages.joined(separator: " · "))
            }
            LabeledContent("Mode") {
                mono(model.settings.protocolMode)
            }
        }
    }

    // MARK: Push-to-Talk

    @ViewBuilder
    private var pushToTalkPane: some View {
        Section {
            Toggle("Enable push-to-talk", isOn: binding(\.hotkeyEnabled))
                .disabled(sessionShapingDisabled)
            LabeledContent("Hotkey") {
                HStack(spacing: 8) {
                    TextField("Hotkey", text: binding(\.hotkey))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                    UntypeKbd(model.settings.hotkey)
                }
            }
            .disabled(sessionShapingDisabled)
            Picker("Recording", selection: binding(\.hotkeyHoldToTalk)) {
                Text("Hold to talk").tag(true)
                Text("Press to start and stop").tag(false)
            }
        } footer: {
            caption(model.settings.hotkeyHoldToTalk
                ? "Push-to-talk: hold the hotkey to record, release to submit."
                : "Push-to-listen: press the hotkey to start, press again to stop and submit.")
        }

        Section {
            Toggle("Quick Close", isOn: binding(\.quickClose))
                .disabled(sessionShapingDisabled)
        } footer: {
            caption("On release, submit the text heard so far without waiting for the speech provider's final transcript. Faster, but the last words can be less accurate.")
        }

        Section("Test") {
            LabeledContent("Listener", value: hotkeyStatus)
            LabeledContent("Try it without the hotkey") {
                Button(model.hotkeyPressed ? "Release Hotkey" : "Press Hotkey") {
                    model.hotkeyPressed
                        ? model.stopHotkeySession(source: "ui-button")
                        : model.startHotkeySession(source: "ui-button")
                }
                .disabled(!model.settings.hotkeyEnabled)
            }
        }
    }

    // MARK: Push-to-Act

    @ViewBuilder
    private var pushToActPane: some View {
        Section {
            Toggle("Enable Push-to-Act", isOn: binding(\.selectionHotkeyEnabled))
            LabeledContent("Hotkey") {
                HStack(spacing: 8) {
                    TextField("Hotkey", text: binding(\.selectionHotkey))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                    UntypeKbd(model.settings.selectionHotkey)
                }
            }
            .disabled(!model.settings.selectionHotkeyEnabled)
        } footer: {
            caption(selectionHotkeyCaption)
        }
        .disabled(sessionShapingDisabled)
    }

    // MARK: Speech

    @ViewBuilder
    private var speechPane: some View {
        Section("Speech recognition") {
            Picker("Provider", selection: binding(\.provider)) {
                Text("Soniox").tag("soniox")
                Text("ElevenLabs").tag("elevenlabs")
            }
            TextField("Model", text: binding(\.model))
            TextField("Languages", text: languagesBinding, prompt: Text("el, en"))
            Stepper(value: sampleRateBinding, in: 8_000...48_000, step: 1_000) {
                LabeledContent("Sample rate", value: "\(model.settings.sampleRate) Hz")
            }
            Toggle("Endpoint detection", isOn: binding(\.endpointDetection))
        }
        .disabled(sessionShapingDisabled)

        Section {
            Picker("Mode", selection: binding(\.protocolMode)) {
                Text("Dictation").tag("dictation")
                Text("Agent").tag("agent-protocol")
                Text("Hybrid").tag("hybrid")
            }
            Toggle("Voice commands", isOn: binding(\.voiceCommands))
        } header: {
            Text("Protocol")
        } footer: {
            caption(model.settings.voiceCommands
                ? "Spoken commands such as “command translate on” or “command send” are recognised."
                : "Spoken commands are ignored: everything you say is dictated text. Use the hotkey letters or the menu to change operators.")
        }
        .disabled(sessionShapingDisabled)
    }

    // MARK: Operators

    @ViewBuilder
    private var operatorsPane: some View {
        Section {
            operatorRow("Refine", "Clean up the dictated text", key: "R", .refine)
            operatorRow("Translate", "Translate the text", key: "T", .translate)
            operatorRow("Ask", "Treat the dictation as a request and insert the answer", key: "A", .ask)
            operatorRow("Follow-up", "Ask continues the conversation", key: "F", .followup)
            operatorRow("Selection", "Include the text selected in the active app", key: "S", .selection)
            operatorRow("Alternative LLM", "Refine, translate and Ask use the alternative model", key: "L", .alternative)
            operatorRow("Screenshot", "Send the app's window; also copied to the clipboard", key: "W", .screenshot)
        } header: {
            Text("Processing")
        } footer: {
            caption("“This turn” switches an operator off again after each push-to-talk turn; “Until changed” keeps it as you set it.")
        }
        .disabled(operatorControlsDisabled)

        Section("Delivery") {
            operatorRow("Clipboard", "Copy the result to the clipboard", key: "C", .clipboard)
            operatorRow("Focused input", "Type the result where the cursor is", key: "I", .input)
        }
        .disabled(operatorControlsDisabled)

        Section("Options") {
            Picker("Selected text is", selection: binding(\.selectionRole)) {
                Text("Material — processed and replaced").tag(SelectionRole.material.rawValue)
                Text("Context — reference only").tag(SelectionRole.context.rawValue)
            }
            .disabled(operatorControlsDisabled)
            Picker("Translate direction", selection: binding(\.translationPolicy)) {
                Text("Opposite").tag("opposite")
                Text("To English").tag("to-en")
                Text("To Greek").tag("to-el")
            }
            .disabled(sessionShapingDisabled)
        }
    }

    /// An operator: its key, what it does, how long a change lasts, and its
    /// current state.
    private func operatorRow(_ label: String, _ detail: String, key: String, _ operatorKey: OperatorKey) -> some View {
        HStack(spacing: 10) {
            UntypeKbd(key)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Picker("Lasts", selection: Binding(
                get: { model.settings.isPerTurn(operatorKey) },
                set: { model.setOperatorPerTurn(operatorKey, $0) }
            )) {
                Text("Until changed").tag(false)
                Text("This turn").tag(true)
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("“This turn”: switched off again after each push-to-talk turn")
            Toggle(label, isOn: Binding(
                get: { model.settings.value(of: operatorKey) },
                set: { model.update(UntypeUISettings.operatorPatch(operatorKey, $0)) }
            ))
            .labelsHidden()
        }
    }

    // MARK: Language models

    @ViewBuilder
    private var modelsPane: some View {
        Section {
            Toggle("Use a language model", isOn: binding(\.llmEnabled))
            Picker("Provider", selection: binding(\.llmProvider)) {
                ForEach(LLMProvider.allCases, id: \.rawValue) { provider in
                    Text(provider.rawValue).tag(provider.rawValue)
                }
            }
            TextField("Model", text: binding(\.llmModel))
        } header: {
            Text("Primary")
        } footer: {
            caption("Used by refine, translate and Ask. API keys are set in Permissions & Keys.")
        }
        .disabled(sessionShapingDisabled)

        Section {
            Picker("Provider", selection: binding(\.altLlmProvider)) {
                Text("None").tag("")
                ForEach(LLMProvider.allCases, id: \.rawValue) { provider in
                    Text(provider.rawValue).tag(provider.rawValue)
                }
            }
            TextField("Model", text: binding(\.altLlmModel))
        } header: {
            Text("Alternative")
        } footer: {
            caption(alternativeLLMCaption)
        }
        .disabled(sessionShapingDisabled)

        Section {
            Picker("Provider", selection: binding(\.alt2LlmProvider)) {
                Text("None").tag("")
                ForEach(LLMProvider.allCases, id: \.rawValue) { provider in
                    Text(provider.rawValue).tag(provider.rawValue)
                }
            }
            TextField("Model", text: binding(\.alt2LlmModel))
        } header: {
            Text("Alternative 2 (Push-to-Act)")
        } footer: {
            caption(alternative2LLMCaption)
        }
        .disabled(sessionShapingDisabled)
    }

    // MARK: Permissions & keys

    @ViewBuilder
    private var permissionsPane: some View {
        Section {
            permissionRow(
                "Microphone",
                value: model.settings.microphoneStatus,
                tone: UntypeStatusToneMap.microphone(model.settings.microphoneStatus),
                deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )
            permissionRow(
                "Accessibility",
                value: model.settings.accessibilityStatus,
                tone: UntypeStatusToneMap.accessibility(model.settings.accessibilityStatus),
                deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
            permissionRow(
                "Input Monitoring",
                value: model.settings.inputStatus,
                tone: model.settings.focusedInput ? .accent : .off,
                deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )
            LabeledContent("Step-by-step guide") {
                Button("Open Permission Setup…") {
                    model.refreshCredentials()
                    showOnboarding = true
                }
            }
        } header: {
            Text("macOS permissions")
        }

        Section {
            LabeledContent(model.settings.apiKeyName) {
                status(model.settings.apiKeyStatus, tone: UntypeStatusToneMap.credential(model.settings.apiKeyStatus))
            }
            LabeledContent("Source") {
                mono(model.settings.storageStatus)
            }
            LabeledContent("Expiry") {
                mono(model.settings.expiryStatus)
            }
            LabeledContent("Provider keys") {
                Button("Edit Keys…") {
                    showCredentialsEditor = true
                }
            }
        } header: {
            Text("API keys")
        } footer: {
            caption("Keys are stored in ~/.tool-agents/untype/.env, readable only by you.")
        }
    }

    private func permissionRow(_ label: String, value: String, tone: UntypeStatusTone, deepLink: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                status(value, tone: tone)
                if tone == .warn {
                    Button("Open System Settings") {
                        if let url = URL(string: deepLink) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: Row pieces

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func status(_ value: String, tone: UntypeStatusTone) -> some View {
        HStack(spacing: 6) {
            UntypeStatusDot(tone: tone, size: 7)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func mono(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var selectionHotkeyCaption: String {
        if !model.settings.hotkeyEnabled {
            return "Needs the push-to-talk hotkey listener: enable Push to talk."
        }
        return "Select text in any app and press the hotkey: a pop-up shows the model (primary, Alternative, Alternative 2), the operators and the translation direction (L switches model, letters toggle, 1–3 translate to a language and turn Translate on). Enter runs and the result replaces the selection; Esc cancels. Push-to-Act remembers its own choices for next time, separately from the push-to-talk operators. No recording."
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

    private var alternativeLLMCaption: String {
        let settings = model.settings
        if settings.altLlmProvider.isEmpty {
            return "Not configured. With the Alternative operator (L) on, refine, translate and Ask then do not call any LLM."
        }
        if settings.altLlmModel.isEmpty {
            return "Set the model to use the alternative LLM (for azure-openai, the deployment name)."
        }
        return "With the Alternative operator (L) on, refine, translate and Ask use \(settings.altLlmProvider) / \(settings.altLlmModel), with the same prompts and the provider's keys from Permissions & Keys."
    }

    private var alternative2LLMCaption: String {
        let settings = model.settings
        if settings.alt2LlmProvider.isEmpty {
            return "Not configured. A second model the Push-to-Act pop-up can pick (L cycles the models)."
        }
        if settings.alt2LlmModel.isEmpty {
            return "Set the model to use the second alternative LLM (for azure-openai, the deployment name)."
        }
        return "The Push-to-Act pop-up can run refine, translate and Ask with \(settings.alt2LlmProvider) / \(settings.alt2LlmModel), with the same prompts and the provider's keys from Permissions & Keys."
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
        case \UntypeUISettings.altLlmProvider:
            return UntypeUISettingsPatch(altLlmProvider: value as? String)
        case \UntypeUISettings.altLlmModel:
            return UntypeUISettingsPatch(altLlmModel: value as? String)
        case \UntypeUISettings.alt2LlmProvider:
            return UntypeUISettingsPatch(alt2LlmProvider: value as? String)
        case \UntypeUISettings.alt2LlmModel:
            return UntypeUISettingsPatch(alt2LlmModel: value as? String)
        case \UntypeUISettings.alternative:
            return UntypeUISettingsPatch(alternative: value as? Bool)
        case \UntypeUISettings.screenshot:
            return UntypeUISettingsPatch(screenshot: value as? Bool)
        case \UntypeUISettings.voiceCommands:
            return UntypeUISettingsPatch(voiceCommands: value as? Bool)
        case \UntypeUISettings.hotkeyEnabled:
            return UntypeUISettingsPatch(hotkeyEnabled: value as? Bool)
        case \UntypeUISettings.hotkeyHoldToTalk:
            return UntypeUISettingsPatch(hotkeyHoldToTalk: value as? Bool)
        case \UntypeUISettings.hotkey:
            return UntypeUISettingsPatch(hotkey: value as? String)
        case \UntypeUISettings.selectionHotkeyEnabled:
            return UntypeUISettingsPatch(selectionHotkeyEnabled: value as? Bool)
        case \UntypeUISettings.selectionHotkey:
            return UntypeUISettingsPatch(selectionHotkey: value as? String)
        default:
            return UntypeUISettingsPatch()
        }
    }
}
