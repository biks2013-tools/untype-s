import Foundation

public protocol TextRefining: AnyObject {
    func refine(_ text: String) async throws -> String
    func dispose()
}

public extension TextRefining {
    func dispose() {}
}

public struct ProtocolControllerDiagnostics {
    public let write: (_ line: String, _ warning: Bool) -> Void

    public init(write: @escaping (_ line: String, _ warning: Bool) -> Void) {
        self.write = write
    }
}

public struct EndProtocolSessionOptions: Sendable, Equatable {
    public let submitPending: Bool

    public init(submitPending: Bool = false) {
        self.submitPending = submitPending
    }
}

public final class VoiceAgentProtocolController {
    public typealias TextDelivery = (_ text: String) async throws -> Void

    private let mode: InteractionMode
    private let renderer: TranscriptRendering
    private let writer: JsonlProtocolWriter?
    private let stateMachine: VoiceCommandStateMachine
    private let translationPolicy: TranslationPolicy
    private let verbose: Bool
    private let refiner: TextRefining?
    private let translator: TextRefining?
    private let clipboardWriter: TextDelivery
    private let inputWriter: TextDelivery
    private let diagnostics: ProtocolControllerDiagnostics
    private let visibleOperatorDiagnostics: Bool

    private var sessionStarted = false
    private var sessionEnded = false
    private var disposed = false

    public init(
        mode: InteractionMode,
        renderer: TranscriptRendering,
        writer: JsonlProtocolWriter? = nil,
        markers: MarkerConfig,
        initialOperators: OperatorState,
        translationPolicy: TranslationPolicy,
        verbose: Bool = false,
        refiner: TextRefining? = nil,
        translator: TextRefining? = nil,
        clipboardWriter: @escaping TextDelivery = { _ in },
        inputWriter: @escaping TextDelivery = { _ in },
        diagnostics: ProtocolControllerDiagnostics = ProtocolControllerDiagnostics(write: { _, _ in }),
        visibleOperatorDiagnostics: Bool = false
    ) {
        self.mode = mode
        self.renderer = renderer
        self.writer = writer
        self.translationPolicy = translationPolicy
        self.verbose = verbose
        self.refiner = refiner
        self.translator = translator
        self.clipboardWriter = clipboardWriter
        self.inputWriter = inputWriter
        self.diagnostics = diagnostics
        self.visibleOperatorDiagnostics = visibleOperatorDiagnostics
        self.stateMachine = VoiceCommandStateMachine(
            markers: markers,
            initialOperators: initialOperators,
            translationPolicy: translationPolicy
        )
    }

    public func startSession() throws {
        guard !sessionStarted else {
            return
        }
        sessionStarted = true
        try writeProtocol(.sessionStarted)
    }

    public func partial(_ text: String) {
        guard !disposed else {
            return
        }
        if mode != .agentProtocol {
            renderer.partial(text)
        }
    }

    public func partialContainsActionableCommand(_ text: String) -> Bool {
        guard let match = findFirstMarker(in: text, definitions: stateMachine.definitions) else {
            return false
        }
        switch match.kind {
        case .sectionEnd, .sectionCancel:
            return true
        case .literalNext:
            return false
        case .stateCommand:
            let tokens = commandArgumentTokens(after: match.end, in: text)
            guard let operatorName = tokens.first?.lowercased() else {
                return false
            }
            if operatorName == "status" {
                return true
            }
            guard OperatorKey(rawValue: operatorName) != nil else {
                return true
            }
            guard tokens.count > 1 else {
                return true
            }
            let value = tokens[1].lowercased()
            return value == "on" || value == "off"
        }
    }

    public var hasPendingContent: Bool {
        stateMachine.statusReport.pendingSection
    }

    public func final(_ text: String) async throws {
        guard !disposed else {
            return
        }

        let result = stateMachine.processFinal(text)
        if mode != .agentProtocol, !result.visibleText.isEmpty {
            renderer.final(result.visibleText)
        }
        for action in result.actions {
            try await handleAction(action)
        }
    }

