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

    /// The element and range of the current Accessibility selection, so the
    /// selection can be replaced later even if focus has moved (Push-to-Act
    /// shows a pop-up in between). nil when the focused element does not
    /// report both `AXSelectedText` (equal to `text`) and `AXSelectedTextRange`.
    static func captureAnchor(expectedText text: String) -> SelectionAnchor? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var selected: CFTypeRef?
        var rangeValue: CFTypeRef?
        var range = CFRange()
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              selected as? String == text,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              AXValueGetValue(unsafeBitCast(rangeValue, to: AXValue.self), .cfRange, &range),
              range.length > 0
        else {
            return nil
        }
        return SelectionAnchor(element: element, range: range, text: text)
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

/// A selection captured through Accessibility: its element, range and text.
/// `replace(with:)` writes into that element directly, independent of which
/// window has the keyboard focus at delivery time.
final class SelectionAnchor: @unchecked Sendable {
    private let element: AXUIElement
    private let range: CFRange
    private let text: String

    init(element: AXUIElement, range: CFRange, text: String) {
        self.element = element
        self.range = range
        self.text = text
    }

    /// Re-selects the captured range and replaces it with `replacement`.
    /// Returns nil (nothing written) when the element is gone, the range no
    /// longer holds the captured text, or the control ignored the write;
    /// the caller then falls back to ordinary focused-input delivery.
    func replace(with replacement: String) -> FocusedInputDeliveryResult? {
        AXUIElementSetMessagingTimeout(element, 1.0)
        var range = self.range
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success
        else {
            return nil
        }
        var selected: CFTypeRef?
        var settable = DarwinBoolean(false)
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              selected as? String == text,
              AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue
        else {
            return nil
        }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString) == .success else {
            return nil
        }
        // A control that accepts the write but changes nothing still holds
        // the captured text at the range: report failure so the caller falls
        // back. Any other state means the replacement landed (never write twice).
        if let value = stringValue(), let original = substring(value, location: self.range.location, length: text.utf16.count),
           original == text, replacement != text {
            return nil
        }
        return .success(
            method: "ax-selection",
            targetRole: stringAttribute(kAXRoleAttribute),
            targetSubrole: stringAttribute(kAXSubroleAttribute)
        )
    }

    private func stringValue() -> String? {
        stringAttribute(kAXValueAttribute)
    }

    private func stringAttribute(_ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func substring(_ value: String, location: Int, length: Int) -> String? {
        let string = value as NSString
        guard location >= 0, location + length <= string.length else {
            return nil
        }
        return string.substring(with: NSRange(location: location, length: length))
    }
}
