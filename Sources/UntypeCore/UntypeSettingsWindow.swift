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
    case meetings
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
        case .meetings: return "Meetings"
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
        case .meetings: return "person.2.wave.2.fill"
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
        case .meetings: return .pink
        case .speech: return .blue
        case .operators: return .orange
        case .models: return .indigo
        case .prompts: return .teal
        case .permissions: return .green
        }
    }

    /// What the pane is for, shown under its title.
    var summary: String {
        switch self {
        case .general: return "Appearance, the dictation overlay and the state of the session"
        case .pushToTalk: return "The hotkey you hold or tap to dictate"
        case .pushToAct: return "The hotkey that works on the text you selected"
        case .meetings: return "Recording both sides of a call: transcript, audio, files and calendar"
        case .speech: return "The speech recogniser and how what you say is understood"
        case .operators: return "What happens to the dictated text and where it goes"
        case .models: return "The models behind Refine, Translate and Ask"
        case .prompts: return "The instructions the language model gets"
        case .permissions: return "What macOS lets untype do, and the provider keys"
        }
    }

    /// Panes with settings that cannot change while a session is active.
    var locksWhileSessionActive: Bool {
        switch self {
        case .pushToTalk, .pushToAct, .speech, .operators, .models: return true
        case .general, .meetings, .prompts, .permissions: return false
        }
    }

    /// Sidebar groups, System Settings style: the app, the ways of using
    /// it, how the text is made, access.
    static let groups: [[UntypeSettingsPane]] = [
        [.general],
        [.pushToTalk, .pushToAct, .meetings],
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("untype \(UntypeAppVersion.current.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .help("The version and build of the untype that is running")
        }
        .background(.regularMaterial)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(pane.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(pane.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                if pane.locksWhileSessionActive, !model.canReshapeSession {
                    Label("Locked while a session is active", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .help("Some settings of this pane cannot change while a session is active")
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
        case .meetings: meetingsPane
        case .speech: speechPane
        case .operators: operatorsPane
        case .models: modelsPane
        case .permissions: permissionsPane
        case .prompts: EmptyView()
        }
    }

    private func chooseMeetingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.settings.meeting.folderURL
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        var meeting = model.settings.meeting
        meeting.folder = url.path
        model.setMeetingPreferences(meeting)
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
            caption("The overlay shows the waveform and the operator chips. Kept visible, the chips can be clicked at any time. Hover it for the tray: drag the tray to move the overlay; double-click it to reset.")
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

    // MARK: Meetings

    private func meetingBinding<T>(_ keyPath: WritableKeyPath<MeetingPreferences, T>) -> Binding<T> {
        Binding(
            get: { model.settings.meeting[keyPath: keyPath] },
            set: { value in
                var meeting = model.settings.meeting
                meeting[keyPath: keyPath] = value
                model.setMeetingPreferences(meeting)
            }
        )
    }

    private var meetingAudioSources: String {
        model.settings.meeting.audioSources ?? MeetingAudioSources.both.rawValue
    }

    @ViewBuilder
    private var meetingsPane: some View {
        Section {
            Picker("Language", selection: meetingBinding(\.language)) {
                ForEach(MeetingTranscriptLanguage.allCases, id: \.rawValue) { language in
                    Text(language.title).tag(language.rawValue)
                }
            }
            LabeledContent("Transcription window") {
                Button("Open") {
                    model.showTranscriptionWindow?()
                }
            }
        } header: {
            Text("Transcript")
        } footer: {
            caption("Hover the overlay and click ⏺ to record both sides of a call: your microphone and the call's sound. The transcript always covers both sides; the transcription window shows it live.")
        }

        Section {
            Picker("Save audio", selection: Binding(
                get: { meetingAudioSources },
                set: { value in
                    var meeting = model.settings.meeting
                    meeting.audioSources = value
                    model.setMeetingPreferences(meeting)
                }
            )) {
                ForEach(MeetingAudioSources.allCases, id: \.rawValue) { sources in
                    Text(sources.title).tag(sources.rawValue)
                }
            }
            if meetingAudioSources == MeetingAudioSources.both.rawValue {
                Picker("Audio files", selection: Binding(
                    get: { model.settings.meeting.audioLayout ?? MeetingAudioLayout.separate.rawValue },
                    set: { value in
                        var meeting = model.settings.meeting
                        meeting.audioLayout = value
                        model.setMeetingPreferences(meeting)
                    }
                )) {
                    ForEach(MeetingAudioLayout.allCases, id: \.rawValue) { layout in
                        Text(layout.title).tag(layout.rawValue)
                    }
                }
            }
            Toggle("Remove speaker sound from the microphone", isOn: Binding(
                get: { model.settings.meeting.removesSpeakerSound },
                set: { value in
                    var meeting = model.settings.meeting
                    meeting.echoCancellation = value
                    model.setMeetingPreferences(meeting)
                }
            ))
        } header: {
            Text("Audio")
        } footer: {
            caption("Saved next to the transcript as .mic.m4a and .system.m4a, or one .m4a when mixed (AAC, speech quality). Without headphones the microphone also hears the call from the loudspeakers: “Remove speaker sound” takes it out of the microphone's audio and transcript (Apple voice processing, which also reduces noise and evens out your voice). It applies from the next recording; while such a recording runs, dictation uses the meeting's microphone.")
        }

        Section {
            Toggle("Mute the microphone while dictating", isOn: Binding(
                get: { model.settings.meeting.mutesMicrophoneWhileDictating },
                set: { value in
                    var meeting = model.settings.meeting
                    meeting.muteWhileDictating = value
                    model.setMeetingPreferences(meeting)
                }
            ))
        } header: {
            Text("Dictation during a meeting")
        } footer: {
            caption(model.settings.meeting.mutesMicrophoneWhileDictating
                ? "Push-to-talk and Push-to-Act work while a meeting is recorded. On: during a push-to-talk turn the meeting gets silence from your microphone, so what you dictate stays out of the transcript, the transcription window and the saved audio. The call's side is still recorded. This does not mute you in the call itself: do that in Teams or Zoom."
                : "Push-to-talk and Push-to-Act work while a meeting is recorded. Off: what you dictate is also recorded in the meeting, as your side of the conversation.")
        }

        Section {
            LabeledContent("Folder") {
                HStack(spacing: 8) {
                    Text(model.settings.meeting.folderURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        chooseMeetingFolder()
                    }
                    Button("Open") {
                        model.openMeetingsFolder()
                    }
                }
            }
        } header: {
            Text("Files")
        } footer: {
            caption("Each meeting gets its own folder, recording-<date>-<time>, with the meeting's name in front once it has one. Its files are named as the ntakker recorder names them and are written while the meeting runs.")
        }

        Section {
            LabeledContent("Stop after silence") {
                HStack(spacing: 8) {
                    Text(model.settings.meeting.silenceMinutes == 0 ? "Off" : "\(model.settings.meeting.silenceMinutes) min")
                        .foregroundStyle(.secondary)
                    Stepper("Stop after silence", value: meetingBinding(\.silenceMinutes), in: 0...60)
                        .labelsHidden()
                }
            }
        } header: {
            Text("Ending")
        } footer: {
            caption("The recording stops by itself when neither side has spoken for this long. Off: it runs until you stop it.")
        }

        Section {
            Toggle("Use my Outlook calendar", isOn: Binding(
                get: { model.settings.meeting.calendarCLIURL != nil },
                set: { model.setCalendarEnabled($0) }
            ))
            if !model.calendarStatus.isEmpty {
                LabeledContent("Status") {
                    Text(model.calendarStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            caption("Read through the nbg-m365 CLI. The overlay says when a Teams meeting you accepted starts, with a Record button; a recording made during a meeting is named after it, its required participants listed at the top of the transcript.")
        }

        Section("Permission") {
            permissionRow(
                "Screen & System Audio Recording",
                value: screenRecordingGranted ? "Granted" : "Not granted",
                tone: screenRecordingGranted ? .ok : .warn,
                deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        }
    }

    /// Needed to hear the call's sound (and for the Screenshot operator).
    private var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
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
        } footer: {
            caption("Hold the hotkey to record and release to submit. Tap it to keep recording hands-free, then press Enter to type the text and send it, the hotkey to type it only, or Esc to discard.")
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
            LabeledContent("Sample rate") {
                HStack(spacing: 8) {
                    Text(verbatim: "\(model.settings.sampleRate) Hz")
                        .foregroundStyle(.secondary)
                    Stepper("Sample rate", value: sampleRateBinding, in: 8_000...48_000, step: 1_000)
                        .labelsHidden()
                }
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
            operatorRow("Alternative LLM", "Refine, translate and Ask use the alternative model", key: "L", .alternative)
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

        Section("Translation") {
            Picker("Direction", selection: binding(\.translationPolicy)) {
                Text("Opposite").tag("opposite")
                Text("To English").tag("to-en")
                Text("To Greek").tag("to-el")
            }
            .disabled(sessionShapingDisabled)
        }

        Section {
            Toggle("Experimental operators", isOn: binding(\.experimentalOperators))
            if model.settings.experimentalOperators {
                operatorRow("Follow-up", "Ask continues the conversation", key: "F", .followup)
                operatorRow("Selection", "Include the text selected in the active app", key: "S", .selection)
                operatorRow("Screenshot", "Send the app's window; also copied to the clipboard", key: "W", .screenshot)
                operatorRow("Window text", "Send the text of the app's window, also what is scrolled out of view", key: "X", .windowText)
                Picker("Selected text is", selection: binding(\.selectionRole)) {
                    Text("Material — processed and replaced").tag(SelectionRole.material.rawValue)
                    Text("Context — reference only").tag(SelectionRole.context.rawValue)
                }
            }
        } header: {
            Text("Experimental")
        } footer: {
            caption(model.settings.experimentalOperators
                ? "Follow-up, Selection, Screenshot and Window text are still being worked on and may change."
                : "Off: Follow-up (F), Selection (S), Screenshot (W) and Window text (X) are switched off and not shown in the overlay, the menu or the hotkey letters.")
        }
        .disabled(operatorControlsDisabled)
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
            permissionRow(
                "Screen & System Audio Recording",
                value: screenRecordingGranted ? "Granted" : "Not granted (meetings, Screenshot)",
                tone: screenRecordingGranted ? .ok : .off,
                deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
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
        case \UntypeUISettings.windowText:
            return UntypeUISettingsPatch(windowText: value as? Bool)
        case \UntypeUISettings.experimentalOperators:
            return UntypeUISettingsPatch(experimentalOperators: value as? Bool)
        case \UntypeUISettings.voiceCommands:
            return UntypeUISettingsPatch(voiceCommands: value as? Bool)
        case \UntypeUISettings.hotkeyEnabled:
            return UntypeUISettingsPatch(hotkeyEnabled: value as? Bool)
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