    public func submitPending() async throws {
        guard !sessionEnded, !disposed else {
            return
        }
        for action in stateMachine.drainForShutdown(options: DrainForShutdownOptions(submitPending: true)) {
            try await handleAction(action)
        }
    }

    public func endSession(
        reason: String,
        options: EndProtocolSessionOptions = EndProtocolSessionOptions()
    ) async throws {
        guard !sessionEnded else {
            return
        }
        for action in stateMachine.drainForShutdown(
            options: DrainForShutdownOptions(submitPending: options.submitPending)
        ) {
            try await handleAction(action)
        }
        try writeProtocol(.sessionEnded(reason: reason))
        writer?.end()
        sessionEnded = true
    }

    public func toggleOperator(_ key: OperatorKey) async throws {
        guard !sessionEnded, !disposed else {
            return
        }
        try await handleAction(stateMachine.toggleOperator(key))
    }

    public func dispose() {
        guard !disposed else {
            return
        }
        disposed = true
        refiner?.dispose()
        translator?.dispose()
        renderer.dispose()
    }

    public func settingsSnapshot() -> ProtocolSettingsSnapshot {
        stateMachine.settingsSnapshot
    }

    private func handleAction(_ action: ProtocolAction) async throws {
        switch action {
        case .stateChanged(let key, let value, let targetPolicy):
            try writeProtocol(.stateChanged(key: key, value: value, targetPolicy: targetPolicy))
            if verbose {
                diagnostics.write("[untype] protocol state: \(key.rawValue)=\(value ? "on" : "off")", false)
            }
        case .statusReported(let report):
            try writeProtocol(.statusReported(report))
            if mode != .agentProtocol {
                renderer.refined(formatStatusReport(report))
            }
            if verbose {
                diagnostics.write("[untype] protocol status: \(formatStatusSummary(report))", false)
            }
        case .sectionSubmitted(let sectionId, let rawText, let operators):
            try writeProtocol(.sectionSubmitted(sectionId: sectionId, rawText: rawText))
            if mode != .agentProtocol {
                renderer.turnBoundary()
            }
            await processSection(sectionId: sectionId, rawText: rawText, operators: operators)
        case .sectionCancelled(let sectionId, let reason):
            try writeProtocol(.sectionCancelled(sectionId: sectionId, reason: reason))
            if verbose {
                diagnostics.write("[untype] protocol section cancelled: \(sectionId) (\(reason.rawValue))", false)
            }
        case .warning(let message):
            warn(message)
        case .sectionEmpty:
            if verbose {
                diagnostics.write("[untype] protocol: empty section ignored", false)
            }
        }
    }

