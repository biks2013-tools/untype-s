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

    private static func shortTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
