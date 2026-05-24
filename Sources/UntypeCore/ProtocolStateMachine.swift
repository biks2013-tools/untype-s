import Foundation

public enum OperatorKey: String, CaseIterable, Sendable, Equatable, Codable {
    case refine
    case translate
    case clipboard
    case input
}

public struct ProtocolSettingsSnapshot: Sendable, Equatable, Codable {
    public let operators: OperatorState
    public let translationPolicy: TranslationPolicy

    enum CodingKeys: String, CodingKey {
        case operators
        case translationPolicy = "translation_policy"
    }

    public init(operators: OperatorState, translationPolicy: TranslationPolicy) {
        self.operators = operators
        self.translationPolicy = translationPolicy
    }
}

public struct ProtocolStatusReport: Sendable, Equatable {
    public let operators: OperatorState
    public let translationPolicy: TranslationPolicy
    public let pendingSection: Bool
}

public enum ProtocolAction: Sendable, Equatable {
    case stateChanged(key: OperatorKey, value: Bool, targetPolicy: TranslationPolicy?)
    case statusReported(ProtocolStatusReport)
    case sectionSubmitted(sectionId: String, rawText: String, operators: [OperatorKey])
    case sectionCancelled(sectionId: String, reason: SectionCancelReason)
    case warning(message: String)
    case sectionEmpty
}

public enum SectionCancelReason: String, Sendable, Equatable, Codable {
    case spokenCancel = "spoken_cancel"
    case shutdown
}

public struct StateMachineResult: Sendable, Equatable {
    public let visibleText: String
    public let actions: [ProtocolAction]
}

public struct DrainForShutdownOptions: Sendable, Equatable {
    public let submitPending: Bool

    public init(submitPending: Bool = false) {
        self.submitPending = submitPending
    }
}

public final class VoiceCommandStateMachine {
    private let markerDefinitionsList: [MarkerDefinition]
    private let translationPolicy: TranslationPolicy
    private var operatorState: OperatorState
    private var buffer = ""
    private var literalNextPending = false
    private var sectionCounter = 0
    private var currentSectionId: String?

    public init(
        markers: MarkerConfig,
        initialOperators: OperatorState,
        translationPolicy: TranslationPolicy
    ) {
        self.markerDefinitionsList = markerDefinitions(for: markers)
        self.operatorState = initialOperators
        self.translationPolicy = translationPolicy
    }

    public var state: OperatorState {
        operatorState
    }

    public var settingsSnapshot: ProtocolSettingsSnapshot {
        ProtocolSettingsSnapshot(operators: operatorState, translationPolicy: translationPolicy)
    }

    public var statusReport: ProtocolStatusReport {
        statusReport(for: buffer)
    }

    public var definitions: [MarkerDefinition] {
        markerDefinitionsList
    }

    @discardableResult
    public func toggleOperator(_ operatorKey: OperatorKey) -> ProtocolAction {
        setOperator(operatorKey, enabled: !operatorState.value(for: operatorKey))
    }

    @discardableResult
    public func setOperator(_ operatorKey: OperatorKey, enabled: Bool) -> ProtocolAction {
        operatorState = operatorState.setting(operatorKey, to: enabled)
        return .stateChanged(
            key: operatorKey,
            value: enabled,
            targetPolicy: operatorKey == .translate ? translationPolicy : nil
        )
    }

    public func processFinal(_ text: String) -> StateMachineResult {
        let visibleText = stripMarkersForDisplay(text, definitions: markerDefinitionsList)
        appendToBuffer(text)

        var actions: [ProtocolAction] = []
        var searchStart = buffer.startIndex

        while searchStart <= buffer.endIndex {
            guard let match = findFirstMarker(in: buffer, definitions: markerDefinitionsList, startAt: searchStart) else {
                break
            }

            if literalNextPending, match.kind != .literalNext {
                literalNextPending = false
                searchStart = match.end
                continue
            }

            switch match.kind {
            case .literalNext:
                buffer.replaceSubrange(match.start..<match.end, with: " ")
                literalNextPending = true
                searchStart = match.start
            case .stateCommand:
                let consumed = consumeCommandArgs(in: buffer, start: match.end)
                let action = applyCommand(
                    operatorRaw: consumed.operatorName,
                    valueRaw: consumed.value,
                    nextBuffer: removingRange(match.start..<consumed.end, from: buffer)
                )
                actions.append(action)
                buffer.replaceSubrange(match.start..<consumed.end, with: " ")
                searchStart = match.start
            case .sectionEnd:
                let rawText = normalizePayloadWhitespace(String(buffer[..<match.start]))
                let after = String(buffer[match.end...])
                if rawText.isEmpty {
                    actions.append(.sectionEmpty)
                    currentSectionId = nil
                } else {
                    actions.append(.sectionSubmitted(
                        sectionId: currentSectionId ?? nextSectionId(),
                        rawText: rawText,
                        operators: activeOperators()
                    ))
                    currentSectionId = nil
                }
                buffer = normalizePayloadWhitespace(after)
                if !buffer.isEmpty {
                    _ = ensureSectionId()
                }
                searchStart = buffer.startIndex
            case .sectionCancel:
                let rawText = normalizePayloadWhitespace(String(buffer[..<match.start]))
                let after = String(buffer[match.end...])
                if !rawText.isEmpty {
                    actions.append(.sectionCancelled(
                        sectionId: currentSectionId ?? nextSectionId(),
                        reason: .spokenCancel
                    ))
                }
                currentSectionId = nil
                buffer = normalizePayloadWhitespace(after)
                if !buffer.isEmpty {
                    _ = ensureSectionId()
                }
                searchStart = buffer.startIndex
            }
        }

        return StateMachineResult(visibleText: visibleText, actions: actions)
    }

