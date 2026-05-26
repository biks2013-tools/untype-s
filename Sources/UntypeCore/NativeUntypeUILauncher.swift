import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
private final class UntypeAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var exitCode: Int32 = ExitCode.success.rawValue
    private var model: UntypeUIModel?
    private var window: NSWindow?
    private var overlay: UntypeOverlayController?
    private var hotkeyMonitor: UntypeHotkeyMonitor?
    private var compactCancellable: AnyCancellable?
    private var wasCompactWindow: Bool = false

    private static let miniSize = NSSize(width: 440, height: 260)
    private static let mainMinSize = NSSize(width: 860, height: 620)

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
        let initialCompact = model.settings.compactWindow
        wasCompactWindow = initialCompact
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: initialCompact ? Self.miniSize.width : model.settings.windowWidth,
            height: initialCompact ? Self.miniSize.height : model.settings.windowHeight
        )
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "untype"
        window.minSize = initialCompact ? Self.miniSize : Self.mainMinSize
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // React to compact-window toggles from the toolbar.
        compactCancellable = model.$settings
            .map(\.compactWindow)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] compact in
                self?.applyCompactWindow(compact)
            }
    }

    private func applyCompactWindow(_ compact: Bool) {
        guard let window, let model else { return }
        if compact == wasCompactWindow { return }
        wasCompactWindow = compact
        if compact {
            window.minSize = Self.miniSize
            var frame = window.frame
            frame.origin.y += frame.size.height - Self.miniSize.height
            frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.miniSize)).size
            window.setFrame(frame, display: true, animate: true)
        } else {
            window.minSize = Self.mainMinSize
            let target = NSSize(width: model.settings.windowWidth, height: model.settings.windowHeight)
            var frame = window.frame
            frame.origin.y -= target.height - frame.size.height
            frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: target)).size
            window.setFrame(frame, display: true, animate: true)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        // Only persist resize while not in compact mode — compact-window size is fixed.
        guard let model, !model.settings.compactWindow else { return }
        model.updateLayout(
            windowWidth: Double(window.contentLayoutRect.width),
            windowHeight: Double(window.contentLayoutRect.height)
        )
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
    private var lastAudioEventCategory: String?
    private var lastAudioEventLoggedAt = Date.distantPast
    private let warmSessionRecycleNanoseconds: UInt64 = 5 * 60 * 1_000_000_000
    private let audioEventInterval: TimeInterval = 2

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

    func updateLayout(
        windowWidth: Double? = nil,
        windowHeight: Double? = nil,
        monitorSidebarExpanded: Bool? = nil,
        settingsExpanded: Bool? = nil,
        selectedMonitorTab: String? = nil,
        selectedEventsFilter: String? = nil,
        compactWindow: Bool? = nil,
        appearance: String? = nil
    ) {
        do {
            settings = try settings.merged(UntypeUISettingsPatch(
                windowWidth: windowWidth,
                windowHeight: windowHeight,
                monitorSidebarExpanded: monitorSidebarExpanded,
                settingsExpanded: settingsExpanded,
                selectedMonitorTab: selectedMonitorTab,
                selectedEventsFilter: selectedEventsFilter,
                compactWindow: compactWindow,
                appearance: appearance
            ))
            try UntypeUISettingsStore.save(settings)
            overlay?.refreshTheme()
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

    var canExportTranscript: Bool {
        transcriptExportDocument != nil
    }

    var canExportEvents: Bool {
        eventsExportDocument != nil
    }

    func copyTranscriptExport() {
        copyExport(transcriptExportDocument)
    }

    func saveTranscriptExport() {
        saveExport(transcriptExportDocument)
    }

    func copyEventsExport() {
        copyExport(eventsExportDocument)
    }

    func saveEventsExport() {
        saveExport(eventsExportDocument)
    }

    func stopFromApplicationQuit() {
        clearWarmSessionRecycleTimer()
        if let runtime {
            Task.detached {
                await runtime.stop(reason: "ui-quit", submitPending: false)
            }
        }
    }

    private var transcriptExportDocument: UntypeUIExportDocument? {
        UntypeUIExportDocument.transcript(from: timeline)
    }

    private var eventsExportDocument: UntypeUIExportDocument? {
        UntypeUIExportDocument.events(from: events)
    }

    private func copyExport(_ document: UntypeUIExportDocument?) {
        let router = UntypeUIExportActionRouter(
            copyText: MacOSClipboardWriter.writeToSystemPasteboard,
            saveDocument: { _ in }
        )
        do {
            let copied = try router.copy(document)
            appendEvent("export.copied: \(copied.kind.displayName)")
        } catch UntypeUIExportActionError.emptyContent {
            return
        } catch {
            appendEvent("diagnostic.warning: \(error.localizedDescription)")
        }
    }

    private func saveExport(_ document: UntypeUIExportDocument?) {
        guard let document, document.hasContent else {
            return
        }
        do {
            if try writeExportDocumentWithSavePanel(document) {
                appendEvent("export.saved: \(document.kind.displayName)")
            }
        } catch {
            appendEvent("diagnostic.warning: Could not save \(document.kind.displayName): \(error.localizedDescription)")
        }
    }

    private func writeExportDocumentWithSavePanel(_ document: UntypeUIExportDocument) throws -> Bool {
        let panel = NSSavePanel()
        panel.title = "Save \(document.kind.displayName.capitalized)"
        panel.nameFieldStringValue = document.suggestedFileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }
        try document.text.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    private func startSession(owner: UntypeUISessionOwner, audioGate: RuntimeAudioGate? = nil) {
        guard runtime == nil, sessionOwner == nil else {
            return
        }
        sessionState = "starting"
        isRunning = true
        audioStatus = "waiting"
        latestTranscript = ""
        timeline.clearPartial()
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
                    if self.restartWarmSessionAfterStop {
                        self.appendEvent("diagnostic.warning: [untype] warm push-to-talk restart skipped after runtime failure")
                    }
                    self.restartWarmSessionAfterStop = false
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
            timeline.commitProcessed(text, status: processedTranscriptStatus())
            appendEvent("transcript.processed: \(text)")
            if hotkeyPressed {
                overlay?.show(phase: "processed", text: text)
            }
        }
    }

    private func processedTranscriptStatus() -> String {
        switch (settings.refine, settings.translate) {
        case (true, true):
            return "refined + translated"
        case (true, false):
            return "refined"
        case (false, true):
            return "translated"
        case (false, false):
            return "processed"
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
            let label = audioStatusLabel(snapshot)
            audioStatus = label
            appendAudioActivityEvent(snapshot, label: label)
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

    private func appendAudioActivityEvent(_ snapshot: AudioActivitySnapshot, label: String) {
        let category = audioActivityCategory(snapshot)
        let now = Date()
        guard category != lastAudioEventCategory || now.timeIntervalSince(lastAudioEventLoggedAt) >= audioEventInterval else {
            return
        }
        lastAudioEventCategory = category
        lastAudioEventLoggedAt = now
        let route = snapshot.mutedByGate ? "provider receives silence" : "provider receives microphone audio"
        appendEvent("audio.input: \(label); mic bytes \(snapshot.byteCount); \(route)")
    }

    private func audioActivityCategory(_ snapshot: AudioActivitySnapshot) -> String {
        if snapshot.mutedByGate {
            return "muted"
        }
        if snapshot.peak <= 0.01 {
            return "silent"
        }
        return "active"
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
    @State private var showOnboarding: Bool = false
    private static let titlebarControlHeight: CGFloat = 54
    private static let transcriptOperatorLabelMinimumContentWidth: CGFloat = 760

    var body: some View {
        Group {
            if model.settings.compactWindow {
                UntypeMiniView(model: model)
                    .toolbar { compactToolbarContent }
            } else {
                NavigationSplitView(columnVisibility: monitorSidebarVisibility) {
                    sidebarPane
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
                } detail: {
                    HStack(spacing: 0) {
                        contentPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if model.settings.settingsExpanded {
                            Divider()
                            settingsPane
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
                .frame(minWidth: 860, minHeight: 620)
                .toolbar { toolbarBrandContent }
                .overlay(alignment: .topTrailing) {
                    titlebarControls
                        .padding(.top, 8)
                        .padding(.trailing, titlebarControlsTrailingPadding)
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: model.settings.settingsExpanded)
        .animation(.easeInOut(duration: 0.16), value: model.settings.monitorSidebarExpanded)
        .animation(.easeInOut(duration: 0.18), value: model.settings.compactWindow)
        .preferredColorScheme(preferredColorScheme)
        .onAppear(perform: evaluateOnboarding)
        .onChange(of: model.settings.apiKeyStatus) { _, _ in evaluateOnboarding() }
        .onChange(of: model.settings.microphoneStatus) { _, _ in evaluateOnboarding() }
        .onChange(of: model.settings.accessibilityStatus) { _, _ in evaluateOnboarding() }
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

    private func evaluateOnboarding() {
        if model.settings.compactWindow {
            showOnboarding = false
            return
        }
        if UntypeOnboardingView.recentlySkipped() {
            return
        }
        let micOK = UntypeStatusToneMap.microphone(model.settings.microphoneStatus) == .ok
        let axOK = UntypeStatusToneMap.accessibility(model.settings.accessibilityStatus) == .ok
        let credOK = UntypeStatusToneMap.credential(model.settings.apiKeyStatus) == .ok
        if !(micOK && axOK && credOK) {
            showOnboarding = true
        }
    }

    @ToolbarContentBuilder
    private var compactToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.updateLayout(compactWindow: false)
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .help("Exit Compact Mode")
            .keyboardShortcut("m", modifiers: [.command, .option])
        }
    }

    // MARK: Titlebar Controls

    @ToolbarContentBuilder
    private var toolbarBrandContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.updateLayout(monitorSidebarExpanded: !model.settings.monitorSidebarExpanded)
            } label: {
                HStack(spacing: 6) {
                    UntypeBrandMark(size: 20)
                    Text("untype")
                        .font(.system(size: 13, weight: .semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.settings.monitorSidebarExpanded ? "Hide Monitor Sidebar" : "Show Monitor Sidebar")
        }
    }

    private var monitorSidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { model.settings.monitorSidebarExpanded ? .all : .detailOnly },
            set: { visibility in
                let expanded = visibility != .detailOnly
                if expanded != model.settings.monitorSidebarExpanded {
                    model.updateLayout(monitorSidebarExpanded: expanded)
                }
            }
        )
    }

    private var titlebarControlsTrailingPadding: CGFloat {
        model.settings.settingsExpanded ? 338 : 18
    }

    private var titlebarControls: some View {
        HStack(spacing: 10) {
            UntypeRecordButton(
                isRecording: model.isRunning,
                titleIdle: model.primarySessionButtonTitle,
                titleRecording: model.primarySessionButtonTitle
            ) {
                model.isRunning ? model.stopPrimarySession() : model.startManualSession()
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button {
                model.refreshCredentials()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh credentials and permission status")

            Menu {
                Picker("Appearance", selection: appearanceBinding) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon.fill").tag("dark")
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: appearanceIcon)
            }
            .help("Appearance: \(model.settings.appearance.capitalized)")

            Button {
                model.updateLayout(settingsExpanded: !model.settings.settingsExpanded)
            } label: {
                Image(systemName: model.settings.settingsExpanded ? "sidebar.right" : "sidebar.squares.right")
            }
            .help(model.settings.settingsExpanded ? "Hide Inspector" : "Show Inspector")
            .keyboardShortcut("\\", modifiers: [.command])

            Button {
                model.updateLayout(compactWindow: true)
            } label: {
                Image(systemName: "rectangle.compress.vertical")
            }
            .help("Enter Compact Mode")
            .keyboardShortcut("m", modifiers: [.command, .option])
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var appearanceBinding: Binding<String> {
        Binding(
            get: { model.settings.appearance },
            set: { model.updateLayout(appearance: $0) }
        )
    }

    private var appearanceIcon: String {
        switch model.settings.appearance {
        case "light": return "sun.max"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    private var statusStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(model.settings.provider)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(UntypeDesignTokens.accentAmber)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(model.settings.protocolMode)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )

                UntypeStatusPill(
                    symbol: model.isRunning ? "record.circle.fill" : "circle",
                    label: "Session",
                    value: model.sessionState,
                    tone: UntypeStatusToneMap.session(isRunning: model.isRunning, isHotkeyPressed: model.hotkeyPressed)
                )
                UntypeStatusPill(
                    symbol: "waveform",
                    label: "Audio",
                    value: model.audioStatus,
                    tone: UntypeStatusToneMap.audio(model.audioStatus)
                )
                UntypeStatusPill(
                    symbol: outputSymbol,
                    label: "Output",
                    value: outputLabel,
                    tone: outputTone
                )
                UntypeStatusPill(
                    symbol: "lock.shield",
                    label: "Permissions",
                    value: permissionLabel,
                    tone: permissionTone
                )
            }
            .padding(.vertical, 2)
        }
    }

    private var outputSymbol: String {
        switch (model.settings.clipboard, model.settings.focusedInput) {
        case (true, true): return "doc.on.clipboard"
        case (true, false): return "doc.on.doc"
        case (false, true): return "keyboard"
        default: return "circle.slash"
        }
    }

    private var outputLabel: String {
        switch (model.settings.clipboard, model.settings.focusedInput) {
        case (true, true): return "clipboard + input"
        case (true, false): return "clipboard"
        case (false, true): return "focused input"
        default: return "off"
        }
    }

    private var outputTone: UntypeStatusTone {
        (model.settings.clipboard || model.settings.focusedInput) ? .accent : .off
    }

    private var permissionLabel: String {
        let micOK = model.settings.microphoneStatus.lowercased().contains("grant") || model.settings.microphoneStatus.lowercased().contains("ok") || model.settings.microphoneStatus.lowercased().contains("authorized")
        let axOK = model.settings.accessibilityStatus.lowercased().contains("trust") || model.settings.accessibilityStatus.lowercased().contains("grant") || model.settings.accessibilityStatus.lowercased().contains("ok")
        if !micOK { return "needs mic" }
        if !axOK { return "needs ax" }
        return "ok"
    }

    private var permissionTone: UntypeStatusTone {
        permissionLabel == "ok" ? .ok : .warn
    }

    // MARK: Sidebar

    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            UntypeSectionHeader("Monitor")
                .padding(.horizontal, 12)
                .padding(.top, 6)
            sidebarRow("Transcript", systemImage: "text.alignleft", tag: "transcript", liveTone: model.isRunning ? .recording : nil)
            sidebarRow("History", systemImage: "clock.arrow.circlepath", tag: "history")
            sidebarRow("Events", systemImage: "list.bullet.indent", tag: "events")

            UntypeSectionHeader("Status")
                .padding(.horizontal, 12)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                statusLine("Microphone", value: model.settings.microphoneStatus, tone: UntypeStatusToneMap.microphone(model.settings.microphoneStatus))
                statusLine("Accessibility", value: model.settings.accessibilityStatus, tone: UntypeStatusToneMap.accessibility(model.settings.accessibilityStatus))
                statusLine(model.settings.apiKeyName, value: model.settings.apiKeyStatus, tone: UntypeStatusToneMap.credential(model.settings.apiKeyStatus))
                statusLine("Hotkey", value: model.settings.hotkeyEnabled ? model.settings.hotkey : "disabled", tone: model.settings.hotkeyEnabled ? .accent : .off)
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous))
            .padding(.horizontal, 8)

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func sidebarRow(_ title: String, systemImage: String, tag: String, liveTone: UntypeStatusTone? = nil) -> some View {
        Button {
            model.updateLayout(selectedMonitorTab: tag)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(model.settings.selectedMonitorTab == tag ? UntypeDesignTokens.accentAmber : Color.secondary)
                Text(title)
                    .font(.system(size: 13, weight: model.settings.selectedMonitorTab == tag ? .semibold : .medium))
                    .foregroundStyle(model.settings.selectedMonitorTab == tag ? Color.primary : Color.secondary)
                Spacer()
                if let liveTone, tag == "transcript" {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(liveTone.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(liveTone.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(model.settings.selectedMonitorTab == tag ? UntypeDesignTokens.accentAmber.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func statusLine(_ key: String, value: String, tone: UntypeStatusTone) -> some View {
        HStack(spacing: 6) {
            UntypeStatusDot(tone: tone, size: 6)
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(tone == .warn ? UntypeDesignTokens.warnGold : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: Content

    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusStrip
            switch model.settings.selectedMonitorTab {
            case "history":
                historyPane
            case "events":
                eventsPane
            default:
                transcriptPane
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcript")
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.timeline.visibleItemCount == 0 ? "No transcript yet" : "\(model.timeline.visibleItemCount) transcript items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    UntypeWaveformView(isActive: model.isRunning, barCount: 24, height: 22)
                    Text(audioLevelLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(model.isRunning ? UntypeDesignTokens.recordingRed : .secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            GeometryReader { geometry in
                transcriptActionRow(
                    showsOperatorLabels: geometry.size.width >= Self.transcriptOperatorLabelMinimumContentWidth
                )
            }
            .frame(height: 34)

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

    private func transcriptActionRow(showsOperatorLabels: Bool) -> some View {
        HStack(spacing: 8) {
            UntypeOperatorChip(
                letter: "R",
                label: "Refine",
                isOn: model.settings.refine,
                isRecording: model.isRunning,
                showsLabel: showsOperatorLabels
            ) {
                model.toggleOperator(.refine)
            }
            UntypeOperatorChip(
                letter: "T",
                label: "Translate",
                isOn: model.settings.translate,
                isRecording: model.isRunning,
                showsLabel: showsOperatorLabels
            ) {
                model.toggleOperator(.translate)
            }
            UntypeOperatorChip(
                letter: "C",
                label: "Clipboard",
                isOn: model.settings.clipboard,
                isRecording: model.isRunning,
                showsLabel: showsOperatorLabels
            ) {
                model.toggleOperator(.clipboard)
            }
            UntypeOperatorChip(
                letter: "I",
                label: "Input",
                isOn: model.settings.focusedInput,
                isRecording: model.isRunning,
                showsLabel: showsOperatorLabels
            ) {
                model.toggleOperator(.input)
            }
            Spacer()
            Button {
                model.copyTranscriptExport()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(!model.canExportTranscript)
            Button {
                model.saveTranscriptExport()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(!model.canExportTranscript)
            Button {
                model.clearTranscriptTimeline()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(model.timeline.visibleItemCount == 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventsPane: some View {
        let filter = model.settings.selectedEventsFilter
        let filtered = filteredEvents(model.events, filter: filter)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Events")
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.events.isEmpty
                        ? "No events yet"
                        : "\(filtered.count) of \(model.events.count) shown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.copyEventsExport()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(!model.canExportEvents)
                Button {
                    model.saveEventsExport()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.canExportEvents)
            }

            HStack(spacing: 6) {
                ForEach(Self.eventsFilterChoices, id: \.value) { choice in
                    eventsFilterChip(label: choice.label, value: choice.value)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if filtered.isEmpty {
                            Text(model.events.isEmpty ? "No events yet." : "No events match the \(filter) filter.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        } else {
                            ForEach(Array(filtered.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(eventLineColor(line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .onChange(of: filtered.count) { _, count in
                    if count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
        }
    }

    private static let eventsFilterChoices: [(label: String, value: String)] = [
        ("All", "all"),
        ("Warnings", "warnings"),
        ("Provider", "provider"),
        ("Audio", "audio"),
        ("Hotkey", "hotkey"),
        ("Protocol", "protocol")
    ]

    private func eventsFilterChip(label: String, value: String) -> some View {
        let isOn = model.settings.selectedEventsFilter == value
        return Button {
            model.updateLayout(selectedEventsFilter: value)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? UntypeDesignTokens.accentAmber.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isOn ? UntypeDesignTokens.accentAmber.opacity(0.45) : Color.primary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter events by \(label)")
    }

    private func filteredEvents(_ events: [String], filter: String) -> [String] {
        switch filter {
        case "warnings":
            return events.filter { $0.localizedCaseInsensitiveContains("warning") || $0.localizedCaseInsensitiveContains("error") }
        case "provider":
            return events.filter {
                let lower = $0.lowercased()
                return lower.contains("soniox") || lower.contains("elevenlabs") || lower.contains("llm") || lower.contains("provider") || lower.contains("stt")
            }
        case "audio":
            return events.filter { $0.localizedCaseInsensitiveContains("audio") || $0.localizedCaseInsensitiveContains("capture") || $0.localizedCaseInsensitiveContains("mic") }
        case "hotkey":
            return events.filter { $0.localizedCaseInsensitiveContains("hotkey") || $0.localizedCaseInsensitiveContains("ptt") || $0.localizedCaseInsensitiveContains("push") }
        case "protocol":
            return events.filter { $0.localizedCaseInsensitiveContains("protocol") || $0.localizedCaseInsensitiveContains("operator") || $0.localizedCaseInsensitiveContains("section") }
        default:
            return events
        }
    }

    private func eventLineColor(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") { return UntypeDesignTokens.recordingRed }
        if lower.contains("warning") { return UntypeDesignTokens.warnGold }
        return .primary
    }

    private var historyPane: some View {
        let history = model.timeline.conversationHistory
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(.system(size: 15, weight: .semibold))
                    Text(history.isEmpty ? "No conversation history yet" : "\(history.count) retained conversations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.clearTranscriptTimeline()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(model.timeline.visibleItemCount == 0)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if history.isEmpty {
                            Text("No conversations recorded in this session.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
                        } else {
                            ForEach(history) { turn in
                                conversationHistoryTurnView(turn)
                                    .id(turn.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .onChange(of: model.timeline.conversationHistoryItemCount) { _, _ in
                    if let last = model.timeline.conversationHistory.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
        }
    }

    private func timelineTurnView(_ turn: UntypeUITimelineTurn) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(turn.time)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(turn.sealed ? "closed" : "open")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(turn.sealed ? Color.secondary : UntypeDesignTokens.accentAmber)
            }
            .frame(width: 44, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(turn.bubbles) { bubble in
                    timelineBubbleView(bubble)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func conversationHistoryTurnView(_ turn: UntypeUIConversationHistoryTurn) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left gutter: time + status
            VStack(alignment: .trailing, spacing: 3) {
                Text(turn.time)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(turn.status)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(historyStatusColor(turn.status))
                    .textCase(.uppercase)
            }
            .frame(width: 56, alignment: .trailing)

            // Main column
            VStack(alignment: .leading, spacing: 6) {
                Text(turn.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if let userText = turn.userText {
                    conversationHistorySection(
                        title: "User said",
                        status: "recorded",
                        text: userText,
                        accent: .secondary,
                        background: Color.primary.opacity(0.04)
                    )
                }
                ForEach(turn.records) { record in
                    conversationHistorySection(
                        title: record.label,
                        status: record.status,
                        text: record.text,
                        accent: record.kind == .issue ? UntypeDesignTokens.warnGold : UntypeDesignTokens.accentAmber,
                        background: record.kind == .issue ? UntypeDesignTokens.warnGold.opacity(0.12) : UntypeDesignTokens.accentAmber.opacity(0.08)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerMedium, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05))
        )
    }

    private func conversationHistorySection(
        title: String,
        status: String,
        text: String,
        accent: Color,
        background: Color
    ) -> some View {
        let isLong = text.count > 280
        return Group {
            if isLong {
                DisclosureGroup {
                    Text(text)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                } label: {
                    historyRowHeader(title: title, status: status, accent: accent, preview: String(text.prefix(120)))
                }
                .padding(8)
                .background(background, in: RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerSmall, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    historyRowHeader(title: title, status: status, accent: accent, preview: nil)
                    Text(text)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(8)
                .background(background, in: RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerSmall, style: .continuous))
            }
        }
    }

    private func historyRowHeader(title: String, status: String, accent: Color, preview: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .textCase(.uppercase)
                .tracking(0.5)
            if let preview {
                Text("· \(preview)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Text(status)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func historyStatusColor(_ status: String) -> Color {
        let lower = status.lowercased()
        if lower.contains("warn") || lower.contains("issue") || lower.contains("error") { return UntypeDesignTokens.warnGold }
        if lower.contains("closed") || lower.contains("done") || lower.contains("recorded") { return UntypeDesignTokens.accentAmber }
        return .secondary
    }

    private func timelineBubbleView(_ bubble: UntypeUITimelineBubble) -> some View {
        Group {
            switch bubble.kind {
            case .raw:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("RAW")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(bubble.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .processed:
                VStack(alignment: .leading, spacing: 4) {
                    if !bubble.label.isEmpty || !bubble.status.isEmpty {
                        HStack(spacing: 6) {
                            Text(bubble.label)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(UntypeDesignTokens.accentAmber)
                                .textCase(.uppercase)
                            Text(bubble.status)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(bubble.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(UntypeDesignTokens.accentAmber)
                        .frame(width: 2)
                }
            case .error:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(UntypeDesignTokens.warnGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bubble.label.isEmpty ? "Issue" : bubble.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(UntypeDesignTokens.warnGold)
                            .textCase(.uppercase)
                        Text(bubble.text)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(9)
                .background(UntypeDesignTokens.warnGold.opacity(0.12), in: RoundedRectangle(cornerRadius: UntypeDesignTokens.cornerSmall, style: .continuous))
            }
        }
    }

    private func livePartialView(_ partial: UntypeUILivePartial) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .center, spacing: 0) {
                UntypeStatusDot(tone: model.isRunning ? .recording : .off, size: 7)
                    .padding(.top, 5)
            }
            .frame(width: 44, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.isRunning ? "LIVE · PARTIAL" : "IDLE · WAITING")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.isRunning ? UntypeDesignTokens.recordingRed : .secondary)
                    .tracking(0.7)
                Text(partial.text.isEmpty ? "Press the hotkey or click Start Listening to begin." : partial.text)
                    .font(.system(size: 14))
                    .italic(partial.text.isEmpty)
                    .foregroundStyle(partial.text.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var settingsPane: some View {
        let availability = UntypeUIControlAvailability(isSessionActive: model.isRunning)
        let sessionShapingDisabled = !availability.sessionShapingControlsEnabled
        let operatorControlsDisabled = !availability.protocolOperatorControlsEnabled

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Session — read-only summary
                inspectorGroup("Session") {
                    inspectorStatusRow("State", value: model.sessionState, tone: UntypeStatusToneMap.session(isRunning: model.isRunning, isHotkeyPressed: model.hotkeyPressed))
                    inspectorMonoRow("Mode", value: model.settings.protocolMode)
                    inspectorMonoRow("STT provider", value: model.settings.provider)
                    inspectorMonoRow("Model", value: model.settings.model)
                    inspectorMonoRow("Languages", value: model.settings.languages.joined(separator: " · "))
                    inspectorMonoRow("Sample rate", value: "\(model.settings.sampleRate) Hz")
                    inspectorMonoRow("Endpoint detection", value: model.settings.endpointDetection ? "on" : "off")
                    inspectorMonoRow("Audio", value: model.audioStatus)
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
                        inspectorToggleRow("Refine", isOn: binding(\.refine))
                        inspectorToggleRow("Translate", isOn: binding(\.translate))
                        inspectorToggleRow("Clipboard", isOn: binding(\.clipboard))
                        inspectorToggleRow("Focused input", isOn: binding(\.focusedInput))
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
        }
        .frame(width: 320)
        .background(.thinMaterial)
        .overlay(alignment: .leading) {
            Divider()
        }
    }

    private func inspectorGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            UntypeSectionHeader(title)
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

    private var audioLevelLabel: String {
        let lower = model.audioStatus.lowercased()
        if let percentRange = lower.range(of: #"\d+%"#, options: .regularExpression) {
            return String(lower[percentRange])
        }
        if model.isRunning { return "live" }
        return "silent"
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

    private var monitorTabBinding: Binding<String> {
        Binding(
            get: { model.settings.selectedMonitorTab },
            set: { model.updateLayout(selectedMonitorTab: $0) }
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
    private let layout = UntypeOverlayLayout()
    private var bottomLeftAnchor: CGPoint?
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
        let wasVisible = panel?.isVisible == true
        if panel == nil {
            createPanel()
        }
        applyPanelFrameIfNeeded()
        if !wasVisible {
            panel?.orderFrontRegardless()
        }
    }

    func refreshOperators() {
        operatorVersion += 1
        applyPanelFrameIfNeeded()
    }

    func refreshTheme() {
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
        bottomLeftAnchor = nil
        panel?.orderOut(nil)
    }

    func destroy() {
        hideTask?.cancel()
        panel?.close()
        panel = nil
        bottomLeftAnchor = nil
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: layout.width, height: layout.height),
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
        let hostingView = NSHostingView(rootView: UntypeOverlayView(controller: self))
        hostingView.frame = NSRect(x: 0, y: 0, width: layout.width, height: layout.height)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        self.panel = panel
    }

    private func applyPanelFrameIfNeeded() {
        guard let panel else {
            return
        }
        let screen = overlayScreen()
        guard let screen else {
            return
        }
        if panel.isVisible {
            let currentFrame = panel.frame
            let anchor = bottomLeftAnchor ?? CGPoint(x: currentFrame.minX, y: currentFrame.minY)
            bottomLeftAnchor = anchor
            let targetFrame = layout.anchoredPanelFrame(
                bottomLeft: anchor,
                text: text,
                in: screen.visibleFrame,
                currentHeight: currentFrame.height
            )
            if !framesMatch(currentFrame, targetFrame) {
                panel.setFrame(targetFrame, display: true)
            }
            return
        }
        let frame = layout.initialPanelFrame(in: screen.visibleFrame, text: text)
        bottomLeftAnchor = CGPoint(x: frame.minX, y: frame.minY)
        panel.setFrame(frame, display: true)
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    private func overlayScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    fileprivate var overlayPhase: String {
        phase
    }

    fileprivate var overlayText: String {
        text
    }

    fileprivate var overlaySize: CGSize {
        panel?.frame.size ?? CGSize(width: layout.width, height: layout.height)
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

    fileprivate var preferredColorScheme: ColorScheme? {
        switch model?.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

@MainActor
private struct UntypeOverlayView: View {
    @ObservedObject var controller: UntypeOverlayController

    private var isRecording: Bool {
        controller.overlayPhase.lowercased() == "recording"
    }

    private var phaseTone: UntypeStatusTone {
        switch controller.overlayPhase.lowercased() {
        case "recording": return .recording
        case "finalizing", "processed": return .accent
        default: return .ok
        }
    }

    private var overlayBorderColor: Color {
        switch phaseTone {
        case .recording:
            return UntypeDesignTokens.recordingRed
        case .accent:
            return UntypeDesignTokens.accentAmber
        case .ok:
            return UntypeDesignTokens.successGreen
        case .warn:
            return UntypeDesignTokens.warnGold
        case .off:
            return Color.primary.opacity(0.08)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Live transcript line — top region, leaves room at the bottom for chips and phase.
            Text(controller.overlayText.isEmpty ? " " : controller.overlayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.horizontal, 14)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .textSelection(.disabled)

            // Bottom-left: operator chips
            HStack(spacing: 5) {
                ForEach(controller.operatorSnapshot, id: \.label) { item in
                    overlayOperatorIndicator(letter: item.label, enabled: item.enabled)
                }
            }
            .padding(.leading, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Bottom-right: phase indicator
            HStack(spacing: 6) {
                UntypeStatusDot(tone: phaseTone, size: 7)
                Text(controller.overlayPhase)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(phaseTone.color)
                    .tracking(0.6)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(phaseTone.color.opacity(0.30), lineWidth: 1)
            )
            .padding(.trailing, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .accessibilityLabel("Phase \(controller.overlayPhase)")
        }
        .frame(width: controller.overlaySize.width, height: controller.overlaySize.height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(overlayBorderColor.opacity(isRecording ? 0.10 : 0.05))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(overlayBorderColor.opacity(isRecording ? 0.55 : 0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 10)
        .preferredColorScheme(controller.preferredColorScheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Push to talk overlay")
    }

    private func overlayOperatorIndicator(letter: String, enabled: Bool) -> some View {
        HStack(spacing: 5) {
            UntypeStatusDot(tone: !enabled ? .off : (isRecording ? .recording : .accent), size: 5)
            Text(letter)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(enabled ? UntypeDesignTokens.accentAmber : Color.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(
            Capsule(style: .continuous)
                .fill(enabled ? UntypeDesignTokens.accentAmber.opacity(0.16) : Color.primary.opacity(0.04))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(enabled ? UntypeDesignTokens.accentAmber.opacity(0.45) : Color.primary.opacity(0.10))
        )
        .accessibilityLabel("Operator \(letter), \(enabled ? "on" : "off")")
    }
}

// MARK: - Onboarding sheet

@MainActor
private struct UntypeOnboardingView: View {
    @ObservedObject var model: UntypeUIModel
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                UntypeBrandMark(size: 52)
                VStack(alignment: .leading, spacing: 6) {
                    Text("WELCOME")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(UntypeDesignTokens.accentAmber)
                        .tracking(1.2)
                    Text("Hold a key. Speak.\nType with your voice.")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("untype is a Swift-native dictation companion for macOS. Push-to-talk in any app, with optional LLM refinement, translation, and clipboard or focused-input delivery.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 520, alignment: .leading)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                onboardingStep(
                    number: 1,
                    title: "Microphone access",
                    body: "Required for AVAudioEngine to capture input.",
                    tone: UntypeStatusToneMap.microphone(model.settings.microphoneStatus),
                    actionLabel: needsMic ? "Grant" : nil,
                    deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
                onboardingStep(
                    number: 2,
                    title: "Accessibility trust",
                    body: "Lets untype install a Quartz event-tap for the push-to-talk hotkey.",
                    tone: UntypeStatusToneMap.accessibility(model.settings.accessibilityStatus),
                    actionLabel: needsAccessibility ? "Grant" : nil,
                    deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                onboardingStep(
                    number: 3,
                    title: "Provider credentials",
                    body: "At least one STT key (Soniox or ElevenLabs) and an LLM key if you want refinement.",
                    tone: UntypeStatusToneMap.credential(model.settings.apiKeyStatus),
                    actionLabel: needsCredential ? "Open .env" : nil,
                    deepLink: nil
                )
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    UntypeSectionHeader("Push-to-talk hotkey")
                    HStack(spacing: 8) {
                        ForEach(hotkeyTokens, id: \.self) { token in
                            UntypeKbd(token)
                                .scaleEffect(1.15, anchor: .leading)
                                .padding(.trailing, 4)
                        }
                        Button("Change…") {
                            // Defer to inspector; this is a hint, not a binding.
                        }
                        .buttonStyle(.borderless)
                    }
                    Text("Hold to record, release to submit. Auto-warms a new provider session after each turn.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(maxHeight: 88)

                VStack(alignment: .leading, spacing: 8) {
                    UntypeSectionHeader("Config search path")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLI flag").foregroundStyle(.secondary)
                        Text("./.env").foregroundStyle(.secondary)
                        Text("~/.tool-agents/untype/.env").foregroundStyle(UntypeDesignTokens.accentAmber)
                        Text("shell environment").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )

            HStack(spacing: 10) {
                Text(footerSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip for now") {
                    Self.markSkipped()
                    onDismiss()
                }
                Button(primaryActionTitle) {
                    if let url = primaryActionURL {
                        NSWorkspace.shared.open(url)
                    } else {
                        model.refreshCredentials()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(UntypeDesignTokens.accentAmber)
            }
        }
        .padding(32)
        .frame(width: 760, height: 560)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }

    private var hotkeyTokens: [String] {
        let separator: Character = model.settings.hotkey.contains("+") ? "+" : "-"
        return model.settings.hotkey.split(separator: separator).map { String($0) }
    }

    private var needsMic: Bool {
        UntypeStatusToneMap.microphone(model.settings.microphoneStatus) != .ok
    }

    private var needsAccessibility: Bool {
        UntypeStatusToneMap.accessibility(model.settings.accessibilityStatus) != .ok
    }

    private var needsCredential: Bool {
        UntypeStatusToneMap.credential(model.settings.apiKeyStatus) != .ok
    }

    private var readyCount: Int {
        [!needsMic, !needsAccessibility, !needsCredential].filter { $0 }.count
    }

    private var footerSummary: String {
        "\(readyCount) of 3 ready · macOS 14+ · Swift 6 · untype"
    }

    private var primaryActionTitle: String {
        if needsAccessibility { return "Grant Accessibility" }
        if needsMic { return "Grant Microphone" }
        if needsCredential { return "Refresh credentials" }
        return "Get started"
    }

    private var primaryActionURL: URL? {
        if needsAccessibility { return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
        if needsMic { return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }
        return nil
    }

    private func onboardingStep(
        number: Int,
        title: String,
        body: String,
        tone: UntypeStatusTone,
        actionLabel: String?,
        deepLink: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(UntypeDesignTokens.accentAmber)
                    .frame(width: 22, height: 22)
                    .background(UntypeDesignTokens.accentAmber.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Spacer()
                HStack(spacing: 5) {
                    UntypeStatusDot(tone: tone, size: 6)
                    Text(tone == .ok ? "ready" : tone == .warn ? "action" : "set up")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(tone.color)
                        .textCase(.uppercase)
                        .tracking(0.4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tone.color.opacity(0.14), in: Capsule(style: .continuous))
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel {
                Button(actionLabel) {
                    if let link = deepLink, let url = URL(string: link) {
                        NSWorkspace.shared.open(url)
                    } else {
                        model.refreshCredentials()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    // Onboarding skip persistence — non-secret, 24h re-prompt suppression.
    private static let skipKey = "untype.onboardingSkippedAt"

    static func markSkipped() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: skipKey)
    }

    static func recentlySkipped() -> Bool {
        let skippedAt = UserDefaults.standard.double(forKey: skipKey)
        guard skippedAt > 0 else { return false }
        return (Date().timeIntervalSince1970 - skippedAt) < 24 * 60 * 60
    }
}

// MARK: - Compact mini window view

@MainActor
private struct UntypeMiniView: View {
    @ObservedObject var model: UntypeUIModel

    private var isRecording: Bool { model.isRunning }
    private var liveText: String { model.timeline.partial?.text ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                UntypeBrandMark(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        UntypeStatusDot(tone: isRecording ? .recording : .accent, size: 6)
                        Text(isRecording ? "RECORDING" : "WARM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(isRecording ? UntypeDesignTokens.recordingRed : UntypeDesignTokens.accentAmber)
                            .tracking(0.7)
                        Text("· \(model.settings.provider)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(model.sessionState)
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                UntypeRecordButton(
                    isRecording: model.isRunning,
                    titleIdle: "Listen",
                    titleRecording: "Stop"
                ) {
                    model.isRunning ? model.stopPrimarySession() : model.startManualSession()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isRecording ? "LIVE · PARTIAL" : "IDLE")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isRecording ? UntypeDesignTokens.recordingRed : .secondary)
                    .tracking(0.7)
                Text(liveText.isEmpty ? "press \(model.settings.hotkey)" : liveText)
                    .font(.system(size: 13))
                    .italic(liveText.isEmpty)
                    .foregroundStyle(liveText.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 6) {
                UntypeOperatorChip(letter: "R", label: "Refine", isOn: model.settings.refine, isRecording: isRecording, isCompact: true) {
                    model.toggleOperator(.refine)
                }
                UntypeOperatorChip(letter: "T", label: "Translate", isOn: model.settings.translate, isRecording: isRecording, isCompact: true) {
                    model.toggleOperator(.translate)
                }
                UntypeOperatorChip(letter: "C", label: "Clipboard", isOn: model.settings.clipboard, isRecording: isRecording, isCompact: true) {
                    model.toggleOperator(.clipboard)
                }
                UntypeOperatorChip(letter: "I", label: "Input", isOn: model.settings.focusedInput, isRecording: isRecording, isCompact: true) {
                    model.toggleOperator(.input)
                }
                Spacer()
                UntypeWaveformView(isActive: isRecording, barCount: 18, height: 20)
                Text(isRecording ? "live" : "silent")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isRecording ? UntypeDesignTokens.recordingRed : .secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 440, minHeight: 220)
        .background(.regularMaterial)
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
