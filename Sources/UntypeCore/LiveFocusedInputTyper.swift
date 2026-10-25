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

    init(targetPID: pid_t, poster: LiveKeyboardPoster = LiveKeyboardPoster()) {
        self.targetPID = targetPID
        self.poster = poster
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
        sync()
    }

    func final(_ text: String) {
        transcript.commitFinal(text)
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
        typed = ""
        transcript = LiveTranscriptText()
        guard !alreadyTyped.isEmpty, targetIsFrontmost else {
            return .notLive
        }
        let edit = LiveInputEdit.between(typed: alreadyTyped, target: delivered)
        if edit.insert.contains(where: { $0.isNewline }) {
            await poster.applyAndWait(LiveInputEdit(deleteCount: edit.deleteCount, insert: ""))
            return .paste(edit.insert)
        }
        await poster.applyAndWait(edit)
        return .completed
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
        let target = transcript.text
        let edit = LiveInputEdit.between(typed: typed, target: target)
        guard !edit.isEmpty else {
            return
        }
        poster.apply(edit)
        typed = target
    }
}
