import AppKit
import ApplicationServices
import Foundation

/// The sentence around the caret at push-to-talk press time: the part before
/// the caret and the part after it. With Refine on, the dictation is refined
/// together with both parts and the result replaces the whole sentence.
public struct SentenceSpan: Equatable, Sendable {
    /// UTF-16 offset of the sentence start in the field's text.
    public let location: Int
    public let before: String
    public let after: String

    /// Longest part (UTF-16 units) on either side of the caret; longer text
    /// without sentence punctuation is not treated as a sentence.
    public static let maxPartLength = 1500

    public init(location: Int, before: String, after: String) {
        self.location = location
        self.before = before
        self.after = after
    }

    /// UTF-16 length of the sentence as captured.
    public var length: Int {
        before.utf16.count + after.utf16.count
    }

    /// The sentence around `caret` (a UTF-16 offset) in `text`. nil when the
    /// caret is not inside a sentence (start of a line or right after a
    /// finished sentence, with nothing after it) or a part is too long.
    public static func around(caret: Int, in text: String) -> SentenceSpan? {
        let units = Array(text.utf16)
        guard caret >= 0, caret <= units.count else {
            return nil
        }
        var start = 0
        var index = caret - 1
        while index >= 0 {
            let unit = units[index]
            if isNewline(unit) {
                start = index + 1
                break
            }
            if isTerminator(unit) {
                let afterClosers = skipClosers(units, from: index + 1, limit: caret)
                if index + 1 == caret || afterClosers == units.count || isWhitespace(units[afterClosers]) {
                    start = afterClosers
                    break
                }
            }
            index -= 1
        }
        while start < caret, isWhitespace(units[start]) {
            start += 1
        }
        var end = units.count
        index = caret
        while index < units.count {
            let unit = units[index]
            if isNewline(unit) {
                end = index
                break
            }
            if isTerminator(unit) {
                let afterClosers = skipClosers(units, from: index + 1, limit: units.count)
                if afterClosers == units.count || isWhitespace(units[afterClosers]) {
                    end = afterClosers
                    break
                }
            }
            index += 1
        }
        while end > caret, isWhitespace(units[end - 1]) {
            end -= 1
        }
        guard caret - start <= maxPartLength, end - caret <= maxPartLength else {
            return nil
        }
        let before = String(utf16CodeUnits: Array(units[start..<caret]), count: caret - start)
        let after = String(utf16CodeUnits: Array(units[caret..<end]), count: end - caret)
        guard !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return SentenceSpan(location: start, before: before, after: after)
    }

    /// The whole sentence with `dictation` at the caret. A full stop the
    /// recognizer put at the end of the dictation is dropped when the
    /// sentence continues after the caret.
    public func compose(dictation: String) -> String {
        var spoken = dictation.trimmingCharacters(in: .whitespacesAndNewlines)
        let continues = !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if continues, let last = spoken.last, last == "." || last == "…", !spoken.hasSuffix("..") {
            spoken.removeLast()
        }
        var text = before
        if let last = before.last, !last.isWhitespace, !"([{«“\"'".contains(last) {
            text += " "
        }
        text += spoken
        if let first = after.first, !first.isWhitespace, !".,;:!?…)]}»”".contains(first) {
            text += " "
        }
        return text + after
    }

