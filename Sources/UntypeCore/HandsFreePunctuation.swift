import AppKit
import ApplicationServices
import Foundation

/// Settings → Push-to-Talk → Hands-free: how the text of a hands-free turn
/// (a tap of the hotkey) is written.
public struct HandsFreePreferences: Codable, Equatable, Sendable {
    /// The user ends the sentences: untype writes no full stop at a pause,
    /// and starts with a capital only after a full stop (nil: the default, off).
    public var userPunctuates: Bool?
    /// With `userPunctuates`: a pause of `pausePeriodSeconds` or more still
    /// gets a full stop (nil: the default, off).
    public var periodAfterPause: Bool?

    /// The pause, measured between the end of one recognised utterance and
    /// the first words of the next. The provider needs about half a second
    /// to end an utterance, so this is 3.5 to 4 seconds of silence.
    public static let pausePeriodSeconds: TimeInterval = 3

    public init(userPunctuates: Bool? = nil, periodAfterPause: Bool? = nil) {
        self.userPunctuates = userPunctuates
        self.periodAfterPause = periodAfterPause
    }

    public var leavesPunctuationToUser: Bool {
        userPunctuates ?? false
    }

    public var addsPeriodAfterPause: Bool {
        leavesPunctuationToUser && (periodAfterPause ?? false)
    }
}

/// The text around the caret of the field being dictated into.
public struct LiveCaretContext: Equatable, Sendable {
    /// The text before the caret (only its end matters).
    public var before: String
    /// Nothing follows the caret on its line (nil: not known).
    public var endsLine: Bool?

    public init(before: String, endsLine: Bool? = nil) {
        self.before = before
        self.endsLine = endsLine
    }
}

/// Writes one recognised utterance the way it should enter the text at the
/// caret when the user ends the sentences themselves.
public enum LiveUtteranceShaper {
    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let openers: Set<Character> = ["(", "[", "{", "«", "“", "‘", "\"", "'"]

    /// - Parameters:
    ///   - context: the text before the caret; nil when the field does not
    ///     tell (then only the provider's closing full stop is dropped).
    ///   - periodFirst: a long pause came before this utterance: it closes
    ///     the sentence before it with a full stop.
    public static func shape(_ utterance: String, context: LiveCaretContext?, periodFirst: Bool = false) -> String {
        let body = withoutClosingPeriod(utterance)
        guard !body.isEmpty, let context else {
            return body
        }
        if periodFirst {
            return ". " + capitalized(body)
        }
        let before = context.before
        let lastWritten = before.last { !$0.isWhitespace }
        let startsSentence = lastWritten.map { isTerminator($0, before: body) } ?? true
        let text = startsSentence ? capitalized(body) : lowercased(body)
        let needsSpace = before.last.map { !$0.isWhitespace && !openers.contains($0) } ?? false
        return (needsSpace ? " " : "") + text
    }

    /// The utterance without the full stop the provider closes it with (an
    /// ellipsis, a question mark and an exclamation mark stay).
    public static func withoutClosingPeriod(_ utterance: String) -> String {
        var text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("."), !text.hasSuffix("..") {
            text.removeLast()
        }
        return text
    }

    /// The Greek question mark looks like a semicolon: it ends a sentence
    /// only before Greek text.
    private static func isTerminator(_ character: Character, before body: String) -> Bool {
        if terminators.contains(character) {
            return true
        }
        guard character == ";" || character == "\u{037E}", let first = body.first(where: { $0.isLetter }) else {
            return false
        }
        return first.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value) }
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else {
            return text
        }
        return first.uppercased() + text.dropFirst()
    }

    /// The provider starts every utterance with a capital. Inside a sentence
    /// that capital goes, unless the word carries its own: "I", or a word
    /// with more capitals (an acronym). A name at the start of an utterance
    /// cannot be told apart and is written in lower case.
    private static func lowercased(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else {
            return text
        }
        let word = text.prefix { !$0.isWhitespace }
        if word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’") {
            return text
        }
        if word.dropFirst().contains(where: { $0.isUppercase }) {
            return text
        }
        return first.lowercased() + text.dropFirst()
    }
}

/// What the user did on the keyboard or with the mouse during a hands-free
/// turn, as far as it changes what stands before the caret.
public enum UserKeystroke: Equatable, Sendable {
    /// Characters were typed.
    case text(String)
    /// Backspace.
    case erase
    /// The caret may be elsewhere now: an arrow key, a click, a shortcut.
    case move
}

/// What the user typed after untype's last words, for fields that do not
/// report their text: a full stop typed by hand is known from its key.
public struct UserTypingTrail: Equatable, Sendable {
    /// Typed by the user since untype last wrote.
    public private(set) var typed = ""
    /// Characters of untype's own text the user erased.
    public private(set) var erased = 0
    /// The caret may have left the end of untype's text.
    public private(set) var moved = false

    public init() {}

    public mutating func note(_ keystroke: UserKeystroke) {
        switch keystroke {
        case .text(let text):
            typed += text
        case .erase:
            if typed.isEmpty {
                erased += 1
            } else {
                typed.removeLast()
            }
        case .move:
            moved = true
        }
    }

    /// The end of the text before the caret, given what untype wrote last;
    /// nil when the caret was moved (then it is not known).
    public func before(written: String) -> String? {
        moved ? nil : String(written.dropLast(erased)) + typed
    }
}

