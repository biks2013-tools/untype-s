import AppKit
import SwiftUI

/// The dropdown under the menu-bar icon: only the switches flipped day to day
/// (hotkey, push-to-talk / push-to-listen, protocol mode, operators,
/// translation target), the hotkeys, and the way into the Transcript, History
/// and Settings windows.
@MainActor
struct UntypeMenuBarPanel: View {
    @ObservedObject var model: UntypeUIModel
    var openTranscript: () -> Void
    var openHistory: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                pushToTalkSection
                Divider()
                operatorsSection
                Divider()
                hotkeysSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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

    // MARK: Push-to-talk and mode

    private var pushToTalkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Hotkey")
                    .font(.system(size: 12, weight: .medium))
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

            Picker("Hotkey mode", selection: binding(\.hotkeyHoldToTalk) { UntypeUISettingsPatch(hotkeyHoldToTalk: $0) }) {
                Text("Push-to-talk").tag(true)
                Text("Push-to-listen").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Push-to-talk: hold the hotkey to record, release to submit. Push-to-listen: press once to start, press again to stop and submit.")

            HStack(spacing: 8) {
                Text("Mode")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 44, alignment: .leading)
                Picker("Protocol mode", selection: binding(\.protocolMode) { UntypeUISettingsPatch(protocolMode: $0) }) {
                    Text("Dictation").tag("dictation")
                    Text("Agent").tag("agent-protocol")
                    Text("Hybrid").tag("hybrid")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .disabled(!model.canReshapeSession)

            HStack(spacing: 8) {
                Text("Theme")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 44, alignment: .leading)
                Picker("Appearance", selection: Binding(
                    get: { model.settings.appearance },
                    set: { model.updateLayout(appearance: $0) }
                )) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon.fill").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Appearance of untype's windows, dropdown and overlay")
            }
        }
    }

    // MARK: Operators

    private var operatorsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Operators", trailing: "hotkey + key")
            operatorRow("Refine", key: "R", isOn: model.settings.refine, perTurn: model.settings.isPerTurn(.refine)) { model.toggleOperator(.refine) }
            operatorRow("Translate", key: "T", isOn: model.settings.translate, perTurn: model.settings.isPerTurn(.translate)) { model.toggleOperator(.translate) }
            if model.settings.translate {
                HStack(spacing: 8) {
                    Text("to")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                    Picker("Translate to", selection: binding(\.translationPolicy) { UntypeUISettingsPatch(translationPolicy: $0) }) {
                        Text("Opposite language").tag("opposite")
                        Text("English").tag("to-en")
                        Text("Greek").tag("to-el")
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(!model.canReshapeSession)
                }
            }
            operatorRow("Ask the model", key: "A", isOn: model.settings.ask, perTurn: model.settings.isPerTurn(.ask)) { model.toggleOperator(.ask) }
            operatorRow("Follow-up (continue the conversation)", key: "F", isOn: model.settings.followup, perTurn: model.settings.isPerTurn(.followup)) { model.toggleOperator(.followup) }
            operatorRow("Include selected text", key: "S", isOn: model.settings.selection, perTurn: model.settings.isPerTurn(.selection)) { model.toggleOperator(.selection) }
            operatorRow("Clipboard", key: "C", isOn: model.settings.clipboard, perTurn: model.settings.isPerTurn(.clipboard)) { model.toggleOperator(.clipboard) }
            operatorRow("Type into focused input", key: "I", isOn: model.settings.focusedInput, perTurn: model.settings.isPerTurn(.input)) { model.toggleOperator(.input) }
        }
    }

    private func operatorRow(_ title: String, key: String, isOn: Bool, perTurn: Bool, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isOn ? Color.black.opacity(0.8) : Color.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? UntypeDesignTokens.accentAmber : Color.primary.opacity(0.07))
                )
            Text(title)
                .font(.system(size: 12))
            if perTurn {
                Text("1×")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .help("This turn only: switched off again after each push-to-talk turn")
            }
            Spacer(minLength: 6)
            Toggle(title, isOn: Binding(get: { isOn }, set: { if $0 != isOn { toggle() } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(UntypeDesignTokens.accentAmber)
        }
    }

    // MARK: Hotkeys

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("Hotkeys", trailing: nil)
            hotkeyLine(model.settings.hotkey,
                       model.settings.hotkeyHoldToTalk ? "hold to record, release to submit" : "press to start, press again to submit")
            hotkeyLine("+ R T A F S C I", "switch an operator mid-turn")
            if !model.settings.hotkeyEnabled {
                Text("The hotkey is off — switch it on above.")
                    .font(.caption)
                    .foregroundStyle(UntypeDesignTokens.warnGold)
            }
        }
    }

    private func hotkeyLine(_ keys: String, _ meaning: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            UntypeKbd(keys)
            Text(meaning)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            UntypeSectionHeader(title)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
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
