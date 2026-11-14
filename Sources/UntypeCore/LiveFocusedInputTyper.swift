import AppKit
import Foundation

/// `eventSourceUserData` value carried by every keyboard event untype posts
/// itself while live-typing. The push-to-talk hotkey monitors ignore events
/// with this marker, so a synthetic key-up (whose flags lack the held hotkey
/// modifier) is never mistaken for the push-to-talk release.
public let untypeSyntheticKeyboardEventMarker: Int64 = 0x554E_5459 // "UNTY"

public func isUntypeSyntheticKeyboardEvent(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == untypeSyntheticKeyboardEventMarker
}

/// The keystrokes that turn the text already typed into a field into a new
/// target text: delete the typed characters after the common prefix, then
/// insert the rest of the target.
public struct LiveInputEdit: Equatable, Sendable {
    public let deleteCount: Int
    public let insert: String

    public init(deleteCount: Int, insert: String) {
        self.deleteCount = deleteCount
        self.insert = insert
    }

    public var isEmpty: Bool {
        deleteCount == 0 && insert.isEmpty
    }

    /// Characters (grapheme clusters) are the unit, because one Backspace
    /// removes one character in text controls.
    public static func between(typed: String, target: String) -> LiveInputEdit {
        let typedCharacters = Array(typed)
        let targetCharacters = Array(target)
        var common = 0
        while common < typedCharacters.count,
              common < targetCharacters.count,
              typedCharacters[common] == targetCharacters[common] {
            common += 1
        }
        return LiveInputEdit(
            deleteCount: typedCharacters.count - common,
            insert: String(targetCharacters[common...])
        )
    }
}

/// How the release-time delivery should treat a push-to-talk turn.
public enum LiveInputReconciliation: Equatable, Sendable {
    /// Nothing was typed live: deliver the text the regular way.
    case notLive
    /// The live text was edited into the delivered text with keystrokes.
    case completed
    /// The live text was trimmed to the common prefix; the rest contains a
    /// line break, which must be pasted (a typed newline would press Return).
    case paste(String)
}

/// The transcript of one push-to-talk turn as it should appear in the field:
/// every final utterance so far, then the utterance still being recognized.
/// Provider partials restart after each final, so finals are accumulated here.
public struct LiveTranscriptText: Equatable, Sendable {
    public private(set) var committed = ""
    public private(set) var partial = ""

    public init() {}

    public var text: String {
        Self.join(committed, partial)
    }

    public mutating func updatePartial(_ text: String) {
        partial = Self.clean(text)
    }

    public mutating func commitFinal(_ text: String) {
        committed = Self.join(committed, Self.clean(text))
        partial = ""
    }

    private static func clean(_ text: String) -> String {
        String(text.drop(while: { $0.isWhitespace }))
    }

    private static func join(_ head: String, _ tail: String) -> String {
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }
}

/// Posts live-typing keystrokes in order on a private serial queue, so the
/// main thread never blocks on long Backspace runs.
final class LiveKeyboardPoster: @unchecked Sendable {
    private let queue = DispatchQueue(label: "untype.live-input-typing")
    private static let deleteKeyCode: CGKeyCode = 51
    private static let returnKeyCode: CGKeyCode = 36
    private static let maxUnitsPerEvent = 20

    func apply(_ edit: LiveInputEdit) {
        queue.async {
            Self.post(edit)
        }
    }

