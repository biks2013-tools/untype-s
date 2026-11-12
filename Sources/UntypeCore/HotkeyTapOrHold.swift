import Foundation

/// One hotkey for both ways of dictating. A press held and released records
/// for as long as it is held (push-to-talk). A quick tap keeps recording
/// hands-free until the turn is finished with one of `HotkeyTurnFinish`.
public enum HotkeyTapOrHold {
    /// A press released sooner than this is a tap. Nobody says anything
    /// useful in less, so a short hold is never mistaken for a dictation.
    public static let tapThreshold: TimeInterval = 0.4

    public static func isTap(heldFor duration: TimeInterval) -> Bool {
        duration >= 0 && duration < tapThreshold
    }
}

/// How a hands-free turn (started with a tap) ends.
public enum HotkeyTurnFinish: String, Equatable, Sendable {
    /// Enter: the text is typed into the field, then Return is pressed there,
    /// so a chat message or a Claude Code prompt is sent.
    case typeAndSend = "type-and-send"
    /// The hotkey again: the text is typed into the field only.
    case typeOnly = "type-only"
    /// Esc: nothing is delivered and the text typed live is removed.
    case discard
}
