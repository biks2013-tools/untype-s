#if os(macOS)
import AppKit
import ApplicationServices
import Foundation

/// What the field holds of a turn's dictated text when the turn ends
/// (plan-071). The user may have moved the caret and typed during the turn,
/// so the text in the field is not always what was spoken, in that order.
public enum TurnFieldReading: Equatable, Sendable {
    /// What untype typed, with the caret right after it.
    case asTyped
    /// The user changed it or moved the caret: the turn's text as it stands
    /// in the field now.
    case edited(String)
    /// It changed in a way untype cannot follow; why (never text).
    case notFollowed(String)
}

/// Where a turn's text stands in the field. Pure.
public enum TurnFieldRegion {
    /// The range (UTF-16) of the turn's text in `value`, the field's text
    /// now: what stands between the text that was before the caret and the
    /// text that was after it when the turn started. nil when either of
    /// them is no longer there unchanged.
    public static func inField(_ value: String, before: String, after: String) -> NSRange? {
        let text = value as NSString
        let headLength = (before as NSString).length
        let tailLength = (after as NSString).length
        guard text.length >= headLength + tailLength,
              text.substring(to: headLength) == before,
              text.substring(from: text.length - tailLength) == after
        else {
            return nil
        }
        return NSRange(location: headLength, length: text.length - headLength - tailLength)
    }

    /// The turn's text in a terminal prompt box, where the caret is not
    /// reported: what follows the prompt as it was when the turn started
    /// (`kept`). When the prompt no longer starts with it (it was a
    /// suggestion shown in an empty prompt, or the user changed it), the
    /// whole prompt is the turn's text.
    public static func inPrompt(_ now: String, atPress: String) -> (kept: String, text: String) {
        if !atPress.isEmpty, now.hasPrefix(atPress) {
            return (atPress, String(now.dropFirst(atPress.count)))
        }
        return ("", now)
    }
}

/// For fields that cannot be read: the turn's text as it follows from
/// untype's own keystrokes and the keys the user pressed, as long as the
/// caret stayed at the end.
public struct TypedTailModel: Equatable, Sendable {
    /// The turn's text in the field; nil once it cannot be told (the caret
    /// was moved, a shortcut was used).
    public private(set) var text: String? = ""
    /// The user pressed a key or clicked during the turn.
    public private(set) var touched = false

    public init(text: String = "") {
        self.text = text
    }

    /// untype typed: Backspaces, then characters.
    public mutating func typed(_ edit: LiveInputEdit) {
        guard var current = text else {
            return
        }
        current.removeLast(min(edit.deleteCount, current.count))
        text = current + edit.insert
    }

    public mutating func note(_ keystroke: UserKeystroke) {
        touched = true
        guard var current = text else {
            return
        }
        switch keystroke {
        case .text(let typed):
            text = current + typed
        case .erase:
            if current.isEmpty {
                // Erased text that was there before the turn.
                text = nil
            } else {
                current.removeLast()
                text = current
            }
        case .eraseWord:
            let kept = current.reversed().drop(while: \.isWhitespace)
            if kept.isEmpty {
                // The word erased was there before the turn.
                text = nil
            } else {
                text = UserTypingTrail.erasingWord(current)
            }
        case .move:
            text = nil
        }
    }
}

/// How the turn's text in the field was replaced with the processed text.
enum TurnFieldReplacement: Equatable {
    /// The turn's text is selected (how): inserting the text replaces it.
    case selected(String)
    /// The turn's text was erased and the processed text typed.
    case typed
    /// The turn's text was erased; this text (it has a line break) is to be
    /// pasted.
    case paste(String)
    /// Nothing usable was done; why (never text).
    case failed(String)
}

/// The place a turn's text goes to, captured when the turn starts, so the
/// text can be read back when the turn ends and replaced with the processed
/// text: a control that reports its text and caret through Accessibility,
/// or the prompt box of a terminal coding agent (read from the screen).
@MainActor
final class TurnFieldAnchor {
    private enum Kind {
        case field(element: AXUIElement, before: String, after: String)
        case prompt(TerminalPromptAnchor, atPress: String)
    }

