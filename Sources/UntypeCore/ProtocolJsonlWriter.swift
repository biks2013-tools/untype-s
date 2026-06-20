import Foundation

public enum ProtocolLanguage: String, Sendable, Equatable {
    case greek = "el"
    case english = "en"
}

public enum ProtocolEvent: Sendable, Equatable {
    case sessionStarted
    case sessionEnded(reason: String)
    case stateChanged(key: OperatorKey, value: Bool, targetPolicy: TranslationPolicy?)
    case statusReported(ProtocolStatusReport)
    case sectionSubmitted(sectionId: String, rawText: String)
    case sectionProcessed(
        sectionId: String,
        operators: [OperatorKey],
        rawText: String,
        refinedText: String?,
        sourceLanguage: ProtocolLanguage?,
        targetLanguage: ProtocolLanguage?,
        outputText: String
    )
    case streamingProgress(sectionId: String, accumulatedText: String)
    case clipboardCopied(sectionId: String)
    case inputSent(sectionId: String)
    case sectionCancelled(sectionId: String, reason: SectionCancelReason)
    case warning(message: String)
}

public final class JsonlProtocolWriter {
    private let output: TextOutput
    private var seq = 0
    private var ended = false

    public init(output: TextOutput) {
        self.output = output
    }

    public func write(_ event: ProtocolEvent) throws {
        guard !ended else {
            return
        }
        seq += 1
        var object = event.jsonObject
        object["seq"] = seq
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard let line = String(data: data, encoding: .utf8) else {
            throw UntypeError.invalidConfiguration("Failed to encode protocol event as UTF-8 JSON.")
        }
        output.write(line + "\n")
    }

    public func end() {
        ended = true
    }
}

private extension ProtocolEvent {
    var jsonObject: [String: Any] {
        switch self {
        case .sessionStarted:
            return [
                "type": "session.started",
                "protocol": "untype.voice-agent.v1"
            ]
        case .sessionEnded(let reason):
            return [
                "type": "session.ended",
                "reason": reason
            ]
        case .stateChanged(let key, let value, let targetPolicy):
            var object: [String: Any] = [
                "type": "state.changed",
                "key": key.rawValue,
                "value": value
            ]
            if let targetPolicy {
                object["target_policy"] = targetPolicy.rawValue
            }
            return object
        case .statusReported(let report):
            return [
                "type": "status.reported",
                "operators": report.operators.jsonObject,
                "translation_policy": report.translationPolicy.rawValue,
                "pending_section": report.pendingSection
            ]
        case .sectionSubmitted(let sectionId, let rawText):
            return [
                "type": "section.submitted",
                "section_id": sectionId,
                "raw_text": rawText
            ]
        case .sectionProcessed(
            let sectionId,
            let operators,
            let rawText,
            let refinedText,
            let sourceLanguage,
            let targetLanguage,
            let outputText
        ):
            var object: [String: Any] = [
                "type": "section.processed",
                "section_id": sectionId,
                "operators": operators.map(\.rawValue),
                "raw_text": rawText,
                "output_text": outputText
            ]
            if let refinedText {
                object["refined_text"] = refinedText
            }
            if let sourceLanguage {
                object["source_language"] = sourceLanguage.rawValue
            }
            if let targetLanguage {
                object["target_language"] = targetLanguage.rawValue
            }
            return object
        case .streamingProgress(let sectionId, let accumulatedText):
            return [
                "type": "streaming.progress",
                "section_id": sectionId,
                "accumulated_text": accumulatedText
            ]
        case .clipboardCopied(let sectionId):
            return [
                "type": "clipboard.copied",
                "section_id": sectionId
            ]
        case .inputSent(let sectionId):
            return [
                "type": "input.sent",
                "section_id": sectionId
            ]
        case .sectionCancelled(let sectionId, let reason):
            return [
                "type": "section.cancelled",
                "section_id": sectionId,
                "reason": reason.rawValue
            ]
        case .warning(let message):
            return [
                "type": "protocol.warning",
                "message": message
            ]
        }
    }
}

private extension OperatorState {
    var jsonObject: [String: Bool] {
        [
            "refine": refine,
            "translate": translate,
            "clipboard": clipboard,
            "input": input
        ]
    }
}