    public func drainForShutdown(options: DrainForShutdownOptions = DrainForShutdownOptions()) -> [ProtocolAction] {
        let rawText = normalizePayloadWhitespace(buffer)
        guard !rawText.isEmpty else {
            return []
        }
        let sectionId = currentSectionId ?? nextSectionId()
        buffer = ""
        currentSectionId = nil
        if options.submitPending {
            return [.sectionSubmitted(sectionId: sectionId, rawText: rawText, operators: activeOperators())]
        }
        return [.sectionCancelled(sectionId: sectionId, reason: .shutdown)]
    }

    private func appendToBuffer(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        buffer = normalizePayloadWhitespace(buffer.isEmpty ? text : "\(buffer) \(text)")
        _ = ensureSectionId()
    }

    private func ensureSectionId() -> String {
        if currentSectionId == nil {
            currentSectionId = nextSectionId()
        }
        return currentSectionId!
    }

    private func nextSectionId() -> String {
        sectionCounter += 1
        return "sec_\(String(format: "%06d", sectionCounter))"
    }

    private func applyCommand(operatorRaw: String?, valueRaw: String?, nextBuffer: String) -> ProtocolAction {
        let operatorName = operatorRaw?.lowercased()
        let value = valueRaw?.lowercased()

        if operatorName == "status" {
            if let valueRaw {
                return .warning(message: "Unknown protocol value for status: \(valueRaw). Expected no value.")
            }
            return .statusReported(statusReport(for: nextBuffer))
        }

        guard let operatorName, let operatorKey = OperatorKey(rawValue: operatorName) else {
            return .warning(message: "Unknown protocol operator: \(operatorRaw ?? "<missing>").")
        }

        if let value, value != "on", value != "off" {
            return .warning(message: "Unknown protocol value for \(operatorName): \(valueRaw ?? "<missing>"). Expected on or off.")
        }

        return setOperator(operatorKey, enabled: value == nil ? true : value == "on")
    }

    private func activeOperators() -> [OperatorKey] {
        OperatorKey.allCases.filter { operatorState.value(for: $0) }
    }

    private func statusReport(for reportBuffer: String) -> ProtocolStatusReport {
        ProtocolStatusReport(
            operators: operatorState,
            translationPolicy: translationPolicy,
            pendingSection: !normalizePayloadWhitespace(reportBuffer).isEmpty
        )
    }
}

private func removingRange(_ range: Range<String.Index>, from text: String) -> String {
    var copy = text
    copy.replaceSubrange(range, with: " ")
    return copy
}

extension OperatorState: Codable {
    enum CodingKeys: String, CodingKey {
        case refine
        case translate
        case clipboard
        case input
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            refine: try container.decode(Bool.self, forKey: .refine),
            translate: try container.decode(Bool.self, forKey: .translate),
            clipboard: try container.decode(Bool.self, forKey: .clipboard),
            input: try container.decodeIfPresent(Bool.self, forKey: .input) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(refine, forKey: .refine)
        try container.encode(translate, forKey: .translate)
        try container.encode(clipboard, forKey: .clipboard)
        try container.encode(input, forKey: .input)
    }

    public func value(for key: OperatorKey) -> Bool {
        switch key {
        case .refine:
            return refine
        case .translate:
            return translate
        case .clipboard:
            return clipboard
        case .input:
            return input
        }
    }

    public func setting(_ key: OperatorKey, to value: Bool) -> OperatorState {
        switch key {
        case .refine:
            return OperatorState(refine: value, translate: translate, clipboard: clipboard, input: input)
        case .translate:
            return OperatorState(refine: refine, translate: value, clipboard: clipboard, input: input)
        case .clipboard:
            return OperatorState(refine: refine, translate: translate, clipboard: value, input: input)
        case .input:
            return OperatorState(refine: refine, translate: translate, clipboard: clipboard, input: value)
        }
    }
}

extension TranslationPolicy: Codable {}