    private let kind: Kind
    /// The prompt as last read and the part of it that is not the turn's.
    private var lastPrompt: (now: String, kept: String)?

    private init(kind: Kind) {
        self.kind = kind
    }

    /// For the event log.
    var name: String {
        switch kind {
        case .field: return "text field"
        case .prompt: return "terminal prompt"
        }
    }

    /// nil when the focused control of `app` offers neither: no focused
    /// control, a password field, a control without text or caret, text
    /// selected, or a terminal that shows no prompt box.
    static func capture(in app: NSRunningApplication) -> TurnFieldAnchor? {
        guard let element = CaretLocator.focusedElement() else {
            return nil
        }
        AXUIElementSetMessagingTimeout(element, 0.25)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else {
            return nil
        }
        if let bundleIdentifier = app.bundleIdentifier,
           SentenceAnchor.terminalBundleIdentifiers.contains(bundleIdentifier) {
            guard string(element, kAXRoleAttribute) == (kAXTextAreaRole as String),
                  let screen = string(element, kAXValueAttribute),
                  let box = TerminalPromptParser.box(in: screen)
            else {
                return nil
            }
            return TurnFieldAnchor(kind: .prompt(TerminalPromptAnchor(element: element, text: box), atPress: box))
        }
        guard string(element, kAXSubroleAttribute) != (kAXSecureTextFieldSubrole as String),
              let value = string(element, kAXValueAttribute),
              let range = selectedRange(element), range.length == 0,
              range.location >= 0, range.location <= (value as NSString).length
        else {
            return nil
        }
        let text = value as NSString
        return TurnFieldAnchor(kind: .field(
            element: element,
            before: text.substring(to: range.location),
            after: text.substring(from: range.location)
        ))
    }

