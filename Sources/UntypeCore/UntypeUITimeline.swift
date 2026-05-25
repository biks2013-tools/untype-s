import Foundation

public enum UntypeUITimelineBubbleKind: String, Codable, Sendable {
    case raw
    case processed
    case error
}

public struct UntypeUITimelineBubble: Identifiable, Equatable, Sendable {
    public let id: Int
    public var kind: UntypeUITimelineBubbleKind
    public var label: String
    public var status: String
    public var text: String
}

public struct UntypeUITimelineTurn: Identifiable, Equatable, Sendable {
    public let id: Int
    public var time: String
    public var sealed: Bool
    public var bubbles: [UntypeUITimelineBubble]
}

public struct UntypeUILivePartial: Identifiable, Equatable, Sendable {
    public let id: Int
    public var time: String
    public var label: String
    public var status: String
    public var text: String
}

public enum UntypeUIConversationHistoryRecordKind: String, Sendable {
    case output
    case issue
}

public struct UntypeUIConversationHistoryRecord: Identifiable, Equatable, Sendable {
    public let id: Int
    public var kind: UntypeUIConversationHistoryRecordKind
    public var label: String
    public var status: String
    public var text: String
}

public struct UntypeUIConversationHistoryTurn: Identifiable, Equatable, Sendable {
    public let id: Int
    public var title: String
    public var time: String
    public var status: String
    public var userText: String?
    public var records: [UntypeUIConversationHistoryRecord]
}

public struct UntypeUITimelineState: Equatable, Sendable {
    public private(set) var turns: [UntypeUITimelineTurn]
    public private(set) var partial: UntypeUILivePartial?
    public private(set) var clearedSinceRaw: Bool
    private var nextID: Int

    public init(
        turns: [UntypeUITimelineTurn] = [],
        partial: UntypeUILivePartial? = nil,
        clearedSinceRaw: Bool = false,
        nextID: Int = 1
    ) {
        self.turns = turns
        self.partial = partial
        self.clearedSinceRaw = clearedSinceRaw
        self.nextID = nextID
    }

    public var visibleItemCount: Int {
        turns.reduce(0) { $0 + $1.bubbles.count } + (partial == nil ? 0 : 1)
    }

