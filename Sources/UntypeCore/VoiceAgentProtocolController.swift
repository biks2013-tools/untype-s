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
    public typealias FocusedInputTextDelivery = (_ text: String) async throws -> FocusedInputDeliveryResult

    private let mode: InteractionMode
    private let renderer: TranscriptRendering
    private let writer: JsonlProtocolWriter?
    private let stateMachine: VoiceCommandStateMachine
    private let translationPolicy: TranslationPolicy
    private let translationUserPromptTemplate: String
    private let verbose: Bool
    private let refiner: TextRefining?
    private let translator: TextRefining?
    private let compositeRefineTranslator: CompositeRefineTranslating?
    private let clipboardWriter: TextDelivery
    private let focusedInputWriter: FocusedInputTextDelivery
    private let diagnostics: ProtocolControllerDiagnostics
    private let visibleOperatorDiagnostics: Bool
    private let streamingProgress: (@Sendable (String) -> Void)?

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
        translationUserPromptTemplate: String = UntypePromptDefaults.translationUserPromptTemplate,
        verbose: Bool = false,
        refiner: TextRefining? = nil,
        translator: TextRefining? = nil,
        compositeRefineTranslator: CompositeRefineTranslating? = nil,
        clipboardWriter: @escaping TextDelivery = { _ in },
        inputWriter: @escaping TextDelivery = { _ in },
        focusedInputWriter: FocusedInputTextDelivery? = nil,
        diagnostics: ProtocolControllerDiagnostics = ProtocolControllerDiagnostics(write: { _, _ in }),
        visibleOperatorDiagnostics: Bool = false,
        streamingProgress: (@Sendable (String) -> Void)? = nil
    ) {
        self.mode = mode
        self.renderer = renderer
        self.writer = writer
        self.translationPolicy = translationPolicy
        self.translationUserPromptTemplate = translationUserPromptTemplate
        self.verbose = verbose
        self.refiner = refiner
        self.translator = translator
        self.compositeRefineTranslator = compositeRefineTranslator
        self.clipboardWriter = clipboardWriter
        if let focusedInputWriter {
            self.focusedInputWriter = focusedInputWriter
        } else {
            self.focusedInputWriter = { text in
                try await inputWriter(text)
                return FocusedInputDeliveryResult.success(method: "in-process")
            }
        }
        self.diagnostics = diagnostics
        self.visibleOperatorDiagnostics = visibleOperatorDiagnostics
        self.streamingProgress = streamingProgress
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
            _ = try await handleAction(action)
        }
    }

    @discardableResult
    public func submitPending() async throws -> ProtocolSubmissionSummary {
        guard !sessionEnded, !disposed else {
            return ProtocolSubmissionSummary()
        }
        var summary = ProtocolSubmissionSummary()
        for action in stateMachine.drainForShutdown(options: DrainForShutdownOptions(submitPending: true)) {
            summary.merge(try await handleAction(action))
        }
        return summary
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
            _ = try await handleAction(action)
        }
        try writeProtocol(.sessionEnded(reason: reason))
        writer?.end()
        sessionEnded = true
    }

    public func toggleOperator(_ key: OperatorKey) async throws {
        guard !sessionEnded, !disposed else {
            return
        }
        _ = try await handleAction(stateMachine.toggleOperator(key))
    }

    public func dispose() {
        guard !disposed else {
            return
        }
        disposed = true
        refiner?.dispose()
        translator?.dispose()
        compositeRefineTranslator?.dispose()
        renderer.dispose()
    }

    public func settingsSnapshot() -> ProtocolSettingsSnapshot {
        stateMachine.settingsSnapshot
    }

    private func handleAction(_ action: ProtocolAction) async throws -> ProtocolSubmissionSummary {
        switch action {
        case .stateChanged(let key, let value, let targetPolicy):
            try writeProtocol(.stateChanged(key: key, value: value, targetPolicy: targetPolicy))
            if verbose {
                diagnostics.write("[untype] protocol state: \(key.rawValue)=\(value ? "on" : "off")", false)
            }
            return ProtocolSubmissionSummary()
        case .statusReported(let report):
            try writeProtocol(.statusReported(report))
            if mode != .agentProtocol {
                renderer.refined(formatStatusReport(report))
            }
            if verbose {
                diagnostics.write("[untype] protocol status: \(formatStatusSummary(report))", false)
            }
            return ProtocolSubmissionSummary()
        case .sectionSubmitted(let sectionId, let rawText, let operators):
            try writeProtocol(.sectionSubmitted(sectionId: sectionId, rawText: rawText))
            if mode != .agentProtocol {
                renderer.turnBoundary()
            }
            return await processSection(sectionId: sectionId, rawText: rawText, operators: operators)
        case .sectionCancelled(let sectionId, let reason):
            try writeProtocol(.sectionCancelled(sectionId: sectionId, reason: reason))
            if verbose {
                diagnostics.write("[untype] protocol section cancelled: \(sectionId) (\(reason.rawValue))", false)
            }
            return ProtocolSubmissionSummary()
        case .warning(let message):
            warn(message)
            return ProtocolSubmissionSummary()
        case .sectionEmpty:
            if verbose {
                diagnostics.write("[untype] protocol: empty section ignored", false)
            }
            return ProtocolSubmissionSummary()
        }
    }

    private func processSection(sectionId: String, rawText: String, operators: [OperatorKey]) async -> ProtocolSubmissionSummary {
        let sectionStarted = DispatchTime.now().uptimeNanoseconds
        var current = rawText
        var refinedText: String?
        var sourceLanguage: ProtocolLanguage?
        var targetLanguage: ProtocolLanguage?
        var summary = ProtocolSubmissionSummary(sectionsProcessed: 1)
        let shouldCompositeProcess = operators.contains(.refine)
            && operators.contains(.translate)
            && compositeRefineTranslator != nil
        let onProgress = makeStreamingProgressHandler(sectionId: sectionId)

        if shouldCompositeProcess {
            operatorDiagnostic(.refine, stage: "started")
            operatorDiagnostic(.translate, stage: "started")
            sourceLanguage = detectProtocolLanguage(current)
            targetLanguage = targetLanguageFor(source: sourceLanguage!, policy: translationPolicy)
            do {
                let started = DispatchTime.now().uptimeNanoseconds
                let result = try await compositeRefineTranslator!.refineAndTranslate(
                    CompositeRefineTranslateRequest(
                        rawText: rawText,
                        targetLanguageName: languageDisplayName(targetLanguage!)
                    ),
                    onProgress: onProgress
                )
                let elapsed = releaseLatencyMilliseconds(from: started)
                summary.refineMs = elapsed
                summary.translateMs = elapsed
                refinedText = result.refinedText
                current = result.translatedText
                operatorDiagnostic(.refine, stage: "completed")
                operatorDiagnostic(.translate, stage: "completed")
            } catch {
                summary.refineMs = summary.refineMs ?? 0
                summary.translateMs = summary.translateMs ?? 0
                logOperatorFailure(.refine, error: error)
                logOperatorFailure(.translate, error: error)
            }
        } else if operators.contains(.refine) {
            if refiner == nil {
                warn("Refine operator is enabled, but no LLM refiner is configured.")
            } else {
                operatorDiagnostic(.refine, stage: "started")
                do {
                    let started = DispatchTime.now().uptimeNanoseconds
                    let refined = try await refine(current, using: refiner!, onProgress: onProgress)
                    summary.refineMs = releaseLatencyMilliseconds(from: started)
                    if !refined.isEmpty {
                        refinedText = refined
                        current = refined
                    }
                    operatorDiagnostic(.refine, stage: "completed")
                } catch {
                    summary.refineMs = summary.refineMs ?? 0
                    logOperatorFailure(.refine, error: error)
                }
            }
        }

        if !shouldCompositeProcess && operators.contains(.translate) {
            if translator == nil {
                warn("Translate operator is enabled, but no LLM translator is configured.")
            } else {
                operatorDiagnostic(.translate, stage: "started")
                sourceLanguage = detectProtocolLanguage(current)
                targetLanguage = targetLanguageFor(source: sourceLanguage!, policy: translationPolicy)
                do {
                    let prompt = renderTranslationPrompt(
                        text: current,
                        targetLanguage: languageDisplayName(targetLanguage!)
                    )
                    let started = DispatchTime.now().uptimeNanoseconds
                    let translated = try await refine(prompt, using: translator!, onProgress: onProgress)
                    summary.translateMs = releaseLatencyMilliseconds(from: started)
                    if !translated.isEmpty {
                        current = translated
                    }
                    operatorDiagnostic(.translate, stage: "completed")
                } catch {
                    summary.translateMs = summary.translateMs ?? 0
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
                let started = DispatchTime.now().uptimeNanoseconds
                try await clipboardWriter(current)
                summary.clipboardMs = releaseLatencyMilliseconds(from: started)
                try writeProtocol(.clipboardCopied(sectionId: sectionId))
                operatorDiagnostic(.clipboard, stage: "completed")
            } catch {
                summary.clipboardMs = summary.clipboardMs ?? 0
                logOperatorFailure(.clipboard, error: error)
            }
        }

        if operators.contains(.input) {
            operatorDiagnostic(.input, stage: "started")
            do {
                let started = DispatchTime.now().uptimeNanoseconds
                let result = try await focusedInputWriter(current)
                let elapsed = releaseLatencyMilliseconds(from: started)
                summary.focusedInputMs = elapsed
                summary.focusedInput = ReleaseLatencyFocusedInput.from(result)
                guard result.ok else {
                    throw FocusedInputDeliveryError(
                        message: "\(result.code ?? "focused_input_failed"): \(result.message ?? "Focused input delivery failed.")",
                        code: result.code
                    )
                }
                try writeProtocol(.inputSent(sectionId: sectionId))
                operatorDiagnostic(.input, stage: "completed via \(result.method ?? "unknown")")
            } catch {
                summary.focusedInputMs = summary.focusedInputMs ?? 0
                summary.focusedInput = ReleaseLatencyFocusedInput.failure(error: error)
                warn("input operator failed: \(error.localizedDescription) Check that the target control is focused before command send completes, and grant Accessibility permission to the app running untype.")
            }
        }
        summary.operatorProcessingMs = releaseLatencyMilliseconds(from: sectionStarted)
        return summary
    }

    /// Builds the streaming progress closure forwarded to the refine/translate/composite
    /// streaming call sites. When invoked (only when a streaming-capable refiner actually
    /// streams), it (a) forwards the accumulated DISPLAY text to the injected overlay sink,
    /// (b) emits a `streaming.progress` protocol event, and (c) writes one verbose diagnostic
    /// line. It NEVER affects the committed result — that remains the strict final value
    /// returned by the refine/translate/composite call.
    private func makeStreamingProgressHandler(sectionId: String) -> ((String) -> Void) {
        return { [weak self] accumulated in
            guard let self else {
                return
            }
            self.streamingProgress?(accumulated)
            try? self.writeProtocol(.streamingProgress(sectionId: sectionId, accumulatedText: accumulated))
            if self.visibleOperatorDiagnostics || self.verbose {
                self.diagnostics.write(
                    "[untype] protocol streaming progress: \(sectionId) (\(accumulated.count) chars)",
                    false
                )
            }
        }
    }

    /// Refines `text` through the given refiner, using the streaming overload when the refiner
    /// conforms to `StreamingTextRefining` (and thus may stream); otherwise falls back to the
    /// existing one-shot `refine(_:)` path. The returned value is always the strict final result.
    private func refine(
        _ text: String,
        using refiner: TextRefining,
        onProgress: @escaping (String) -> Void
    ) async throws -> String {
        if let streaming = refiner as? StreamingTextRefining {
            return try await streaming.refine(text, onProgress: onProgress)
        }
        return try await refiner.refine(text)
    }

    private func writeProtocol(_ event: ProtocolEvent) throws {
        try writer?.write(event)
    }

    private func warn(_ message: String) {
        diagnostics.write("[untype] protocol warning: \(message)", true)
        try? writeProtocol(.warning(message: message))
    }

    private func renderTranslationPrompt(text: String, targetLanguage: String) -> String {
        translationUserPromptTemplate
            .replacingOccurrences(of: "{target_language}", with: targetLanguage)
            .replacingOccurrences(of: "{text}", with: text)
    }

    private func languageDisplayName(_ language: ProtocolLanguage) -> String {
        language == .english ? "English" : "Greek"
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
