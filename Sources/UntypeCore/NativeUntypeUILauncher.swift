import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI

public enum NativeUntypeUILauncher {
    public static func launchBlockingOnCurrentThread() throws -> Int32 {
        guard Thread.isMainThread else {
            throw UntypeError.invalidConfiguration("Native UI must be launched from the main thread.")
        }
        return MainActor.assumeIsolated {
            NativeUntypeUIApplication.run()
        }
    }

    public static func launch() async throws -> Int32 {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let code = MainActor.assumeIsolated {
                    NativeUntypeUIApplication.run()
                }
                continuation.resume(returning: code)
            }
        }
    }
}

@MainActor
private enum NativeUntypeUIApplication {
    static func run() -> Int32 {
        let app = NSApplication.shared
        let delegate = UntypeAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
        return delegate.exitCode
    }
}

private func dispatchToUI(_ work: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            work()
        }
    }
}

@MainActor
private final class UntypeAppDelegate: NSObject, NSApplicationDelegate {
    var exitCode: Int32 = ExitCode.success.rawValue
    private var model: UntypeUIModel?
    private var window: NSWindow?
    private var overlay: UntypeOverlayController?
    private var hotkeyMonitor: UntypeHotkeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationMenu()
        let model = UntypeUIModel()
        let overlay = UntypeOverlayController(model: model)
        let hotkeyMonitor = UntypeHotkeyMonitor(model: model)
        model.overlay = overlay
        model.hotkeyMonitor = hotkeyMonitor
        self.model = model
        self.overlay = overlay
        self.hotkeyMonitor = hotkeyMonitor
        model.configureHotkeyServices()

        let content = UntypeRootView(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "untype"
        window.minSize = NSSize(width: 860, height: 620)
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor?.stop()
        overlay?.destroy()
        model?.stopFromApplicationQuit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About untype", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide untype", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit untype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}

@MainActor
private enum UntypeUISessionOwner {
    case manual
    case hotkey
}

private final class HotkeySessionControl: RuntimeAudioGate, @unchecked Sendable {
    private let lock = NSLock()
    private var gateOpen = false

    func isOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gateOpen
    }

    func open() {
        lock.lock()
        gateOpen = true
        lock.unlock()
    }

    func close() {
        lock.lock()
        gateOpen = false
        lock.unlock()
    }
}

@MainActor
private final class UntypeUIModel: ObservableObject {
    @Published var settings: UntypeUISettings
    @Published var sessionState = "idle"
    @Published var captureState = "idle"
    @Published var latestTranscript = ""
    @Published var timeline = UntypeUITimelineState()
    @Published var events: [String] = []
    @Published var isRunning = false
    @Published var hotkeyPressed = false
    @Published var hotkeyMonitorStatus = "disabled"
    @Published var audioStatus = "idle"

    var overlay: UntypeOverlayController?
    var hotkeyMonitor: UntypeHotkeyMonitor?

    private var runtime: UntypeRuntimeSession?
    private var sessionTask: Task<Void, Never>?
    private var sessionOwner: UntypeUISessionOwner?
    private var hotkeySessionControl: HotkeySessionControl?
    private var warmSessionRecycleTask: Task<Void, Never>?
    private var restartWarmSessionAfterStop = false
    private var warmSessionRecycleInFlight = false
    private let warmSessionRecycleNanoseconds: UInt64 = 5 * 60 * 1_000_000_000

    init() {
        let result = UntypeUISettingsStore.loadForUI()
        settings = result.settings
        if let errorMessage = result.errorMessage {
            appendEvent("diagnostic.warning: \(errorMessage)")
        }
    }

    func configureHotkeyServices() {
        hotkeyMonitor?.configure(settings: settings)
        reconcileHotkeyWarmSession()
    }

    func update(_ patch: UntypeUISettingsPatch) {
        do {
            let previous = settings
            settings = try settings.merged(patch).refreshingCredentialStatus()
            try UntypeUISettingsStore.save(settings)
            hotkeyMonitor?.configure(settings: settings)
            applyRuntimeOperatorChanges(previous: previous, next: settings)
            reconcileHotkeyWarmSession(restartExistingHotkeySession: !isProtocolSwitchOnlyChange(previous: previous, next: settings))
            overlay?.refreshOperators()
            appendEvent("config.saved: settings updated")
        } catch {
            appendEvent("diagnostic.warning: \(error.localizedDescription)")
        }
    }

    func refreshCredentials() {
        settings = settings.refreshingCredentialStatus()
    }

    func startManualSession() {
        stopHotkeyWarmSession(restartAfterStop: false)
        if runtime == nil, sessionOwner == nil {
            startSession(owner: .manual)
        }
    }

    func stopManualSession() {
        stopPrimarySession()
    }

    func stopPrimarySession() {
        restartWarmSessionAfterStop = false
        if sessionOwner == .hotkey {
            stopHotkeyWarmSession(restartAfterStop: false)
        } else {
            stopSession(reason: "ui-manual-stop", submitPending: false)
        }
    }

    var primarySessionButtonTitle: String {
        guard isRunning else {
            return "Start Listening"
        }
        if captureState == "recording" {
            return "Stop Recording"
        }
        if captureState == "warm" {
            return "Stop Warm Session"
        }
        return "Stop Listening"
    }

