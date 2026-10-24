import AppKit
import Foundation
import SwiftUI

/// The menu-bar icon. A left click toggles the dropdown (`UntypeMenuBarPanel`,
/// in a transient popover): the everyday switches, the hotkeys, and the way
/// into the Transcript / History window and the Settings window. A right click
/// shows a short menu with the same destinations.
///
/// The main window is an ordinary window opened from the dropdown. Whether it
/// was open is remembered: an open window is reopened at the next launch.
@MainActor
final class UntypeMenuBarController: NSObject, NSPopoverDelegate {
    /// Key kept from the earlier "popped out" window so the state carries over.
    static let windowOpenDefaultsKey = "untype.windowDetached"
    private static let windowFrameAutosaveName = "untype.detachedWindow"

    private let window: NSWindow
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let openTab: (String) -> Void
    private let openSettings: () -> Void

    /// - Parameters:
    ///   - openTab: shows the main window at a monitor tab.
    ///   - openSettings: shows the Settings window.
    init(
        window: NSWindow,
        model: UntypeUIModel,
        openTab: @escaping (String) -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.window = window
        self.openTab = openTab
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "untype"
        }
        setRecording(false)

        if !window.setFrameUsingName(Self.windowFrameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.windowFrameAutosaveName)

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let panel = UntypeMenuBarPanel(
            model: model,
            openTranscript: { [weak self] in self?.choose { $0.openTab("transcript") } },
            openHistory: { [weak self] in self?.choose { $0.openTab("history") } },
            openSettings: { [weak self] in self?.choose { $0.openSettings() } },
            quit: { NSApp.terminate(nil) }
        )
        let host = NSHostingController(rootView: panel)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    /// Launch presentation: reopen the window when it was open at quit or
    /// setup is needed, else stay in the menu bar.
    func presentAtLaunch(needsSetup: Bool) {
        if UserDefaults.standard.bool(forKey: Self.windowOpenDefaultsKey) || needsSetup {
            showWindow()
        }
    }

    func setRecording(_ recording: Bool) {
        let name = recording ? "waveform.badge.mic" : "waveform"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: recording ? "untype, recording" : "untype")
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "untype")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func showWindow() {
        UserDefaults.standard.set(true, forKey: Self.windowOpenDefaultsKey)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window's close button / Cmd+W: hide it; the app lives in the menu bar.
    func handleCloseRequest() {
        UserDefaults.standard.set(false, forKey: Self.windowOpenDefaultsKey)
        window.orderOut(nil)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Opens the destination first, then closes the dropdown, so the close
    /// handler sees a visible window and keeps untype active.
    private func choose(_ open: (UntypeMenuBarController) -> Void) {
        open(self)
        popover.performClose(nil)
    }

    /// Closed with Escape or by clicking the icon again: untype was activated
    /// to show the dropdown, so hand the focus back to the previous app unless
    /// an untype window is open.
    func popoverDidClose(_ notification: Notification) {
        let hasOpenWindow = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if NSApp.isActive, !hasOpenWindow {
            NSApp.hide(nil)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Transcript", #selector(openTranscriptFromMenu), key: "1"))
        menu.addItem(menuItem("History", #selector(openHistoryFromMenu), key: "2"))
        menu.addItem(menuItem("Settings…", #selector(openSettingsFromMenu), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit untype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openTranscriptFromMenu() {
        openTab("transcript")
    }

    @objc private func openHistoryFromMenu() {
        openTab("history")
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }
}
