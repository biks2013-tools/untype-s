import AppKit
import Foundation

/// The menu-bar icon and the two ways the untype window is presented:
///
/// - **attached**: dropped down under the menu-bar icon like a popover — not
///   movable, no window buttons, hidden again when another app becomes active
///   or the icon is clicked;
/// - **detached** ("popped out"): an ordinary movable window that stays open;
///   clicking the icon or closing the window docks it back.
///
/// One window serves both modes, so the full and compact layouts (and their
/// window toolbar) look the same either way. Whether the window was detached
/// is remembered: a detached window is reopened at the next launch.
@MainActor
final class UntypeMenuBarController: NSObject {
    static let detachedDefaultsKey = "untype.windowDetached"
    private static let detachedFrameAutosaveName = "untype.detachedWindow"
    private static let attachedGap: CGFloat = 6

    private let window: NSWindow
    private let statusItem: NSStatusItem
    private let onDetachedChange: (Bool) -> Void
    private var resignObserver: NSObjectProtocol?
    /// When the attached window was last hidden because untype lost focus.
    /// Pressing the menu-bar icon deactivates untype before the click action
    /// runs, so a click right after that auto-hide means "close", not "reopen".
    private var autoHiddenAt: TimeInterval?
    private(set) var isDetached = false

    init(window: NSWindow, onDetachedChange: @escaping (Bool) -> Void) {
        self.window = window
        self.onDetachedChange = onDetachedChange
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "untype"
        }
        setRecording(false)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hideIfAttached()
            }
        }
    }

    /// Launch presentation: reopen the detached window when it was detached at
    /// quit, open the attached window when setup is needed, else stay quiet.
    func presentAtLaunch(needsSetup: Bool) {
        if UserDefaults.standard.bool(forKey: Self.detachedDefaultsKey) {
            popOut()
        } else if needsSetup {
            showAttached()
        }
    }

    func setRecording(_ recording: Bool) {
        let name = recording ? "waveform.badge.mic" : "waveform"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: recording ? "untype, recording" : "untype")
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "untype")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    /// Pop-out button in the UI: detach when attached, dock back when detached.
    func toggleDetached() {
        if isDetached {
            dockBack(show: true)
        } else {
            popOut()
        }
    }

    /// The window's close button / Cmd+W: never closes the window (the app
    /// lives in the menu bar); a detached window docks back, an attached one hides.
    func handleCloseRequest() {
        if isDetached {
            dockBack(show: false)
        } else {
            window.orderOut(nil)
        }
    }

    /// Keeps the attached window under the icon after a size change (compact
    /// mode toggles resize the window).
    func windowDidChangeSize() {
        if !isDetached, window.isVisible {
            positionUnderStatusItem()
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        if isDetached {
            dockBack(show: true)
        } else if window.isVisible {
            window.orderOut(nil)
        } else if let hiddenAt = autoHiddenAt, ProcessInfo.processInfo.systemUptime - hiddenAt < 0.4 {
            autoHiddenAt = nil
        } else {
            showAttached()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show untype", action: #selector(showFromMenu), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let detach = NSMenuItem(
            title: isDetached ? "Dock Window to Menu Bar" : "Pop Out into a Window",
            action: #selector(toggleDetachedFromMenu),
            keyEquivalent: ""
        )
        detach.target = self
        menu.addItem(detach)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit untype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showFromMenu() {
        if isDetached {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            showAttached()
        }
    }

    @objc private func toggleDetachedFromMenu() {
        toggleDetached()
    }

    private func showAttached() {
        applyAttachedStyle()
        positionUnderStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func popOut() {
        let wasVisible = window.isVisible
        setDetached(true)
        window.level = .normal
        window.isMovable = true
        setWindowButtonsHidden(false)
        if !window.setFrameUsingName(Self.detachedFrameAutosaveName), !wasVisible {
            window.center()
        }
        window.setFrameAutosaveName(Self.detachedFrameAutosaveName)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func dockBack(show: Bool) {
        window.saveFrame(usingName: Self.detachedFrameAutosaveName)
        window.setFrameAutosaveName("")
        setDetached(false)
        window.orderOut(nil)
        if show {
            showAttached()
        }
    }

    private func hideIfAttached() {
        if !isDetached, window.isVisible {
            window.orderOut(nil)
            autoHiddenAt = ProcessInfo.processInfo.systemUptime
        }
    }

    private func setDetached(_ detached: Bool) {
        isDetached = detached
        UserDefaults.standard.set(detached, forKey: Self.detachedDefaultsKey)
        onDetachedChange(detached)
    }

    private func applyAttachedStyle() {
        window.level = .floating
        window.isMovable = false
        setWindowButtonsHidden(true)
    }

    private func setWindowButtonsHidden(_ hidden: Bool) {
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    /// Top edge just under the icon, horizontally centred on it and kept
    /// inside the screen; a window taller or wider than the screen is shrunk.
    private func positionUnderStatusItem() {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            window.center()
            return
        }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = buttonWindow.screen ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width - 16)
        frame.size.height = min(frame.height, visible.maxY - Self.attachedGap - visible.minY)
        frame.origin.x = min(max(buttonFrame.midX - frame.width / 2, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = min(buttonFrame.minY, visible.maxY) - Self.attachedGap - frame.height
        window.setFrame(frame, display: true)
    }
}