    func startHotkeySession(source: String = "hotkey") {
        guard settings.hotkeyEnabled else {
            appendEvent("diagnostic.warning: [untype] push-to-talk ignored because it is disabled")
            return
        }
        guard sessionOwner != .manual else {
            appendEvent("diagnostic.warning: [untype] push-to-talk ignored while a manual session is running")
            return
        }
        hotkeyPressed = true
        captureState = "recording"
        latestTranscript = ""
        timeline.clearPartial()
        clearWarmSessionRecycleTimer()
        overlay?.show(phase: "recording", text: latestTranscript)
        let control = hotkeySessionControl ?? HotkeySessionControl()
        control.open()
        hotkeySessionControl = control
        if runtime == nil, sessionOwner == nil {
            startSession(owner: .hotkey, audioGate: control)
        }
        appendEvent("diagnostic.info: [untype] push-to-talk pressed (\(source))")
    }

    func stopHotkeySession(source: String = "hotkey") {
        guard hotkeyPressed else {
            return
        }
        hotkeyPressed = false
        captureState = "finalizing"
        hotkeySessionControl?.close()
        appendEvent("diagnostic.info: [untype] push-to-talk released (\(source))")
        restartWarmSessionAfterStop = settings.hotkeyEnabled
        stopSession(reason: "ui-hotkey-release", submitPending: true)
        overlay?.show(phase: "finalizing", text: latestTranscript)
        overlay?.hideAfterDelay()
    }

    func toggleOperator(_ key: OperatorKey) {
        let patch: UntypeUISettingsPatch
        switch key {
        case .refine:
            patch = UntypeUISettingsPatch(refine: !settings.refine)
        case .translate:
            patch = UntypeUISettingsPatch(translate: !settings.translate)
        case .clipboard:
            patch = UntypeUISettingsPatch(clipboard: !settings.clipboard)
        case .input:
            patch = UntypeUISettingsPatch(focusedInput: !settings.focusedInput)
        }
        update(patch)
    }

    func clearTranscriptTimeline() {
        timeline.clear()
        latestTranscript = ""
        appendEvent("transcript.cleared")
        overlay?.hideAfterDelay()
    }

    func stopFromApplicationQuit() {
        clearWarmSessionRecycleTimer()
        if let runtime {
            Task.detached {
                await runtime.stop(reason: "ui-quit", submitPending: false)
            }
        }
    }