    private func processSection(sectionId: String, rawText: String, operators: [OperatorKey]) async {
        var current = rawText
        var refinedText: String?
        var sourceLanguage: ProtocolLanguage?
        var targetLanguage: ProtocolLanguage?

        if operators.contains(.refine) {
            if refiner == nil {
                warn("Refine operator is enabled, but no LLM refiner is configured.")
            } else {
                operatorDiagnostic(.refine, stage: "started")
                do {
                    let refined = try await refiner!.refine(current)
                    if !refined.isEmpty {
                        refinedText = refined
                        current = refined
                    }
                    operatorDiagnostic(.refine, stage: "completed")
                } catch {
                    logOperatorFailure(.refine, error: error)
                }
            }
        }

        if operators.contains(.translate) {
            if translator == nil {
                warn("Translate operator is enabled, but no LLM translator is configured.")
            } else {
                operatorDiagnostic(.translate, stage: "started")
                sourceLanguage = detectProtocolLanguage(current)
                targetLanguage = targetLanguageFor(source: sourceLanguage!, policy: translationPolicy)
                do {
                    let prompt = "Translate the following text to \(targetLanguage == .english ? "English" : "Greek"). Return only the translated text.\n\n\(current)"
                    let translated = try await translator!.refine(prompt)
                    if !translated.isEmpty {
                        current = translated
                    }
                    operatorDiagnostic(.translate, stage: "completed")
                } catch {
                    logOperatorFailure(.translate, error: error)
                }
            }
        }

        try? writeProtocol(.sectionProcessed(
            sectionId: sectionId,
            operators: operators,
            rawText: rawText,
            refinedText: refinedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            outputText: current
        ))

        if mode != .agentProtocol, !current.isEmpty {
            renderer.refined(current)
        }

        if operators.contains(.clipboard) {
            operatorDiagnostic(.clipboard, stage: "started")
            do {
                try await clipboardWriter(current)
                try writeProtocol(.clipboardCopied(sectionId: sectionId))
                operatorDiagnostic(.clipboard, stage: "completed")
            } catch {
                logOperatorFailure(.clipboard, error: error)
            }
        }

        if operators.contains(.input) {
            operatorDiagnostic(.input, stage: "started")
            do {
                try await inputWriter(current)
                try writeProtocol(.inputSent(sectionId: sectionId))
                operatorDiagnostic(.input, stage: "completed")
            } catch {
                warn("input operator failed: \(error.localizedDescription). Check that the target control is focused before command send completes, and grant Accessibility permission to the terminal app running untype.")
            }
        }
    }

    private func writeProtocol(_ event: ProtocolEvent) throws {
        try writer?.write(event)
    }

    private func warn(_ message: String) {
        diagnostics.write("[untype] protocol warning: \(message)", true)
        try? writeProtocol(.warning(message: message))
    }

    private func logOperatorFailure(_ operatorKey: OperatorKey, error: Error) {
        if visibleOperatorDiagnostics {
            warn("\(operatorKey.rawValue) operator failed: \(error.localizedDescription)")
            return
        }
        guard verbose else {
            return
        }
        diagnostics.write("[untype] protocol \(operatorKey.rawValue) failed: \(error.localizedDescription)", true)
    }

    private func operatorDiagnostic(_ operatorKey: OperatorKey, stage: String) {
        guard visibleOperatorDiagnostics || verbose else {
            return
        }
        diagnostics.write("[untype] protocol \(operatorKey.rawValue) operator \(stage)", false)
    }
}

public func detectProtocolLanguage(_ text: String) -> ProtocolLanguage {
    for scalar in text.unicodeScalars {
        let value = scalar.value
        if (0x0370...0x03FF).contains(value) || (0x1F00...0x1FFF).contains(value) {
            return .greek
        }
    }
    return .english
}

public func targetLanguageFor(source: ProtocolLanguage, policy: TranslationPolicy) -> ProtocolLanguage {
    switch policy {
    case .toEnglish:
        return .english
    case .toGreek:
        return .greek
    case .opposite:
        return source == .greek ? .english : .greek
    }
}

private func formatStatusReport(_ report: ProtocolStatusReport) -> String {
    "[untype] status: \(formatStatusSummary(report))"
}

private func formatStatusSummary(_ report: ProtocolStatusReport) -> String {
    [
        "refine=\(report.operators.refine ? "on" : "off")",
        "translate=\(report.operators.translate ? "on" : "off")",
        "clipboard=\(report.operators.clipboard ? "on" : "off")",
        "input=\(report.operators.input ? "on" : "off")",
        "translation_policy=\(report.translationPolicy.rawValue)",
        "pending_section=\(report.pendingSection ? "yes" : "no")"
    ].joined(separator: ", ")
}

private func commandArgumentTokens(after start: String.Index, in text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var index = start
    while index < text.endIndex, tokens.count < 2 {
        let character = text[index]
        if character.isWhitespace || [".", ",", ";", ":", "!", "?"].contains(character) {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        } else {
            current.append(character)
        }
        index = text.index(after: index)
    }
    if !current.isEmpty, tokens.count < 2 {
        tokens.append(current)
    }
    return tokens
}