    public var conversationHistory: [UntypeUIConversationHistoryTurn] {
        var history: [UntypeUIConversationHistoryTurn] = []
        for (index, turn) in turns.enumerated() {
            let rawText = joinedText(
                turn.bubbles.filter { $0.kind == .raw }.map(\.text)
            )
            let records = turn.bubbles
                .filter { $0.kind == .processed || $0.kind == .error }
                .map { bubble in
                    UntypeUIConversationHistoryRecord(
                        id: bubble.id,
                        kind: bubble.kind == .error ? .issue : .output,
                        label: conversationRecordLabel(for: bubble),
                        status: bubble.status,
                        text: bubble.text
                    )
                }
            if rawText == nil && records.isEmpty {
                continue
            }
            history.append(UntypeUIConversationHistoryTurn(
                id: turn.id,
                title: "Conversation \(index + 1)",
                time: turn.time,
                status: turn.sealed ? "closed" : "open",
                userText: rawText,
                records: records
            ))
        }
        if let partial, !partial.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            history.append(UntypeUIConversationHistoryTurn(
                id: partial.id,
                title: "Live conversation",
                time: partial.time,
                status: partial.status,
                userText: partial.text,
                records: []
            ))
        }
        return history
    }

    public var conversationHistoryItemCount: Int {
        conversationHistory.reduce(0) { count, turn in
            count + (turn.userText == nil ? 0 : 1) + turn.records.count
        }
    }

    public func exportPlainText() -> String {
        var sections: [String] = []
        for (index, turn) in turns.enumerated() {
            let exportedBubbles = turn.bubbles.compactMap { bubble -> String? in
                let text = bubble.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    return nil
                }
                return "[\(bubble.label) | \(bubble.status)]\n\(text)"
            }
            guard !exportedBubbles.isEmpty else {
                continue
            }
            let turnState = turn.sealed ? "closed" : "open"
            let heading = "Turn \(index + 1) | \(turn.time) | \(turnState)"
            sections.append(([heading] + exportedBubbles).joined(separator: "\n"))
        }
        if let partial {
            let text = partial.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                sections.append([
                    "Live partial | \(partial.time)",
                    "[\(partial.label) | \(partial.status)]",
                    text
                ].joined(separator: "\n"))
            }
        }
        return sections.joined(separator: "\n\n")
    }

    public mutating func updatePartial(_ text: String, status: String = "streaming") {
        if partial != nil {
            partial?.text = text
            partial?.status = status
            partial?.time = "Live"
            return
        }
        partial = UntypeUILivePartial(
            id: allocateID(),
            time: "Live",
            label: "Partial transcript",
            status: status,
            text: text
        )
    }

    public mutating func commitFinal(_ text: String, status: String = "committed", time: String? = nil) {
        partial = nil
        appendRawTranscript(text, status: status, time: time ?? Self.shortTime())
    }

    public mutating func commitProcessed(_ text: String, status: String = "processed", time: String? = nil) {
        partial = nil
        guard !(clearedSinceRaw && turns.isEmpty) else {
            return
        }
        let turnIndex = latestTurn(time: time ?? Self.shortTime())
        let id = allocateID()
        turns[turnIndex].bubbles.append(UntypeUITimelineBubble(
            id: id,
            kind: .processed,
            label: "Processed output",
            status: status,
            text: text
        ))
    }

    public mutating func commitError(_ text: String, status: String = "error", time: String? = nil) {
        partial = nil
        let turnIndex = latestTurn(time: time ?? Self.shortTime())
        turns[turnIndex].sealed = true
        let id = allocateID()
        turns[turnIndex].bubbles.append(UntypeUITimelineBubble(
            id: id,
            kind: .error,
            label: "Session issue",
            status: status,
            text: text
        ))
    }

    public mutating func sealCurrentTurn() {
        partial = nil
        guard !turns.isEmpty else {
            return
        }
        turns[turns.count - 1].sealed = true
    }

    public mutating func clearPartial() {
        partial = nil
    }

    public mutating func clear() {
        turns = []
        partial = nil
        clearedSinceRaw = true
    }

    private mutating func appendRawTranscript(_ text: String, status: String, time: String) {
        let turnIndex = openTurn(time: time)
        clearedSinceRaw = false
        if let rawIndex = turns[turnIndex].bubbles.firstIndex(where: { $0.kind == .raw }) {
            turns[turnIndex].bubbles[rawIndex].text = appendTranscriptText(
                turns[turnIndex].bubbles[rawIndex].text,
                text
            )
            turns[turnIndex].bubbles[rawIndex].status = status
            return
        }
        turns[turnIndex].bubbles.append(UntypeUITimelineBubble(
            id: allocateID(),
            kind: .raw,
            label: "Dictated text",
            status: status,
            text: text
        ))
    }

    private mutating func openTurn(time: String) -> Int {
        if let last = turns.indices.last, !turns[last].sealed {
            return last
        }
        return createTurn(sealed: false, time: time)
    }

    private mutating func latestTurn(time: String) -> Int {
        if let last = turns.indices.last {
            return last
        }
        return createTurn(sealed: true, time: time)
    }

    private mutating func createTurn(sealed: Bool, time: String) -> Int {
        let id = allocateID()
        turns.append(UntypeUITimelineTurn(
            id: id,
            time: time,
            sealed: sealed,
            bubbles: []
        ))
        return turns.count - 1
    }

    private mutating func allocateID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func appendTranscriptText(_ current: String, _ next: String) -> String {
        let normalizedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNext = next.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedCurrent.isEmpty {
            return normalizedNext
        }
        if normalizedNext.isEmpty || normalizedCurrent.hasSuffix(normalizedNext) {
            return normalizedCurrent
        }
        return "\(normalizedCurrent) \(normalizedNext)"
    }

    private func joinedText(_ values: [String]) -> String? {
        let text = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    private func conversationRecordLabel(for bubble: UntypeUITimelineBubble) -> String {
        switch bubble.kind {
        case .processed:
            return "Refine / Translate record"
        case .error:
            return "Session record"
        case .raw:
            return bubble.label
        }
    }

    private static func shortTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
