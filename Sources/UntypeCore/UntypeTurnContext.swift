import Foundation

/// How the Selection operator uses the selected text.
public enum SelectionRole: String, CaseIterable, Sendable, Equatable {
    /// The selection is what refine/translate process (the dictation, if any,
    /// follows it); the result replaces the selection.
    case material
    /// The selection is reference only; the dictation is processed and the
    /// result is inserted after the selection.
    case context
}

/// Per-turn inputs that come from outside the transcript: the text selected
/// in the active app at press time. Owned by the UI model (runtimes are
/// recreated every turn) and read by the protocol controller.
public final class UntypeTurnContext: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSelection: String?
    private var storedRole: SelectionRole = .material

    public init(selectedText: String? = nil, selectionRole: SelectionRole = .material) {
        storedSelection = selectedText
        storedRole = selectionRole
    }

    public var selectedText: String? {
        lock.withLock { storedSelection }
    }

    public var selectionRole: SelectionRole {
        lock.withLock { storedRole }
    }

    public func begin(selectionRole: SelectionRole) {
        lock.withLock {
            storedSelection = nil
            storedRole = selectionRole
        }
    }

    public func setSelection(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            storedSelection = (trimmed?.isEmpty ?? true) ? nil : text
        }
    }
}

public struct AskExchange: Equatable, Sendable {
    public let request: String
    public let answer: String

    public init(request: String, answer: String) {
        self.request = request
        self.answer = answer
    }
}

/// The Ask conversation the Follow-up operator sends along. Owned by the UI
/// model so it outlives the per-turn runtimes; kept in memory only.
public final class AskConversation: @unchecked Sendable {
    public static let maxExchanges = 20
    private let lock = NSLock()
    private var stored: [AskExchange] = []

    public init() {}

    public var exchanges: [AskExchange] {
        lock.withLock { stored }
    }

    public func append(_ exchange: AskExchange) {
        lock.withLock {
            stored.append(exchange)
            if stored.count > Self.maxExchanges {
                stored.removeFirst(stored.count - Self.maxExchanges)
            }
        }
    }

    public func clear() {
        lock.withLock { stored.removeAll() }
    }

    /// `User:` / `Assistant:` lines, oldest first.
    public func rendered() -> String {
        exchanges
            .map { "User: \($0.request)\nAssistant: \($0.answer)" }
            .joined(separator: "\n\n")
    }
}