    /// The part of `processed` (the processed whole sentence) that stands
    /// where the dictation was, when both captured parts survived unchanged.
    /// Used when the sentence cannot be replaced in the field.
    public func dictationOnly(from processed: String) -> String? {
        let head = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= head.count + tail.count, text.hasPrefix(head), text.hasSuffix(tail) else {
            return nil
        }
        let middle = String(text.dropFirst(head.count).dropLast(tail.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return middle.isEmpty ? nil : middle
    }

    private static func skipClosers(_ units: [UInt16], from start: Int, limit: Int) -> Int {
        var index = start
        while index < limit, isCloser(units[index]) {
            index += 1
        }
        return index
    }

    private static func isNewline(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0 || isNewline(unit)
    }

    /// . ! ? ; … and the Greek question mark.
    private static func isTerminator(_ unit: UInt16) -> Bool {
        unit == 0x2E || unit == 0x21 || unit == 0x3F || unit == 0x3B || unit == 0x2026 || unit == 0x037E
    }

    /// " ' ) ] } » ” ’
    private static func isCloser(_ unit: UInt16) -> Bool {
        unit == 0x22 || unit == 0x27 || unit == 0x29 || unit == 0x5D || unit == 0x7D
            || unit == 0xBB || unit == 0x201D || unit == 0x2019
    }
}

/// What focused-input delivery does with a turn whose text is a whole
/// sentence (the dictation refined together with the sentence around it).
public enum SentenceDeliveryPlan: Equatable, Sendable {
    /// The turn's text is the dictation only: deliver it the regular way.
    case notUsed
    /// The sentence is selected in the field: inserting the text replaces it.
    case regionSelected
    /// The sentence could not be selected: deliver this text (the dictation
    /// part only) the regular way.
    case dictationOnly(String)
}

/// The focused control and the sentence around its caret, captured at
/// push-to-talk press time. `selectRegion()` selects that sentence again at
/// delivery time, including whatever was typed live at the caret meanwhile.
@MainActor
final class SentenceAnchor {
    /// Terminals: their text area holds the screen, not an editable sentence.
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.cmuxterm.app",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper"
    ]

    let span: SentenceSpan
    private let element: AXUIElement
    /// The field's text before and after the sentence, to recognize the
    /// sentence again at delivery time.
    private let head: String
    private let tail: String

    private init(element: AXUIElement, span: SentenceSpan, head: String, tail: String) {
        self.element = element
        self.span = span
        self.head = head
        self.tail = tail
    }

    enum Capture {
        case captured(SentenceAnchor)
        /// Why not, for the event log (no text content).
        case notCaptured(String)
    }

    /// The sentence around the caret of the focused control of `app`. Not
    /// captured when there is no such control, it is a terminal or a
    /// password field, it has a selection, its selection cannot be set, or
    /// the caret is not inside a sentence. No side effects.
    static func capture(in app: NSRunningApplication) -> Capture {
        if let bundleIdentifier = app.bundleIdentifier, terminalBundleIdentifiers.contains(bundleIdentifier) {
            return .notCaptured("terminal")
        }
        guard let element = CaretLocator.focusedElement() else {
            return .notCaptured("the app reports no focused control")
        }
        AXUIElementSetMessagingTimeout(element, 0.25)
        let role = string(element, kAXRoleAttribute) ?? "unknown role"
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else {
            return .notCaptured("the focused control belongs to another app")
        }
        guard string(element, kAXSubroleAttribute) != (kAXSecureTextFieldSubrole as String) else {
            return .notCaptured("password field")
        }
        guard let value = string(element, kAXValueAttribute) else {
            return .notCaptured("the focused control (\(role)) reports no text")
        }
        guard let range = selectedRange(element) else {
            return .notCaptured("the focused control (\(role)) reports no cursor position")
        }
        guard range.length == 0 else {
            return .notCaptured("text is selected")
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
              settable.boolValue
        else {
            return .notCaptured("the selection of the focused control (\(role)) cannot be set")
        }
        guard let span = SentenceSpan.around(caret: range.location, in: value) else {
            return .notCaptured("the cursor is not inside a sentence (\(role), cursor at \(range.location) of \((value as NSString).length))")
        }
        let text = value as NSString
        return .captured(SentenceAnchor(
            element: element,
            span: span,
            head: text.substring(to: span.location),
            tail: text.substring(from: span.location + span.length)
        ))
    }

    enum Selection: Equatable {
        /// The sentence is selected; how ("accessibility" or "keys").
        case selected(String)
        /// Nothing is selected; why, for the event log (no text content).
        case failed(String)
    }

    /// Selects the sentence as it stands now (with the text typed live at
    /// the caret): through Accessibility, or with arrow keys where the
    /// control does not take an Accessibility selection (web views). Fails,
    /// with nothing selected, when the control is no longer the focused one
    /// or the text around the sentence or the sentence's own parts changed.
    func selectRegion() async -> Selection {
        guard let focused = CaretLocator.focusedElement() else {
            return .failed("no focused control at delivery")
        }
        guard CFEqual(focused, element) else {
            return .failed("another control has the focus at delivery")
        }
        guard let value = Self.string(element, kAXValueAttribute) else {
            return .failed("the control's text cannot be read at delivery")
        }
        let text = value as NSString
        let regionLength = text.length - (head as NSString).length - (tail as NSString).length
        guard regionLength >= span.length else {
            return .failed("the text got shorter during the dictation")
        }
        guard text.substring(to: span.location) == head,
              text.substring(from: span.location + regionLength) == tail
        else {
            return .failed("the text around the sentence changed during the dictation")
        }
        let region = text.substring(with: NSRange(location: span.location, length: regionLength))
        guard region.hasPrefix(span.before), region.hasSuffix(span.after) else {
            return .failed("the sentence itself changed during the dictation")
        }
        let original = Self.selectedRange(element)
        let wanted = CFRange(location: span.location, length: regionLength)
        var range = wanted
        if let rangeValue = AXValueCreate(.cfRange, &range),
           AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success,
           isSelected(wanted) {
            return .selected("accessibility")
        }
        // Not taken through Accessibility: the caret must be where it was
        // (right after the live text) for the arrow keys to select the
        // sentence.
        let caretLocation = span.location + regionLength - (span.after as NSString).length
        if let now = Self.selectedRange(element), now.location != caretLocation || now.length != 0,
           var original, let originalValue = AXValueCreate(.cfRange, &original) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, originalValue)
        }
        guard let caret = Self.selectedRange(element), caret.length == 0, caret.location == caretLocation else {
            return .failed("the control did not take the selection and the cursor is not right after the dictated text")
        }
        await SelectedTextReader.pressKey(keyCode: 124, flags: [], times: span.after.count)
        await SelectedTextReader.pressKey(keyCode: 123, flags: .maskShift, times: region.count)
        for _ in 0..<10 {
            if isSelected(wanted) {
                return .selected("keys")
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        // The keys selected something else: back to the caret after the
        // live text (end of the selection, then left over the last part).
        if let now = Self.selectedRange(element), now.length > 0 {
            await SelectedTextReader.pressKey(keyCode: 124, flags: [], times: 1)
        }
        try? await Task.sleep(for: .milliseconds(60))
        if let now = Self.selectedRange(element), now.length == 0, now.location > caretLocation {
            let back = text.substring(with: NSRange(location: caretLocation, length: min(now.location, text.length) - caretLocation)).count
            await SelectedTextReader.pressKey(keyCode: 123, flags: [], times: back)
            try? await Task.sleep(for: .milliseconds(60))
        }
        return .failed("neither Accessibility nor the arrow keys selected the sentence")
    }

    private func isSelected(_ wanted: CFRange) -> Bool {
        guard let selected = Self.selectedRange(element) else {
            return false
        }
        return selected.location == wanted.location && selected.length == wanted.length
    }

    /// UTF-16 length of the field's text now (to wait for live keystrokes).
    func valueLength() -> Int? {
        Self.string(element, kAXValueAttribute).map { ($0 as NSString).length }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        var range = CFRange()
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cfRange, &range)
        else {
            return nil
        }
        return range
    }
}
