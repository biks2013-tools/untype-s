import Foundation

public enum UntypeUIExportKind: String, Equatable, Sendable {
    case transcript
    case events

    public var displayName: String {
        switch self {
        case .transcript:
            return "transcript"
        case .events:
            return "events"
        }
    }

    fileprivate var filePrefix: String {
        switch self {
        case .transcript:
            return "untype-transcript"
        case .events:
            return "untype-events"
        }
    }
}

public enum UntypeUITranscriptSectionCopyKind: String, Equatable, Sendable {
    case raw
    case processed

    public var displayName: String {
        switch self {
        case .raw:
            return "raw"
        case .processed:
            return "processed output"
        }
    }

    public var eventName: String {
        switch self {
        case .raw:
            return "raw"
        case .processed:
            return "processed"
        }
    }
}

public struct UntypeUITranscriptSectionCopyPayload: Equatable, Sendable {
    public let kind: UntypeUITranscriptSectionCopyKind
    public let text: String

    public init?(
        kind: UntypeUITranscriptSectionCopyKind,
        text: String
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.kind = kind
        self.text = text
    }
}

public struct UntypeUIExportDocument: Equatable, Sendable {
    public let kind: UntypeUIExportKind
    public let text: String
    public let suggestedFileName: String

    public init(kind: UntypeUIExportKind, text: String, generatedAt: Date = Date()) {
        self.kind = kind
        self.text = text
        suggestedFileName = "\(kind.filePrefix)-\(Self.timestamp(generatedAt)).txt"
    }

    public var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func transcript(
        from timeline: UntypeUITimelineState,
        generatedAt: Date = Date()
    ) -> UntypeUIExportDocument? {
        let text = timeline.exportPlainText()
        let document = UntypeUIExportDocument(kind: .transcript, text: text, generatedAt: generatedAt)
        return document.hasContent ? document : nil
    }

    public static func events(
        from events: [String],
        generatedAt: Date = Date()
    ) -> UntypeUIExportDocument? {
        let text = events.joined(separator: "\n")
        let document = UntypeUIExportDocument(kind: .events, text: text, generatedAt: generatedAt)
        return document.hasContent ? document : nil
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

public enum UntypeUIExportActionError: Error, Equatable {
    case emptyContent
}

public struct UntypeUIExportActionRouter {
    private let copyText: (String) throws -> Void
    private let saveDocument: (UntypeUIExportDocument) throws -> Void

    public init(
        copyText: @escaping (String) throws -> Void,
        saveDocument: @escaping (UntypeUIExportDocument) throws -> Void
    ) {
        self.copyText = copyText
        self.saveDocument = saveDocument
    }

    @discardableResult
    public func copy(_ document: UntypeUIExportDocument?) throws -> UntypeUIExportDocument {
        guard let document, document.hasContent else {
            throw UntypeUIExportActionError.emptyContent
        }
        try copyText(document.text)
        return document
    }

    @discardableResult
    public func save(_ document: UntypeUIExportDocument?) throws -> UntypeUIExportDocument {
        guard let document, document.hasContent else {
            throw UntypeUIExportActionError.emptyContent
        }
        try saveDocument(document)
        return document
    }
}