    private func startSession(owner: UntypeUISessionOwner, audioGate: RuntimeAudioGate? = nil) {
        guard runtime == nil, sessionOwner == nil else {
            return
        }
        sessionState = "starting"
        isRunning = true
        audioStatus = "waiting"
        latestTranscript = ""
        timeline = UntypeUITimelineState()
        sessionOwner = owner
        appendEvent("session.state: starting")
        let currentSettings = settings
        let modelBox = WeakUntypeUIModelBox(self)
        sessionTask = Task.detached { [modelBox] in
            do {
                dispatchToUI { [modelBox] in
                    modelBox.model?.appendEvent("diagnostic.info: [untype] preparing UI session arguments")
                }
                let args = try currentSettings.sessionArguments()
                dispatchToUI { [modelBox] in
                    modelBox.model?.appendEvent("diagnostic.info: [untype] resolving UI session configuration")
                }
                let config = try ConfigResolver(requireProtocolOutputForHybrid: false).resolve(argv: args)
                try Task.checkCancellation()
                for warning in config.warnings {
                    dispatchToUI { [modelBox] in
                        modelBox.model?.appendEvent("diagnostic.warning: \(warning)")
                    }
                }
                try Task.checkCancellation()
                dispatchToUI { [modelBox] in
                    modelBox.model?.appendEvent("diagnostic.info: [untype] creating UI runtime")
                }
                let runtime = try UntypeRuntimeFactory.makeForUI(
                    config: config,
                    audioGate: audioGate,
                    transcript: { event in
                        dispatchToUI { [modelBox] in
                            modelBox.model?.handleTranscript(event)
                        }
                    },
                    protocolOutput: UIEventTextOutput { line in
                        dispatchToUI { [modelBox] in
                            modelBox.model?.appendEvent("protocol.event: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
                        }
                    },
                    diagnosticsOutput: UIEventTextOutput { _ in },
                    eventSink: { event in
                        dispatchToUI { [modelBox] in
                            modelBox.model?.handleSessionEvent(event, owner: owner)
                        }
                    }
                )
                dispatchToUI { [modelBox] in
                    modelBox.model?.runtime = runtime
                    modelBox.model?.appendEvent("diagnostic.info: [untype] starting UI runtime")
                }
                try await runtime.start()
                if Task.isCancelled {
                    await runtime.stop(reason: "ui-start-cancelled", submitPending: false)
                    return
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    dispatchToUI { [modelBox] in
                        modelBox.model?.resetStoppedSessionState(reason: "ui-start-cancelled")
                    }
                    return
                }
                dispatchToUI { [modelBox] in
                    modelBox.model?.appendEvent("session.error: \(uiDiagnosticLine(error))")
                    modelBox.model?.timeline.commitError(uiDiagnosticLine(error))
                    modelBox.model?.resetStoppedSessionState(reason: "ui-startup-error")
                }
            }
        }
    }

    private func stopSession(reason: String, submitPending: Bool) {
        sessionTask?.cancel()
        guard let runtime else {
            resetStoppedSessionState(reason: reason)
            if restartWarmSessionAfterStop {
                restartWarmSessionAfterStop = false
                startHotkeyWarmSession()
            }
            return
        }
        clearWarmSessionRecycleTimer()
        sessionState = "stopping"
        Task.detached { [weak self] in
            await runtime.stop(reason: reason, submitPending: submitPending)
            let failure = runtime.recordedFailure()
            dispatchToUI { [weak self] in
                guard let self else {
                    return
                }
                if let failure {
                    self.appendEvent("session.error: \(uiDiagnosticLine(failure))")
                    self.timeline.commitError(uiDiagnosticLine(failure))
                }
                self.runtime = nil
                self.sessionOwner = nil
                self.hotkeySessionControl = nil
                self.sessionState = "idle"
                self.captureState = "idle"
                self.isRunning = false
                self.hotkeyPressed = false
                self.overlay?.hideAfterDelay()
                if self.restartWarmSessionAfterStop {
                    self.restartWarmSessionAfterStop = false
                    self.startHotkeyWarmSession()
                }
            }
        }
    }

    private func resetStoppedSessionState(reason: String) {
        runtime = nil
        sessionOwner = nil
        hotkeySessionControl = nil
        hotkeyPressed = false
        sessionState = "idle"
        captureState = "idle"
        audioStatus = "idle"
        isRunning = false
        clearWarmSessionRecycleTimer()
        overlay?.hideNow()
        appendEvent("session.state: idle (\(reason))")
    }

    private func reconcileHotkeyWarmSession(restartExistingHotkeySession: Bool = false) {
        guard settings.hotkeyEnabled else {
            stopHotkeyWarmSession(restartAfterStop: false)
            return
        }
        if runtime != nil || sessionOwner != nil {
            if sessionOwner == .hotkey, restartExistingHotkeySession {
                stopHotkeyWarmSession(restartAfterStop: true)
            }
            return
        }
        startHotkeyWarmSession()
    }

    private func startHotkeyWarmSession() {
        guard settings.hotkeyEnabled, runtime == nil, sessionOwner == nil else {
            return
        }
        let control = HotkeySessionControl()
        control.close()
        hotkeySessionControl = control
        captureState = "warm"
        appendEvent("diagnostic.info: [untype] push-to-talk warmed")
        startSession(owner: .hotkey, audioGate: control)
    }

    private func stopHotkeyWarmSession(restartAfterStop: Bool) {
        hotkeyPressed = false
        hotkeySessionControl?.close()
        clearWarmSessionRecycleTimer()
        restartWarmSessionAfterStop = restartAfterStop
        guard sessionOwner == .hotkey else {
            if !restartAfterStop {
                hotkeySessionControl = nil
            }
            return
        }
        stopSession(reason: restartAfterStop ? "ui-hotkey-warm-restart" : "ui-hotkey-warm-stop", submitPending: false)
    }

    private func scheduleWarmSessionRecycle() {
        clearWarmSessionRecycleTimer()
        guard settings.hotkeyEnabled,
              sessionOwner == .hotkey,
              runtime != nil,
              !hotkeyPressed,
              hotkeySessionControl != nil
        else {
            return
        }
        let delay = warmSessionRecycleNanoseconds
        warmSessionRecycleTask = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            dispatchToUI { [weak self] in
                self?.recycleWarmSession()
            }
        }
    }

    private func clearWarmSessionRecycleTimer() {
        warmSessionRecycleTask?.cancel()
        warmSessionRecycleTask = nil
    }

    private func recycleWarmSession() {
        guard !warmSessionRecycleInFlight,
              settings.hotkeyEnabled,
              sessionOwner == .hotkey,
              runtime != nil,
              !hotkeyPressed
        else {
            return
        }
        warmSessionRecycleInFlight = true
        appendEvent("diagnostic.info: [untype] recycling warm push-to-talk session")
        stopHotkeyWarmSession(restartAfterStop: true)
        warmSessionRecycleInFlight = false
    }

