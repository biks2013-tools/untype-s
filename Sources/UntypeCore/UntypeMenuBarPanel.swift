import AppKit
import SwiftUI

/// The dropdown under the menu-bar icon: the state, the hotkey switches flipped
/// day to day, and the way into the Transcript, History and Settings windows.
///
/// The operator switches are on the screen overlay too. While the overlay is
/// kept on screen (`overlayAlwaysVisible`) the dropdown leaves them to it and
/// only names the ones that are on; otherwise they sit in a second tab.
@MainActor
struct UntypeMenuBarPanel: View {
    @ObservedObject var model: UntypeUIModel
    var openTranscript: () -> Void
    var openHistory: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void

    private enum Tab: Hashable {
        case controls
        case operators
    }

    @State private var selectedTab: Tab = .controls

    /// The operators tab exists only while the overlay is not kept on screen.
    private var showsOperatorsTab: Bool { !model.settings.overlayAlwaysVisible }
    private var tab: Tab { showsOperatorsTab ? selectedTab : .controls }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            if showsOperatorsTab {
                Picker("Section", selection: $selectedTab) {
                    Text("Controls").tag(Tab.controls)
                    Text(operatorsTabTitle).tag(Tab.operators)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            Divider()
            Group {
                switch tab {
                case .controls: controlsSection
                case .operators: operatorsSection
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider()
            VStack(spacing: 0) {
                actionRow("Transcript", systemImage: "text.alignleft", shortcut: "⌘1", action: openTranscript)
                    .keyboardShortcut("1", modifiers: [.command])
                actionRow("History", systemImage: "clock.arrow.circlepath", shortcut: "⌘2", action: openHistory)
                    .keyboardShortcut("2", modifiers: [.command])
                actionRow("New conversation", systemImage: "bubble.left.and.bubble.right", shortcut: "", action: model.startNewAskConversation)
                    .help("Forget the Ask conversation that Follow-up sends along")
                actionRow("Settings…", systemImage: "gearshape", shortcut: "⌘,", action: openSettings)
                    .keyboardShortcut(",", modifiers: [.command])
                Divider()
                    .padding(.vertical, 4)
                actionRow("Quit untype", systemImage: "power", shortcut: "⌘Q", action: quit)
                    .keyboardShortcut("q", modifiers: [.command])
            }
            .padding(6)
            Divider()
            Text("untype \(UntypeAppVersion.current.label)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .help("The version and build of the untype that is running")
        }
        .frame(width: 320)
        .preferredColorScheme(preferredColorScheme)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            UntypeBrandMark(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("untype")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(model.settings.provider) · \(model.settings.llmEnabled ? model.settings.llmProvider : "no LLM")")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                UntypeStatusDot(tone: stateTone, size: 7)
                Text(stateLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(stateTone.color)
                    .tracking(0.6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(stateTone.color.opacity(0.14), in: Capsule(style: .continuous))
        }
    }

    private var stateLabel: String {
        switch model.captureState {
        case "recording": return "RECORDING"
        case "finalizing": return "FINALIZING"
        case "warm": return "READY"
        case "listening": return "LISTENING"
        default: return model.isRunning ? "STARTING" : "IDLE"
        }
    }

    private var stateTone: UntypeStatusTone {
        switch model.captureState {
        case "recording", "listening": return .recording
        case "finalizing": return .warn
        case "warm": return .ok
        default: return .off
        }
    }

    // MARK: Controls

    private static let labelWidth: CGFloat = 52

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                rowLabel("Hotkey")
                UntypeKbd(model.settings.hotkey)
                Spacer(minLength: 6)
                Toggle("Hotkey", isOn: binding(\.hotkeyEnabled) { UntypeUISettingsPatch(hotkeyEnabled: $0) })
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(UntypeDesignTokens.accentAmber)
                    .disabled(!model.canReshapeSession)
            }
            .help(model.canReshapeSession ? "Listen for the global hotkey" : "Locked while a turn or a manual session is running")

            HStack(spacing: 8) {
                rowLabel("Trigger")
                Picker("Hotkey mode", selection: binding(\.hotkeyHoldToTalk) { UntypeUISettingsPatch(hotkeyHoldToTalk: $0) }) {
                    Text("Push-to-talk").tag(true)
                    Text("Push-to-listen").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .help("Push-to-talk: hold the hotkey to record, release to submit. Push-to-listen: press once to start, press again to stop and submit.")

            HStack(spacing: 8) {
                rowLabel("Mode")
                Picker("Protocol mode", selection: binding(\.protocolMode) { UntypeUISettingsPatch(protocolMode: $0) }) {
                    Text("Dictation").tag("dictation")
                    Text("Agent").tag("agent-protocol")
                    Text("Hybrid").tag("hybrid")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!model.canReshapeSession)

            Text(hotkeyHint)
                .font(.system(size: 11))
                .foregroundStyle(model.settings.hotkeyEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(UntypeDesignTokens.warnGold))
                .fixedSize(horizontal: false, vertical: true)

            if model.settings.selectionHotkeyEnabled {
                HStack(spacing: 8) {
                    UntypeKbd(model.settings.selectionHotkey)
                    Text("Push-to-Act on the selected text")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()
            overlaySection
        }
    }

    /// The overlay switch. On, the overlay stays on screen and has the
    /// operator switches, so the dropdown only names the ones that are on.
    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                rowLabel("Overlay")
                Text("Keep on screen")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Toggle("Keep overlay visible", isOn: Binding(
                    get: { model.settings.overlayAlwaysVisible },
                    set: { model.updateLayout(overlayAlwaysVisible: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(UntypeDesignTokens.accentAmber)
            }
            .help("Keep the dictation overlay on screen when you are not dictating. Also in Settings → General.")

            HStack(spacing: 8) {
                Text("Experimental")
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize()
                Text("Operators F, S, W, X")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Toggle("Experimental operators", isOn: Binding(
                    get: { model.settings.experimentalOperators },
                    set: { model.update(UntypeUISettingsPatch(experimentalOperators: $0)) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(UntypeDesignTokens.accentAmber)
            }
            .help("Offer the experimental operators: Follow-up (F), Selection (S), Screenshot (W) and Window text (X). Off: they are switched off and hidden. Also in Settings → Operators.")

            if !showsOperatorsTab {
                operatorsSummary
            }
            Text(showsOperatorsTab
                ? "The overlay appears only while you dictate."
                : "Switch operators on the screen overlay.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private var hotkeyHint: String {
        guard model.settings.hotkeyEnabled else {
            return "The hotkey is off — switch it on to dictate."
        }
        return model.settings.hotkeyHoldToTalk
            ? "Hold the hotkey to record, release to submit."
            : "Press the hotkey to start, press it again to submit."
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .frame(width: Self.labelWidth, alignment: .leading)
    }

    // MARK: Operators

    private struct OperatorEntry {
        let key: OperatorKey
        let letter: String
        let title: String
        let detail: String
        let isOn: Bool
    }

    private var operatorEntries: [OperatorEntry] {
        let s = model.settings
        return allOperatorEntries.filter { s.isAvailable($0.key) }
    }

    private var allOperatorEntries: [OperatorEntry] {
        let s = model.settings
        return [
            OperatorEntry(key: .refine, letter: "R", title: "Refine", detail: "Clean up what was said", isOn: s.refine),
            OperatorEntry(key: .translate, letter: "T", title: "Translate", detail: "Translate the text", isOn: s.translate),
            OperatorEntry(key: .ask, letter: "A", title: "Ask", detail: "Send what was said to the model as a question", isOn: s.ask),
            OperatorEntry(key: .followup, letter: "F", title: "Follow-up", detail: "Continue the Ask conversation", isOn: s.followup),
            OperatorEntry(key: .selection, letter: "S", title: "Selection", detail: "Include the selected text", isOn: s.selection),
            OperatorEntry(key: .alternative, letter: "L", title: "Alternative LLM", detail: "Use the alternative language model", isOn: s.alternative),
            OperatorEntry(key: .screenshot, letter: "W", title: "Screenshot", detail: "Send a screenshot of the app's window", isOn: s.screenshot),
            OperatorEntry(key: .windowText, letter: "X", title: "Window text", detail: "Send the text of the app's window", isOn: s.windowText),
            OperatorEntry(key: .clipboard, letter: "C", title: "Clipboard", detail: "Copy the result to the clipboard", isOn: s.clipboard),
            OperatorEntry(key: .input, letter: "I", title: "Input", detail: "Type the result into the focused input", isOn: s.focusedInput)
        ]
    }

    private var operatorsTabTitle: String {
        let count = operatorEntries.filter(\.isOn).count
        return count == 0 ? "Operators" : "Operators · \(count)"
    }

    private var operatorsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(operatorEntries, id: \.letter) { entry in
                operatorRow(entry)
                if entry.key == .translate, entry.isOn {
                    translationTargetRow
                        .padding(.leading, 26)
                }
            }
            Text("Or hold the hotkey and press the letter.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    /// Shown instead of the operators tab while the overlay is kept on screen.
    private var operatorsSummary: some View {
        let active = operatorEntries.filter(\.isOn)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                rowLabel("On now")
                Text(active.isEmpty ? "No operators" : active.map(\.title).joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(active.isEmpty ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.settings.translate {
                HStack(spacing: 8) {
                    Text("Translate to")
                        .font(.system(size: 12, weight: .medium))
                    translationTargetRow
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var translationTargetRow: some View {
        Picker("Translate to", selection: binding(\.translationPolicy) { UntypeUISettingsPatch(translationPolicy: $0) }) {
            Text("Opposite language").tag("opposite")
            Text("English").tag("to-en")
            Text("Greek").tag("to-el")
        }
        .labelsHidden()
        .controlSize(.small)
        .disabled(!model.canReshapeSession)
        .help("Language Translate turns the text into")
    }

    private func operatorRow(_ entry: OperatorEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.letter)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.isOn ? Color.black.opacity(0.8) : Color.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(entry.isOn ? UntypeDesignTokens.accentAmber : Color.primary.opacity(0.07))
                )
            Text(entry.title)
                .font(.system(size: 12))
            if model.settings.isPerTurn(entry.key) {
                Text("1×")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .help("This turn only: switched off again after each push-to-talk turn")
            }
            Spacer(minLength: 6)
            Toggle(entry.title, isOn: Binding(get: { entry.isOn }, set: { if $0 != entry.isOn { model.toggleOperator(entry.key) } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(UntypeDesignTokens.accentAmber)
        }
        .help("\(entry.detail) (hotkey + \(entry.letter))")
    }

    // MARK: Actions

    private func actionRow(_ title: String, systemImage: String, shortcut: String, action: @escaping () -> Void) -> some View {
        UntypeMenuBarActionRow(title: title, systemImage: systemImage, shortcut: shortcut, action: action)
    }

    // MARK: Helpers

    private func binding<T>(_ keyPath: KeyPath<UntypeUISettings, T>, patch: @escaping (T) -> UntypeUISettingsPatch) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.update(patch($0)) }
        )
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

/// A menu-like row: icon, title, shortcut, highlighted on hover.
private struct UntypeMenuBarActionRow: View {
    let title: String
    let systemImage: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(hovering ? Color.primary : Color.secondary)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? UntypeDesignTokens.accentAmber.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