    /// The turn's text in the field now, against `typed` (what untype
    /// typed). `userTouched`: the user pressed a key or clicked during the
    /// turn (a terminal does not report its caret, so only that tells that
    /// the caret may have moved).
    func read(typed: String, userTouched: Bool) -> TurnFieldReading {
        switch kind {
        case .field(let element, let before, let after):
            guard let focused = CaretLocator.focusedElement(), CFEqual(focused, element) else {
                return .notFollowed("another control has the focus")
            }
            guard let value = Self.string(element, kAXValueAttribute) else {
                return .notFollowed("the control's text cannot be read")
            }
            guard let range = TurnFieldRegion.inField(value, before: before, after: after) else {
                return .notFollowed("the text around the dictation changed")
            }
            let region = (value as NSString).substring(with: range)
            if region == typed {
                if let caret = Self.selectedRange(element),
                   caret.length != 0 || caret.location != range.location + range.length {
                    return .edited(region)
                }
                return .asTyped
            }
            guard !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .notFollowed("nothing of the dictation is left in the field")
            }
            return .edited(region)
        case .prompt(let anchor, let atPress):
            guard let now = anchor.currentBox() else {
                return .notFollowed("the prompt box is not on screen")
            }
            let (kept, text) = TurnFieldRegion.inPrompt(now, atPress: atPress)
            lastPrompt = (now, kept)
            if !userTouched, LiveFocusedInputTyper.sameWords(text, typed) {
                return .asTyped
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .notFollowed("nothing of the dictation is left in the prompt")
            }
            return .edited(trimmed)
        }
    }

    /// Replaces the turn's text in the field with `text`, or prepares it
    /// (see `TurnFieldReplacement`).
    func replace(with text: String) async -> TurnFieldReplacement {
        switch kind {
        case .field(let element, let before, let after):
            return await select(element: element, before: before, after: after)
        case .prompt(let anchor, _):
            return await rewrite(anchor, with: text)
        }
    }

    // MARK: A control that reports its text

    private func select(element: AXUIElement, before: String, after: String) async -> TurnFieldReplacement {
        guard let focused = CaretLocator.focusedElement(), CFEqual(focused, element) else {
            return .failed("another control has the focus at delivery")
        }
        guard let value = Self.string(element, kAXValueAttribute),
              let region = TurnFieldRegion.inField(value, before: before, after: after)
        else {
            return .failed("the text around the dictation changed before delivery")
        }
        let wanted = CFRange(location: region.location, length: region.length)
        var range = wanted
        if let rangeValue = AXValueCreate(.cfRange, &range),
           AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success,
           Self.isSelected(element, wanted) {
            return .selected("accessibility")
        }
        // The control does not take an Accessibility selection (web views):
        // arrow keys from wherever the caret stands inside the turn's text.
        let text = value as NSString
        let end = region.location + region.length
        guard let caret = Self.selectedRange(element), caret.length == 0,
              caret.location >= region.location, caret.location <= end
        else {
            return .failed("the control did not take the selection and the cursor is not inside the dictated text")
        }
        let toEnd = text.substring(with: NSRange(location: caret.location, length: end - caret.location)).count
        await SelectedTextReader.pressKey(keyCode: 124, flags: [], times: toEnd)
        await SelectedTextReader.pressKey(keyCode: 123, flags: .maskShift, times: text.substring(with: region).count)
        for _ in 0..<10 {
            if Self.isSelected(element, wanted) {
                return .selected("keys")
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        if let now = Self.selectedRange(element), now.length > 0 {
            // Something else got selected: collapse it, so nothing is replaced.
            await SelectedTextReader.pressKey(keyCode: 124, flags: [], times: 1)
        }
        return .failed("neither Accessibility nor the arrow keys selected the dictated text")
    }

    private static func isSelected(_ element: AXUIElement, _ wanted: CFRange) -> Bool {
        guard let selected = selectedRange(element) else {
            return false
        }
        return selected.location == wanted.location && selected.length == wanted.length
    }

    // MARK: A terminal prompt box

    /// Extra key presses that make up for characters the screen text does
    /// not show exactly (a wrapped line). Harmless at either end of the prompt.
    private static let keyMargin = 8

    /// The caret is taken to the end of the prompt with Right, the turn's
    /// text is erased with Backspace, and `text` is typed.
    private func rewrite(_ anchor: TerminalPromptAnchor, with text: String) async -> TurnFieldReplacement {
        guard let (now, kept) = lastPrompt else {
            return .failed("the prompt was not read")
        }
        let turn = String(now.dropFirst(kept.count))
        let lead = String(turn.prefix(while: { $0.isWhitespace }))
        await SelectedTextReader.pressKey(keyCode: 124, flags: [], times: now.count + Self.keyMargin)
        if kept.isEmpty {
            await SelectedTextReader.pressBackspace(times: now.count + Self.keyMargin)
            try? await Task.sleep(for: .milliseconds(150))
        } else {
            // What stood in the prompt before the turn stays: erase exactly
            // the turn's text, then check the screen and correct.
            await SelectedTextReader.pressBackspace(times: turn.count)
            var restored = false
            for _ in 0..<3 {
                guard let current = await settledBox(anchor) else {
                    return .failed("the prompt box is not on screen at delivery")
                }
                if current == kept {
                    restored = true
                    break
                }
                if current.hasPrefix(kept) {
                    await SelectedTextReader.pressBackspace(times: current.count - kept.count)
                } else if kept.hasPrefix(current) {
                    await LiveKeyboardPoster().applyAndWait(
                        LiveInputEdit(deleteCount: 0, insert: String(kept.dropFirst(current.count)))
                    )
                } else {
                    return .failed("the prompt changed while the dictated text was being replaced")
                }
            }
            guard restored else {
                return .failed("the dictated text could not be erased from the prompt")
            }
        }
        let insert = (kept.isEmpty ? "" : lead) + text
        if insert.contains(where: { $0.isNewline }) {
            return .paste(insert)
        }
        await LiveKeyboardPoster().applyAndWait(LiveInputEdit(deleteCount: 0, insert: insert))
        return .typed
    }

    /// The prompt box once the screen stopped changing (at most 1.2 s).
    private func settledBox(_ anchor: TerminalPromptAnchor) async -> String? {
        try? await Task.sleep(for: .milliseconds(80))
        var last = anchor.currentBox()
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(80))
            let next = anchor.currentBox()
            if next == last {
                return next
            }
            last = next
        }
        return last
    }

    // MARK: Accessibility

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
#endif
