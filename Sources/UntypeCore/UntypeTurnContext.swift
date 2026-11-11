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

/// A screenshot of the active app's window (the Screenshot operator).
public struct WindowScreenshot: Sendable, Equatable {
    public let image: LLMImageAttachment
    /// The app the window belongs to, named in the prompt.
    public let appName: String

    public init(image: LLMImageAttachment, appName: String) {
        self.image = image
        self.appName = appName
    }
}

/// Per-turn inputs that come from outside the transcript: the text selected
/// in the active app at press time and the screenshot of its window. Owned
/// by the UI model (runtimes are recreated every turn) and read by the
/// protocol controller.
public final class UntypeTurnContext: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSelection: String?
    private var storedRole: SelectionRole = .material
    private var storedScreenshot: WindowScreenshot?
    private var pendingScreenshot: Task<WindowScreenshot?, Never>?
    private var storedSentence: SentenceSpan?
    private var storedSentenceDictation: String?

    public init(
        selectedText: String? = nil,
        selectionRole: SelectionRole = .material,
        screenshot: WindowScreenshot? = nil
    ) {
        storedSelection = selectedText
        storedRole = selectionRole
        storedScreenshot = screenshot
    }

    /// The screenshot, waiting for a capture still in progress.
    public func screenshot() async -> WindowScreenshot? {
        let (stored, pending) = lock.withLock { (storedScreenshot, pendingScreenshot) }
        if let stored {
            return stored
        }
        return await pending?.value
    }

    /// Whether a screenshot was captured or is being captured.
    public var hasScreenshot: Bool {
        lock.withLock { storedScreenshot != nil || pendingScreenshot != nil }
    }

    /// A capture in progress; its result becomes the screenshot.
    public func setScreenshotCapture(_ capture: Task<WindowScreenshot?, Never>) {
        lock.withLock {
            storedScreenshot = nil
            pendingScreenshot = capture
        }
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
            storedScreenshot = nil
            pendingScreenshot = nil
            storedSentence = nil
            storedSentenceDictation = nil
        }
    }

    /// The sentence around the caret at press time (nil: none).
    public func setSentence(_ span: SentenceSpan?) {
        lock.withLock {
            storedSentence = span
            storedSentenceDictation = nil
        }
    }

    /// The sentence around the caret, handed out once: the section that
    /// takes it processes the whole sentence with `dictation` at the caret,
    /// and its output replaces the sentence in the field.
    public func takeSentence(dictation: String) -> SentenceSpan? {
        lock.withLock {
            guard let span = storedSentence else {
                return nil
            }
            storedSentence = nil
            storedSentenceDictation = dictation
            return span
        }
    }

    /// The dictation of the section that took the sentence, handed out once
    /// to the delivery of that section's output. nil: the text being
    /// delivered is not a whole sentence.
    public func takeSentenceDelivery() -> String? {
        lock.withLock {
            defer { storedSentenceDictation = nil }
            return storedSentenceDictation
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
