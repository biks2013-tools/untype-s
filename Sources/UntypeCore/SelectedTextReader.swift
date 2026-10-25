import AppKit
import ApplicationServices
import Foundation

/// Reads the text selected in the frontmost app at push-to-talk press time
/// (Selection operator).
@MainActor
enum SelectedTextReader {
    enum AccessibilityResult: Equatable {
        /// The focused element reports a non-empty selection.
        case selected(String)
        /// The focused element supports selections and nothing is selected.
        case nothingSelected
        /// No focused element, or it does not expose `AXSelectedText`
        /// (terminals, some Electron apps): only a copy can tell.
        case unsupported
    }

    /// `AXSelectedText` of the system-wide focused element. No side effects.
    static func readAccessibility() -> AccessibilityResult {
        let system = AXUIElementCreateSystemWide()
        // A hung app must not stall the press.
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            return .unsupported
        }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String
        else {
            return .unsupported
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .nothingSelected : .selected(text)
    }

    /// Copies the selection with a synthetic ⌘C, reads it, and puts the
    /// previous pasteboard contents back. nil when the app copied nothing.
    static func readByCopying(timeout: Duration = .milliseconds(300)) async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        let before = pasteboard.changeCount
        postKey(keyCode: 8, flags: .maskCommand) // C
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard pasteboard.changeCount != before else {
            return nil
        }
        let text = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        if !saved.isEmpty {
            pasteboard.writeObjects(saved)
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    /// Moves the caret to the end of the selection (Right arrow), so text
    /// typed next is inserted after it instead of replacing it.
    static func collapseSelectionToEnd() {
        postKey(keyCode: 124, flags: [])
    }

    /// Marked like live typing, so the hotkey monitors ignore it; a
    /// private-state source keeps the held push-to-talk modifier out.
    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: untypeSyntheticKeyboardEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
