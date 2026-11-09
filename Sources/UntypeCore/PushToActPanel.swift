import AppKit
import SwiftUI

/// The Push-to-Act pop-up: shows the selected text and lets the user pick
/// the model (primary / Alternative), the operators and the translation
/// direction. It opens with the choices of the last Push-to-Act run, which
/// are remembered again on Run (Push-to-Act's own, separate from the
/// push-to-talk operators). Enter runs, Esc cancels without saving.
///
/// The panel is non-activating but can become key, so it takes the keyboard
/// while the app holding the selection stays frontmost (the result is then
/// delivered back into it, and a push-to-talk press still targets it).
@MainActor
final class PushToActPanelController {
    private var panel: PushToActKeyPanel?
    private var state: PushToActPanelState?
    private var onRun: ((PushToActChoice) -> Void)?
    private var onCancel: (() -> Void)?
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show(
        choice: PushToActChoice,
        selectedText: String,
        wholeFieldName: String? = nil,
        primaryModel: String,
        alternativeModel: String?,
        alternative2Model: String?,
        onRun: @escaping (PushToActChoice) -> Void,
        onCancel: @escaping () -> Void
    ) {
        close()
        let state = PushToActPanelState(
            choice: choice,
            selectedText: selectedText,
            wholeFieldName: wholeFieldName,
            primaryModel: primaryModel,
            alternativeModel: alternativeModel,
            alternative2Model: alternative2Model
        )
        self.state = state
        self.onRun = onRun
        self.onCancel = onCancel
        state.run = { [weak self] in self?.run() }
        state.cancel = { [weak self] in self?.cancel() }

        let panel = PushToActKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: PushToActView.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.onKeyDown = { [weak state] event in
            state?.handleKey(event) ?? false
        }
        let hosting = NSHostingView(rootView: PushToActView(state: state))
        panel.contentView = hosting
        let size = hosting.fittingSize
        if let screen = Self.screenUnderMouse() {
            let frame = screen.visibleFrame
            panel.setFrame(
                NSRect(
                    x: frame.midX - size.width / 2,
                    y: frame.midY - size.height / 2 + frame.height * 0.12,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancel()
            }
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes the pop-up without running (Esc, a click elsewhere, or a
    /// push-to-talk press).
    func cancel() {
        guard panel != nil else {
            return
        }
        let onCancel = self.onCancel
        close()
        onCancel?()
    }

    private func run() {
        guard let state, state.choice.canRun else {
            NSSound.beep()
            return
        }
        let choice = state.choice
        let onRun = self.onRun
        close()
        onRun?(choice)
    }

    private func close() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        panel?.onKeyDown = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        state = nil
        onRun = nil
        onCancel = nil
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}

/// A borderless panel that can take the keyboard and routes every key press
/// to the pop-up's handler first.
private final class PushToActKeyPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class PushToActPanelState: ObservableObject {
    @Published var choice: PushToActChoice
    let selectedText: String
    /// Nothing was selected: what the text is instead ("whole field",
    /// "terminal prompt").
    let wholeFieldName: String?
    let primaryModel: String
    let alternativeModel: String?
    let alternative2Model: String?
    var run: () -> Void = {}
    var cancel: () -> Void = {}

    init(
        choice: PushToActChoice,
        selectedText: String,
        wholeFieldName: String?,
        primaryModel: String,
        alternativeModel: String?,
        alternative2Model: String?
    ) {
        self.choice = choice
        self.selectedText = selectedText
        self.wholeFieldName = wholeFieldName
        self.primaryModel = primaryModel
        self.alternativeModel = alternativeModel
        self.alternative2Model = alternative2Model
    }

    /// Enter / keypad Enter run, Esc cancels, r t a f c toggle, l switches
    /// the model, 1 2 3 pick (and turn on Translate) the translation direction. true: the key was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76:
            run()
            return true
        case 53:
            cancel()
            return true
        default:
            break
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased().first else {
            return false
        }
        if let digit = key.wholeNumberValue, (1...TranslationPolicy.allCases.count).contains(digit) {
            choice.selectTranslation(TranslationPolicy.allCases[digit - 1])
            return true
        }
        if !choice.toggle(key: key) {
            NSSound.beep()
        }
        return true
    }
}

private struct PushToActView: View {
    static let width: CGFloat = 440

    @ObservedObject var state: PushToActPanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Push-to-Act")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text(state.wholeFieldName.map { "Nothing selected · \($0), \(state.selectedText.count) characters" }
                    ?? "\(state.selectedText.count) characters selected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(state.selectedText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerSmall, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

            section("Model") {
                pill("Primary · \(state.primaryModel)", key: nil, on: state.choice.model == .primary) {
                    state.choice.select(.primary)
                }
                if let alternative = state.alternativeModel {
                    pill("Alternative · \(alternative)", key: nil, on: state.choice.model == .alternative) {
                        state.choice.select(.alternative)
                    }
                }
                if let alternative2 = state.alternative2Model {
                    pill("Alternative 2 · \(alternative2)", key: nil, on: state.choice.model == .alternative2) {
                        state.choice.select(.alternative2)
                    }
                }
                if state.alternativeModel == nil, state.alternative2Model == nil {
                    Text("No Alternative LLM configured")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            section("Operators") {
                pill("Refine", key: "R", on: state.choice.refine) { state.choice.refine.toggle() }
                pill("Translate", key: "T", on: state.choice.translate) { state.choice.translate.toggle() }
                pill("Ask", key: "A", on: state.choice.ask) { state.choice.ask.toggle() }
                pill("Follow-up", key: "F", on: state.choice.followup) { state.choice.followup.toggle() }
                pill("Screenshot", key: "W", on: state.choice.screenshot) { state.choice.screenshot.toggle() }
                pill("Clipboard", key: "C", on: state.choice.clipboard) { state.choice.clipboard.toggle() }
            }

            section("Translation") {
                ForEach(Array(TranslationPolicy.allCases.enumerated()), id: \.element) { index, policy in
                    pill(Self.label(policy), key: "\(index + 1)", on: state.choice.translate && state.choice.translationPolicy == policy) {
                        state.choice.selectTranslation(policy)
                    }
                }
            }

            Divider()

            HStack {
                Text(state.choice.canRun ? "L model · letters toggle · 1–3 translate to · Esc cancel" : "Turn on Refine, Translate or Ask")
                    .font(.system(size: 11))
                    .foregroundStyle(state.choice.canRun ? Color.secondary : UntypeDesignTokens.warnGold)
                Spacer()
                Button("Cancel") { state.cancel() }
                Button("Run  ⏎") { state.run() }
                    .buttonStyle(.borderedProminent)
                    .tint(UntypeDesignTokens.accentAmberStrong)
                    .disabled(!state.choice.canRun)
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerLarge, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    static func label(_ policy: TranslationPolicy) -> String {
        switch policy {
        case .opposite: return "Greek ↔ English"
        case .toEnglish: return "→ English"
        case .toGreek: return "→ Greek"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            FlowRow(spacing: 6) {
                content()
            }
        }
    }

    private func pill(_ title: String, key: String?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let key {
                    Text(key)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .opacity(0.7)
                }
                Text(title)
                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(on ? Color.black.opacity(0.85) : Color.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(on ? UntypeDesignTokens.accentAmber : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(on ? Color.clear : Color.primary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

/// Lays its children out left to right, wrapping to a new line when the
/// width runs out.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