    private func applyRuntimeOperatorChanges(previous: UntypeUISettings, next: UntypeUISettings) {
        guard runtime != nil else {
            return
        }
        let changes: [(OperatorKey, Bool, Bool)] = [
            (.refine, previous.refine, next.refine),
            (.translate, previous.translate, next.translate),
            (.clipboard, previous.clipboard, next.clipboard),
            (.input, previous.focusedInput, next.focusedInput)
        ]
        for (key, old, new) in changes where old != new {
            let currentRuntime = runtime
            Task.detached { [weak self, currentRuntime] in
                do {
                    try await currentRuntime?.toggleOperator(key)
                } catch {
                    dispatchToUI { [weak self] in
                        self?.appendEvent("diagnostic.warning: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func handleTranscript(_ event: UITranscriptEvent) {
        switch event {
        case .partial(let text):
            latestTranscript = text
            timeline.updatePartial(text)
            appendEvent("transcript.partial: \(text)")
            if hotkeyPressed {
                overlay?.show(phase: "recording", text: text)
            }
        case .final(let text):
            latestTranscript = text
            timeline.commitFinal(text)
            appendEvent("transcript.final: \(text)")
            if hotkeyPressed {
                overlay?.show(phase: "recording", text: text)
            }
        case .turnBoundary:
            timeline.sealCurrentTurn()
            appendEvent("transcript.turn_boundary")
        case .processed(let text):
            latestTranscript = text
            timeline.commitProcessed(text)
            appendEvent("transcript.processed: \(text)")
            if hotkeyPressed {
                overlay?.show(phase: "processed", text: text)
            }
        }
    }

    private func handleSessionEvent(_ event: TranscriptionSessionEvent, owner: UntypeUISessionOwner) {
        switch event {
        case .stateChanged(let state, let reason):
            sessionState = state.rawValue
            if state == .listening {
                captureState = owner == .hotkey ? (hotkeyPressed ? "recording" : "warm") : "listening"
                if owner == .hotkey, !hotkeyPressed {
                    scheduleWarmSessionRecycle()
                }
            }
            if state == .stopped {
                captureState = "idle"
            }
            appendEvent("session.state: \(state.rawValue)\(reason.map { " (\($0))" } ?? "")")
        case .ready(let message):
            appendEvent("ready: \(message)")
        case .diagnostic(let message, let warning):
            appendEvent("\(warning ? "diagnostic.warning" : "diagnostic.info"): \(message)")
            if warning, shouldSurfaceDiagnosticInTimeline(message) {
                timeline.commitError(message)
            }
        case .audioActivity(let snapshot):
            audioStatus = audioStatusLabel(snapshot)
        }
    }

    fileprivate func appendEvent(_ line: String) {
        guard events.last != line else {
            return
        }
        events.append(line)
        if events.count > 300 {
            events.removeFirst(events.count - 300)
        }
    }

    private func shouldSurfaceDiagnosticInTimeline(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("push-to-talk release")
            || normalized.contains("failed to submit pending utterance")
            || normalized.contains("operator failed")
            || normalized.contains("refine operator is enabled")
            || normalized.contains("translate operator is enabled")
            || normalized.contains("input operator failed")
    }

    private func isProtocolSwitchOnlyChange(previous: UntypeUISettings, next: UntypeUISettings) -> Bool {
        previous.provider == next.provider &&
            previous.model == next.model &&
            previous.languages == next.languages &&
            previous.sampleRate == next.sampleRate &&
            previous.endpointDetection == next.endpointDetection &&
            previous.protocolMode == next.protocolMode &&
            previous.translationPolicy == next.translationPolicy &&
            previous.llmEnabled == next.llmEnabled &&
            previous.llmProvider == next.llmProvider &&
            previous.llmModel == next.llmModel &&
            previous.hotkeyEnabled == next.hotkeyEnabled &&
            previous.hotkey == next.hotkey
    }

    private func audioStatusLabel(_ snapshot: AudioActivitySnapshot) -> String {
        UntypeUIAudioStatusFormatter.label(for: snapshot)
    }
}

private final class UIEventTextOutput: TextOutput {
    private let writeLine: @Sendable (_ text: String) -> Void

    init(writeLine: @escaping @Sendable (_ text: String) -> Void) {
        self.writeLine = writeLine
    }

    func write(_ text: String) {
        writeLine(text)
    }
}

private final class WeakUntypeUIModelBox: @unchecked Sendable {
    weak var model: UntypeUIModel?

    init(_ model: UntypeUIModel?) {
        self.model = model
    }
}

@MainActor
private struct UntypeRootView: View {
    @ObservedObject var model: UntypeUIModel

    var body: some View {
        HStack(spacing: 0) {
            mainPane
            Divider()
            settingsPane
        }
        .frame(minWidth: 860, minHeight: 620)
    }

    private var mainPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("untype")
                        .font(.title2.weight(.semibold))
                    Text("Session: \(model.sessionState) · Capture: \(model.captureState) · Audio: \(model.audioStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.primarySessionButtonTitle) {
                    model.isRunning ? model.stopPrimarySession() : model.startManualSession()
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("Refresh") {
                    model.refreshCredentials()
                }
            }

            monitorPane
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var monitorPane: some View {
        TabView {
            transcriptPane
                .padding(.top, 8)
                .tabItem {
                    Text("Transcript")
                }
            eventsPane
                .padding(.top, 8)
                .tabItem {
                    Text("Events")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcript")
                        .font(.headline)
                    Text(model.timeline.visibleItemCount == 0 ? "No transcript yet" : "\(model.timeline.visibleItemCount) transcript items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") {
                    model.clearTranscriptTimeline()
                }
                .disabled(model.timeline.visibleItemCount == 0)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.timeline.turns) { turn in
                            timelineTurnView(turn)
                                .id(turn.id)
                        }
                        if let partial = model.timeline.partial {
                            livePartialView(partial)
                                .id(partial.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .onChange(of: model.timeline.visibleItemCount) { _, _ in
                    if let partial = model.timeline.partial {
                        proxy.scrollTo(partial.id, anchor: .bottom)
                    } else if let last = model.timeline.turns.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var eventsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Events")
                .font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.events.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.contains("warning") || line.contains("error") ? .orange : .primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .onChange(of: model.events.count) { _, count in
                    if count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func timelineTurnView(_ turn: UntypeUITimelineTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(turn.time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(turn.sealed ? "closed" : "open")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ForEach(turn.bubbles) { bubble in
                timelineBubbleView(bubble)
            }
        }
    }

    private func timelineBubbleView(_ bubble: UntypeUITimelineBubble) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bubble.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(bubble.status)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(bubble.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(9)
        .background(bubbleBackground(bubble.kind))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func livePartialView(_ partial: UntypeUILivePartial) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(partial.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(partial.status)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(partial.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(9)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func bubbleBackground(_ kind: UntypeUITimelineBubbleKind) -> Color {
        switch kind {
        case .raw:
            return Color(nsColor: .controlBackgroundColor)
        case .processed:
            return Color.green.opacity(0.12)
        case .error:
            return Color.orange.opacity(0.16)
        }
    }

    private var settingsPane: some View {
        let availability = UntypeUIControlAvailability(isSessionActive: model.isRunning)
        let sessionShapingDisabled = !availability.sessionShapingControlsEnabled
        let operatorControlsDisabled = !availability.protocolOperatorControlsEnabled

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                glassSection("Credentials") {
                    VStack(alignment: .leading, spacing: 7) {
                        statusRow("Key", model.settings.apiKeyName)
                        statusRow("Status", model.settings.apiKeyStatus)
                        statusRow("Source", model.settings.storageStatus)
                        statusRow("Expiry", model.settings.expiryStatus)
                    }
                }

                glassSection("System") {
                    VStack(alignment: .leading, spacing: 7) {
                        statusRow("Microphone", model.settings.microphoneStatus)
                        statusRow("Audio", model.audioStatus)
                        statusRow("Accessibility", model.settings.accessibilityStatus)
                        statusRow("Input", model.settings.inputStatus)
                    }
                }

                glassSection("Provider") {
                    VStack(alignment: .leading, spacing: 8) {
                        formRow("STT") {
                            Picker("", selection: binding(\.provider)) {
                                Text("Soniox").tag("soniox")
                                Text("ElevenLabs").tag("elevenlabs")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        formRow("Model") {
                            TextField("", text: binding(\.model))
                                .textFieldStyle(.roundedBorder)
                        }
                        formRow("Languages") {
                            TextField("", text: languagesBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                        formRow("Sample") {
                            Stepper("\(model.settings.sampleRate)", value: sampleRateBinding, in: 8_000...48_000, step: 1_000)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        formRow("Endpoint") {
                            Toggle("Detection", isOn: binding(\.endpointDetection))
                        }
                    }
                    .disabled(sessionShapingDisabled)
                }

                glassSection("Protocol") {
                    VStack(alignment: .leading, spacing: 8) {
                        formRow("Mode") {
                            Picker("", selection: binding(\.protocolMode)) {
                                Text("Dictation").tag("dictation")
                                Text("Agent").tag("agent-protocol")
                                Text("Hybrid").tag("hybrid")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(sessionShapingDisabled)
                        formRow("Translation") {
                            Picker("", selection: binding(\.translationPolicy)) {
                                Text("Opposite").tag("opposite")
                                Text("To English").tag("to-en")
                                Text("To Greek").tag("to-el")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(sessionShapingDisabled)
                        formRow("Operators") {
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle("Refine", isOn: binding(\.refine))
                                Toggle("Translate", isOn: binding(\.translate))
                                Toggle("Clipboard", isOn: binding(\.clipboard))
                                Toggle("Focused input", isOn: binding(\.focusedInput))
                            }
                            .disabled(operatorControlsDisabled)
                        }
                    }
                }

                glassSection("LLM") {
                    VStack(alignment: .leading, spacing: 8) {
                        formRow("Enabled") {
                            Toggle("", isOn: binding(\.llmEnabled))
                                .labelsHidden()
                        }
                        formRow("Provider") {
                            Picker("", selection: binding(\.llmProvider)) {
                                ForEach(LLMProvider.allCases, id: \.rawValue) { provider in
                                    Text(provider.rawValue).tag(provider.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        formRow("Model") {
                            TextField("", text: binding(\.llmModel))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .disabled(sessionShapingDisabled)
                }

                glassSection("Push to Talk") {
                    VStack(alignment: .leading, spacing: 8) {
                        formRow("Enabled") {
                            Toggle("", isOn: binding(\.hotkeyEnabled))
                                .labelsHidden()
                        }
                        .disabled(sessionShapingDisabled)
                        formRow("Hotkey") {
                            TextField("", text: binding(\.hotkey))
                                .textFieldStyle(.roundedBorder)
                        }
                        .disabled(sessionShapingDisabled)
                        formRow("Action") {
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
                            .padding(.leading, settingsLabelWidth + 10)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .frame(width: 360)
    }

    private var settingsLabelWidth: CGFloat {
        88
    }

    private func glassSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func formRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: settingsLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: settingsLabelWidth, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
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
        case \UntypeUISettings.hotkey:
            return UntypeUISettingsPatch(hotkey: value as? String)
        default:
            return UntypeUISettingsPatch()
        }
    }
}

@MainActor
private final class UntypeOverlayController: ObservableObject {
    private weak var model: UntypeUIModel?
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    @Published private var phase = "idle"
    @Published private var text = ""
    @Published private var operatorVersion = 0

    init(model: UntypeUIModel) {
        self.model = model
    }

    func show(phase: String, text: String) {
        hideTask?.cancel()
        self.phase = phase
        self.text = text
        if panel == nil {
            createPanel()
        }
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func refreshOperators() {
        operatorVersion += 1
    }

    func hideAfterDelay() {
        hideTask?.cancel()
        hideTask = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dispatchToUI { [weak self] in
                self?.hideNow()
            }
        }
    }

    func hideNow() {
        hideTask?.cancel()
        text = ""
        phase = "idle"
        panel?.orderOut(nil)
    }

    func destroy() {
        hideTask?.cancel()
        panel?.close()
        panel = nil
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 118),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(rootView: UntypeOverlayView(controller: self))
        self.panel = panel
    }

    private func positionPanel() {
        guard let panel else {
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else {
            return
        }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 46
        ))
    }

    fileprivate var overlayPhase: String {
        phase
    }

    fileprivate var overlayText: String {
        text
    }

    fileprivate var operatorSnapshot: [(label: String, enabled: Bool)] {
        guard let settings = model?.settings else {
            return []
        }
        return [
            ("R", settings.refine),
            ("T", settings.translate),
            ("C", settings.clipboard),
            ("I", settings.focusedInput)
        ]
    }
}

@MainActor
private struct UntypeOverlayView: View {
    @ObservedObject var controller: UntypeOverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(controller.overlayPhase == "recording" ? Color.red : Color.green)
                    .frame(width: 9, height: 9)
                Text(controller.overlayPhase)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                Spacer()
            }
            Text(controller.overlayText.isEmpty ? " " : controller.overlayText)
                .font(.system(size: 20, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(controller.operatorSnapshot, id: \.label) { item in
                    Text(item.label)
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 18)
                        .foregroundStyle(item.enabled ? Color.white : Color.secondary)
                        .background(item.enabled ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Spacer()
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 18)
    }
}

@MainActor
private final class UntypeHotkeyMonitor {
    private weak var model: UntypeUIModel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var descriptor: UntypeHotkeyDescriptor?
    private var eventTap: UntypeQuartzHotkeyEventTap?
    private let state = UntypeHotkeySharedState()

    init(model: UntypeUIModel) {
        self.model = model
    }

    func configure(settings: UntypeUISettings) {
        stop()
        guard settings.hotkeyEnabled else {
            model?.hotkeyMonitorStatus = "disabled"
            return
        }
        do {
            let descriptor = try UntypeHotkeyDescriptor(settings.hotkey)
            self.descriptor = descriptor
            state.reset()
            if !AXIsProcessTrusted() {
                model?.events.append("diagnostic.warning: Accessibility/Input Monitoring may be required for global hotkey release detection.")
            }
            let tap = UntypeQuartzHotkeyEventTap(
                descriptor: descriptor,
                state: state,
                emit: { [weak self] event in
                    dispatchToUI { [weak self] in
                        self?.dispatch(event)
                    }
                }
            )
            if tap.start() {
                eventTap = tap
                state.setReleaseHookAvailable(true)
                model?.hotkeyMonitorStatus = "global event tap ready"
            } else {
                state.setReleaseHookAvailable(false)
                model?.hotkeyMonitorStatus = "fallback monitor active; press again if release is blocked"
                model?.events.append("diagnostic.warning: Quartz hotkey event tap could not start. Falling back to NSEvent monitoring and press-to-toggle behavior if release is not detected.")
                globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                    _ = self?.handle(event: event, source: "global-monitor", suppress: false)
                }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self else {
                    return event
                }
                return self.handle(event: event, source: "local-monitor", suppress: true) ? nil : event
            }
        } catch {
            model?.hotkeyMonitorStatus = "invalid hotkey"
            model?.events.append("diagnostic.warning: \(error.localizedDescription)")
        }
    }

    func stop() {
        eventTap?.stop()
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        eventTap = nil
        localMonitor = nil
        globalMonitor = nil
        state.reset()
    }

    private func handle(event: NSEvent, source: String, suppress: Bool) -> Bool {
        guard let descriptor else {
            return false
        }
        if event.type == .keyDown {
            if event.isARepeat, descriptor.matches(event) {
                return true
            }
            if state.isPressed(), let key = descriptor.eventKey(event), let operatorKey = OperatorKey.hotkeyKey(key) {
                dispatch(.toggleOperator(operatorKey, source: source))
                return true
            }
            if descriptor.matches(event) {
                if state.releaseHookAvailable() {
                    if state.markPressed() {
                        dispatch(.press(source: source))
                    }
                } else if state.togglePressed() {
                    dispatch(.press(source: source))
                } else {
                    dispatch(.release(source: source))
                }
                return true
            }
            return false
        }
        if event.type == .keyUp || event.type == .flagsChanged {
            if state.isPressed(), descriptor.releases(event), state.markReleased() {
                dispatch(.release(source: source))
                return event.type == .keyUp
            }
            return false
        }
        return false
    }

    private func dispatch(_ event: UntypeHotkeyEvent) {
        dispatchToUI { [weak model] in
            guard let model else {
                return
            }
            switch event {
            case .press(let source):
                model.startHotkeySession(source: source)
            case .release(let source):
                model.stopHotkeySession(source: source)
            case .toggleOperator(let key, let source):
                model.appendEvent("diagnostic.info: [untype] protocol operator hotkey \(key.rawValue) (\(source))")
                model.toggleOperator(key)
            case .warning(let message):
                model.hotkeyMonitorStatus = "event tap warning"
                model.events.append("diagnostic.warning: \(message)")
            }
        }
    }
}

private enum UntypeHotkeyEvent: Sendable {
    case press(source: String)
    case release(source: String)
    case toggleOperator(OperatorKey, source: String)
    case warning(String)
}

private final class UntypeHotkeySharedState: @unchecked Sendable {
    private let lock = NSLock()
    private var pressed = false
    private var hasReleaseHook = false

    func reset() {
        lock.lock()
        pressed = false
        hasReleaseHook = false
        lock.unlock()
    }

    func setReleaseHookAvailable(_ available: Bool) {
        lock.lock()
        hasReleaseHook = available
        lock.unlock()
    }

    func releaseHookAvailable() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasReleaseHook
    }

    func isPressed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pressed
    }

    func markPressed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !pressed else {
            return false
        }
        pressed = true
        return true
    }

    func markReleased() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pressed else {
            return false
        }
        pressed = false
        return true
    }

    func togglePressed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pressed.toggle()
        return pressed
    }
}

private final class UntypeQuartzHotkeyEventTap {
    private let descriptor: UntypeHotkeyDescriptor
    private let state: UntypeHotkeySharedState
    private let emit: @Sendable (UntypeHotkeyEvent) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        descriptor: UntypeHotkeyDescriptor,
        state: UntypeHotkeySharedState,
        emit: @escaping @Sendable (UntypeHotkeyEvent) -> Void
    ) {
        self.descriptor = descriptor
        self.state = state
        self.emit = emit
    }

    func start() -> Bool {
        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: untypeHotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            emit(.warning("Quartz hotkey event tap was disabled by macOS and was re-enabled. If this repeats, grant Input Monitoring permission to the launching app."))
            return false
        }
        if type == .keyDown {
            if descriptor.matches(event), event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return true
            }
            if state.isPressed(),
               let key = descriptor.eventKey(event),
               let operatorKey = OperatorKey.hotkeyKey(key)
            {
                emit(.toggleOperator(operatorKey, source: "quartz-event-tap"))
                return true
            }
            if descriptor.matches(event) {
                if state.markPressed() {
                    emit(.press(source: "quartz-event-tap"))
                }
                return true
            }
            return false
        }
        if type == .keyUp || type == .flagsChanged {
            if state.isPressed(), descriptor.releases(event), state.markReleased() {
                emit(.release(source: "quartz-event-tap"))
                return type == .keyUp
            }
            return false
        }
        return false
    }
}

private let untypeHotkeyEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let tap = Unmanaged<UntypeQuartzHotkeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    if tap.handle(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}

private extension OperatorKey {
    static func hotkeyKey(_ key: String) -> OperatorKey? {
        switch key.uppercased() {
        case "R":
            return .refine
        case "T":
            return .translate
        case "C":
            return .clipboard
        case "I":
            return .input
        default:
            return nil
        }
    }
}

private struct UntypeHotkeyDescriptor: Sendable {
    let key: String
    let keyCode: CGKeyCode?
    let commandOrControl: Bool
    let control: Bool
    let command: Bool
    let option: Bool
    let shift: Bool

    init(_ raw: String) throws {
        let separator: Character = raw.contains("+") ? "+" : "-"
        let parts = raw
            .split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            throw UntypeError.invalidConfiguration("hotkey must not be empty.")
        }
        var commandOrControl = false
        var control = false
        var command = false
        var option = false
        var shift = false
        var key: String?
        for part in parts {
            switch UntypeHotkeyDescriptor.normalizedModifier(part) {
            case .commandOrControl:
                guard !commandOrControl else {
                    throw UntypeError.invalidConfiguration("Duplicate hotkey modifier: \(part).")
                }
                commandOrControl = true
            case .control:
                guard !control else {
                    throw UntypeError.invalidConfiguration("Duplicate hotkey modifier: \(part).")
                }
                control = true
            case .command:
                guard !command else {
                    throw UntypeError.invalidConfiguration("Duplicate hotkey modifier: \(part).")
                }
                command = true
            case .option:
                guard !option else {
                    throw UntypeError.invalidConfiguration("Duplicate hotkey modifier: \(part).")
                }
                option = true
            case .shift:
                guard !shift else {
                    throw UntypeError.invalidConfiguration("Duplicate hotkey modifier: \(part).")
                }
                shift = true
            case .none:
                guard key == nil else {
                    throw UntypeError.invalidConfiguration("hotkey must contain exactly one non-modifier key: \(raw).")
                }
                key = try UntypeHotkeyDescriptor.normalizedKey(part)
            }
        }
        guard let key else {
            throw UntypeError.invalidConfiguration("hotkey must include a non-modifier key: \(raw).")
        }
        if commandOrControl && (control || command) {
            throw UntypeError.invalidConfiguration("CommandOrControl cannot be combined with explicit Command or Control modifiers.")
        }
        self.key = key
        self.keyCode = UntypeHotkeyDescriptor.keyCodes[key]
        self.commandOrControl = commandOrControl
        self.control = control
        self.command = command
        self.option = option
        self.shift = shift
    }

    func matches(_ event: NSEvent) -> Bool {
        eventKey(event) == key && modifiersMatch(event.modifierFlags)
    }

    func releases(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            return requiredModifierWasReleased(event.modifierFlags)
        }
        return eventKey(event) == key || requiredModifierWasReleased(event.modifierFlags)
    }

    func eventKey(_ event: NSEvent) -> String? {
        if let codeKey = UntypeHotkeyDescriptor.keyCodesByCode[CGKeyCode(event.keyCode)] {
            return codeKey
        }
        return try? UntypeHotkeyDescriptor.normalizedKey(event.charactersIgnoringModifiers ?? event.characters ?? "")
    }

    func matches(_ event: CGEvent) -> Bool {
        guard eventKey(event) == key else {
            return false
        }
        return modifiersMatch(event.flags)
    }

    func releases(_ event: CGEvent) -> Bool {
        eventKey(event) == key || requiredModifierWasReleased(event.flags)
    }

    func eventKey(_ event: CGEvent) -> String? {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        return UntypeHotkeyDescriptor.keyCodesByCode[code]
    }

    private func modifiersMatch(_ flags: NSEvent.ModifierFlags) -> Bool {
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        return modifiersMatch(
            control: normalized.contains(.control),
            command: normalized.contains(.command),
            option: normalized.contains(.option),
            shift: normalized.contains(.shift)
        )
    }

    private func modifiersMatch(_ flags: CGEventFlags) -> Bool {
        modifiersMatch(
            control: flags.contains(.maskControl),
            command: flags.contains(.maskCommand),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift)
        )
    }

    private func modifiersMatch(control hasControl: Bool, command hasCommand: Bool, option hasOption: Bool, shift hasShift: Bool) -> Bool {
        guard hasOption == option, hasShift == shift else {
            return false
        }
        if commandOrControl {
            return hasControl != hasCommand
        }
        return hasControl == control && hasCommand == command
    }

    private func requiredModifierWasReleased(_ flags: NSEvent.ModifierFlags) -> Bool {
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        return requiredModifierWasReleased(
            control: normalized.contains(.control),
            command: normalized.contains(.command),
            option: normalized.contains(.option),
            shift: normalized.contains(.shift)
        )
    }

    private func requiredModifierWasReleased(_ flags: CGEventFlags) -> Bool {
        requiredModifierWasReleased(
            control: flags.contains(.maskControl),
            command: flags.contains(.maskCommand),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift)
        )
    }

    private func requiredModifierWasReleased(control hasControl: Bool, command hasCommand: Bool, option hasOption: Bool, shift hasShift: Bool) -> Bool {
        if commandOrControl {
            return !hasControl && !hasCommand
        }
        if control && !hasControl {
            return true
        }
        if command && !hasCommand {
            return true
        }
        if option && !hasOption {
            return true
        }
        if shift && !hasShift {
            return true
        }
        return false
    }

    private enum Modifier {
        case commandOrControl
        case control
        case command
        case option
        case shift
    }

    private static func normalizedModifier(_ value: String) -> Modifier? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "commandorcontrol", "cmdorctrl", "commandorctrl":
            return .commandOrControl
        case "control", "ctrl":
            return .control
        case "command", "cmd", "meta", "super":
            return .command
        case "option", "alt":
            return .option
        case "shift":
            return .shift
        default:
            return nil
        }
    }

    private static func normalizedKey(_ value: String) throws -> String {
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
        case "\r", "return", "enter":
            return "Enter"
        case "\t", "tab":
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

    private static let keyCodes: [String: CGKeyCode] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
        "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
        "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "Enter": 36,
        "L": 37, "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "N": 45, "M": 46, ".": 47, "Tab": 48, "Space": 49,
        "`": 50, "Backspace": 51, "Escape": 53, "F5": 96, "F6": 97,
        "F7": 98, "F3": 99, "F8": 100, "F9": 101, "F11": 103, "F13": 105,
        "F16": 106, "F14": 107, "F10": 109, "F12": 111, "F15": 113,
        "Home": 115, "PageUp": 116, "Delete": 117, "F4": 118, "End": 119,
        "F2": 120, "PageDown": 121, "F1": 122, "ArrowLeft": 123,
        "ArrowRight": 124, "ArrowDown": 125, "ArrowUp": 126
    ]

    private static let keyCodesByCode: [CGKeyCode: String] = {
        var result: [CGKeyCode: String] = [:]
        for (key, code) in keyCodes {
            result[code] = key
        }
        return result
    }()
}

private func uiDiagnosticLine(_ error: Error) -> String {
    if let error = error as? UntypeError {
        return error.diagnosticLine
    }
    return "unknown: \(error.localizedDescription)"
}