/// The text of a hands-free turn when the user ends the sentences: every
/// utterance is written once it starts, for the place the caret is at then.
/// So the user can type a full stop, or move the caret, between utterances
/// and the next words follow from what is there.
public struct HandsFreeTextFlow: Equatable, Sendable {
    /// What untype has written for the finished utterances.
    public private(set) var committed = ""
    private var partial = ""
    private var current: Utterance?
    private var lastFinalAt: TimeInterval?
    private let pausePeriodSeconds: TimeInterval?
    private var trail = UserTypingTrail()

    private struct Utterance: Equatable, Sendable {
        var context: LiveCaretContext?
        var periodFirst: Bool
    }

    /// - Parameter pausePeriodSeconds: nil: a pause never writes a full stop.
    public init(pausePeriodSeconds: TimeInterval? = nil) {
        self.pausePeriodSeconds = pausePeriodSeconds
    }

    /// A key or click of the user, between or during utterances.
    public mutating func note(_ keystroke: UserKeystroke) {
        trail.note(keystroke)
    }

    /// Everything to be in the field: the finished utterances and the one
    /// being recognised.
    public var text: String {
        committed + partial
    }

    /// - Parameter context: reads the text around the caret; called once,
    ///   when an utterance starts, before any of it is typed.
    public mutating func updatePartial(_ text: String, now: TimeInterval, context: () -> LiveCaretContext?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            partial = ""
            return
        }
        let utterance = begin(now: now, context: context)
        partial = LiveUtteranceShaper.shape(text, context: utterance.context, periodFirst: utterance.periodFirst)
    }

    public mutating func commitFinal(_ text: String, now: TimeInterval, context: () -> LiveCaretContext?) {
        partial = ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            current = nil
            return
        }
        let utterance = begin(now: now, context: context)
        committed += LiveUtteranceShaper.shape(text, context: utterance.context, periodFirst: utterance.periodFirst)
        current = nil
        lastFinalAt = now
    }

    private mutating func begin(now: TimeInterval, context read: () -> LiveCaretContext?) -> Utterance {
        if let current {
            return current
        }
        var field = read()
        // "Nothing before the caret" after untype wrote into the field: the
        // control does not report its caret (it answers as an empty field
        // would). It is not believed.
        if let answer = field, answer.before.isEmpty, !committed.isEmpty || !trail.typed.isEmpty {
            field = nil
        }
        // A field that does not tell: before the caret stands what untype
        // wrote last and what the user typed after it (their full stop is
        // known from its key). After a click or an arrow key only untype's
        // own text is left to go by.
        let known = trail.before(written: committed) ?? committed
        let context = field ?? (known.isEmpty ? nil : LiveCaretContext(before: known))
        trail = UserTypingTrail()
        let utterance = Utterance(context: context, periodFirst: closesSentence(now: now, field: field))
        current = utterance
        return utterance
    }

    /// A long pause closes the sentence, but only where that is certainly
    /// meant: the caret still stands right after what untype wrote last, at
    /// the end of its line, and that text ends in a letter or a digit.
    private func closesSentence(now: TimeInterval, field: LiveCaretContext?) -> Bool {
        guard let pausePeriodSeconds, let lastFinalAt, now - lastFinalAt >= pausePeriodSeconds,
              let field, field.endsLine == true, !committed.isEmpty,
              let last = field.before.last, last.isLetter || last.isNumber
        else {
            return false
        }
        return field.before.hasSuffix(String(committed.suffix(12)))
    }
}

/// Reads the text around the caret of the focused control through
/// Accessibility. No side effects.
@MainActor
enum LiveCaretContextReader {
    private static let charactersBefore = 80

    /// nil when `pid` has no focused text control that reports its text and
    /// caret (terminals, some web views), or it is a password field.
    static func read(pid: pid_t) -> LiveCaretContext? {
        // A terminal's text area holds the screen, not the text being typed.
        if let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           SentenceAnchor.terminalBundleIdentifiers.contains(bundle) {
            return nil
        }
        guard let element = CaretLocator.focusedElement() else {
            return nil
        }
        AXUIElementSetMessagingTimeout(element, 0.25)
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else {
            return nil
        }
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
           (subrole as? String) == (kAXSecureTextFieldSubrole as String) {
            return nil
        }
        var rangeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRaw) == .success,
              let rangeRaw, CFGetTypeID(rangeRaw) == AXValueGetTypeID()
        else {
            return nil
        }
        var selection = CFRange()
        guard AXValueGetValue(rangeRaw as! AXValue, .cfRange, &selection), selection.location >= 0 else {
            return nil
        }
        // Text replaces a selection: what counts is what is before it.
        let start = max(0, selection.location - charactersBefore)
        let after = selection.location + selection.length
        if let before = string(element, location: start, length: selection.location - start) {
            let next = string(element, location: after, length: 1)
            return LiveCaretContext(before: before, endsLine: next.map { $0.isEmpty || $0.first?.isNewline == true })
        }
        var valueRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRaw) == .success,
              let value = valueRaw as? String
        else {
            return nil
        }
        let text = value as NSString
        guard after <= text.length else {
            return nil
        }
        let before = text.substring(with: NSRange(location: start, length: selection.location - start))
        let endsLine = after == text.length || text.substring(with: NSRange(location: after, length: 1)).first?.isNewline == true
        return LiveCaretContext(before: before, endsLine: endsLine)
    }

    /// The characters of a range; nil when the control does not offer them.
    /// A range that reaches past the end gives nil for some controls: the
    /// one character after the caret is then not known.
    private static func string(_ element: AXUIElement, location: Int, length: Int) -> String? {
        if length == 0 {
            return ""
        }
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else {
            return nil
        }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, value, &result
        ) == .success else {
            return nil
        }
        return result as? String
    }
}