    func applyAndWait(_ edit: LiveInputEdit) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                Self.post(edit)
                continuation.resume()
            }
        }
    }

    /// Presses Return once in the app in front (a hands-free turn finished
    /// with Enter: sends the message just typed). Marked like the live
    /// keystrokes, so untype's own key taps let it through.
    static func postReturn() {
        guard let source = CGEventSource(stateID: .privateState) else {
            return
        }
        postKey(source: source, keyCode: returnKeyCode, units: nil)
    }

    private static func post(_ edit: LiveInputEdit) {
        // A private-state source keeps the held push-to-talk modifier out of
        // the posted events' flags.
        guard let source = CGEventSource(stateID: .privateState) else {
            return
        }
        for _ in 0..<edit.deleteCount {
            postKey(source: source, keyCode: deleteKeyCode, units: nil)
        }
        for chunk in unicodeChunks(edit.insert) {
            postKey(source: source, keyCode: 0, units: chunk)
        }
    }

    private static func postKey(source: CGEventSource, keyCode: CGKeyCode, units: [UniChar]?) {
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: untypeSyntheticKeyboardEventMarker)
            if var units {
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            }
            event.post(tap: .cghidEventTap)
        }
    }

    /// Splits text into UTF-16 runs of at most `maxUnitsPerEvent` units
    /// without splitting a character.
    static func unicodeChunks(_ text: String) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty, current.count + units.count > maxUnitsPerEvent {
                chunks.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

/// Types the transcript of one push-to-talk turn straight into the focused
/// control of the target app while the user speaks, then turns that live text
/// into the delivered (refined/translated) text on release.
@MainActor
final class LiveFocusedInputTyper {
    let targetPID: pid_t
    private var transcript = LiveTranscriptText()
    private var typed = ""
    private let poster: LiveKeyboardPoster
    /// While held, the transcript accumulates but nothing is typed (the
    /// selection is being read; typing would replace it).
    private var isHeld = false
    /// A hands-free turn in which the user ends the sentences: the text as
    /// it is written then (nil: the transcript is typed as recognised).
    private var flow: HandsFreeTextFlow?
    private let readContext: (pid_t) -> LiveCaretContext?
    private let now: () -> TimeInterval
    /// What the field answered about its caret, for the event log (no text).
    var onCaretContext: ((String) -> Void)?

    init(
        targetPID: pid_t,
        poster: LiveKeyboardPoster = LiveKeyboardPoster(),
        readContext: @escaping @MainActor (pid_t) -> LiveCaretContext? = { LiveCaretContextReader.read(pid: $0) },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.targetPID = targetPID
        self.poster = poster
        self.readContext = { pid in MainActor.assumeIsolated { readContext(pid) } }
        self.now = now
    }

    /// From now on, in this turn, the user ends the sentences (see
    /// `HandsFreeTextFlow`). What was typed so far is rewritten the same way.
    func leavePunctuationToUser(pausePeriodSeconds: TimeInterval?) {
        guard flow == nil else {
            return
        }
        var flow = HandsFreeTextFlow(pausePeriodSeconds: pausePeriodSeconds)
        // The field as it was before this turn typed into it.
        var context = caretContext()
        if !typed.isEmpty {
            context = context.flatMap { field in
                field.before.hasSuffix(typed)
                    ? LiveCaretContext(before: String(field.before.dropLast(typed.count)), endsLine: field.endsLine)
                    : nil
            }
        }
        let time = now()
        if !transcript.committed.isEmpty {
            flow.commitFinal(transcript.committed, now: time, context: { context })
            flow.updatePartial(transcript.partial, now: time, context: { nil })
        } else {
            flow.updatePartial(transcript.partial, now: time, context: { context })
        }
        self.flow = flow
        sync()
    }

    /// A key or click of the user during the turn (not untype's own keys).
    func userKeystroke(_ keystroke: UserKeystroke) {
        flow?.note(keystroke)
    }

    private func caretContext() -> LiveCaretContext? {
        let context = targetIsFrontmost ? readContext(targetPID) : nil
        if let onCaretContext {
            if let context {
                let last = context.before.last
                let kind = last == nil ? "nothing" : last!.isNewline ? "a line break" : last!.isWhitespace ? "a space"
                    : last!.isLetter || last!.isNumber ? "a letter or digit" : "punctuation"
                let line = context.endsLine.map { $0 ? "line ends after it" : "text follows" } ?? "what follows is not known"
                onCaretContext("before the cursor: \(kind) (\(context.before.count) characters read), \(line)")
            } else {
                onCaretContext("the field does not report its cursor")
            }
        }
        return context
    }

    func hold() {
        isHeld = true
    }

    func resume() {
        isHeld = false
        sync()
    }

    func partial(_ text: String) {
        transcript.updatePartial(text)
        flow?.updatePartial(text, now: now(), context: caretContext)
        sync()
    }

    func final(_ text: String) {
        transcript.commitFinal(text)
        flow?.commitFinal(text, now: now(), context: caretContext)
        sync()
    }

    /// Edits the live text into `delivered` with the same keystrokes that
    /// typed it, so the result never depends on another insertion method (an
    /// Accessibility insert that a terminal applies asynchronously looks like
    /// a no-op and made the paste fallback insert the text a second time).
    /// The turn's live state is cleared, so later speech in the same session
    /// starts a new live run.
    func reconcile(with delivered: String) async -> LiveInputReconciliation {
        let alreadyTyped = typed
        let spoken = transcript.text
        let userPunctuated = flow != nil
        typed = ""
        transcript = LiveTranscriptText()
        flow = nil
        guard !alreadyTyped.isEmpty, targetIsFrontmost else {
            return .notLive
        }
        // The user ended the sentences and nothing processed the text: what
        // is in the field (with the user's own edits) is the result.
        if userPunctuated, Self.sameWords(delivered, spoken) {
            await flush()
            return .completed
        }
        let edit = LiveInputEdit.between(typed: alreadyTyped, target: delivered)
        if edit.insert.contains(where: { $0.isNewline }) {
            await poster.applyAndWait(LiveInputEdit(deleteCount: edit.deleteCount, insert: ""))
            return .paste(edit.insert)
        }
        await poster.applyAndWait(edit)
        return .completed
    }

    /// Returns when every keystroke posted so far has been sent.
    func flush() async {
        await poster.applyAndWait(LiveInputEdit(deleteCount: 0, insert: ""))
    }

    /// Forgets the live text without editing it (it is being replaced
    /// together with the sentence around it).
    func discard() {
        typed = ""
        transcript = LiveTranscriptText()
        flow = nil
    }

    /// The same text, whatever the spacing.
    static func sameWords(_ a: String, _ b: String) -> Bool {
        a.split(whereSeparator: { $0.isWhitespace }) == b.split(whereSeparator: { $0.isWhitespace })
    }

    private var targetIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
    }

    private func sync() {
        // Never type into another app; the text catches up if the target
        // becomes frontmost again.
        guard !isHeld, targetIsFrontmost else {
            return
        }
        let target = flow?.text ?? transcript.text
        let edit = LiveInputEdit.between(typed: typed, target: target)
        guard !edit.isEmpty else {
            return
        }
        poster.apply(edit)
        typed = target
    }
}
