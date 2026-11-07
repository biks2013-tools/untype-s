import Foundation

public protocol UntypeRuntimeSession: AnyObject, Sendable {
    func start() async throws
    func submitPending() async throws
    func stop(reason: String, submitPending: Bool) async
    func recordedFailure() -> Error?
    func toggleOperator(_ key: OperatorKey) async throws
}

extension TranscriptionSessionRuntime: UntypeRuntimeSession {}
extension TranscriptionSessionRuntime: @unchecked Sendable {}

public enum UntypeRuntimeFactory {
    /// An alternative LLM's clients with the same prompts as the primary
    /// LLM; nil when that alternative LLM is not configured. `second`: the
    /// second alternative slot (Push-to-Act) instead of the first.
    static func makeAlternativeLLMClients(config: ResolvedConfig, second: Bool = false) throws -> ProtocolLLMClients? {
        guard let llm = second ? config.alternativeLLM2 : config.alternativeLLM else {
            return nil
        }
        return ProtocolLLMClients(
            refiner: try LLMRefinerFactory.makeRefiner(config: llm),
            translator: try LLMRefinerFactory.makeTranslator(
                config: llm,
                systemPrompt: config.prompts.translationSystemPrompt
            ),
            compositeRefineTranslator: try LLMRefinerFactory.makeCompositeRefineTranslator(
                config: llm,
                prompts: config.prompts
            ),
            asker: try LLMRefinerFactory.makeAsker(
                config: llm,
                systemPrompt: config.prompts.askSystemPrompt
            )
        )
    }

    public static func make(
        config: ResolvedConfig,
        stdout: TextOutput,
        stderr: TextOutput,
        stdoutIsTTY: Bool
    ) throws -> UntypeRuntimeSession {
        let protocolConfig = try resolvedProtocolConfig(config.protocolConfig)
        let diagnostics = ProtocolControllerDiagnostics { line, _ in
            stderr.write(line.hasSuffix("\n") ? line : "\(line)\n")
        }
        let renderer = TranscriptRenderer(
            output: stdout,
            mode: config.outputMode,
            isTTY: stdoutIsTTY
        )
        let protocolWriter = try makeProtocolWriter(
            protocolConfig: protocolConfig,
            stdout: stdout
        )
        let refiner = try LLMRefinerFactory.makeRefiner(config: config.llm)
        let translator = try LLMRefinerFactory.makeTranslator(
            config: config.llm,
            systemPrompt: config.prompts.translationSystemPrompt
        )
        let compositeRefineTranslator = try LLMRefinerFactory.makeCompositeRefineTranslator(
            config: config.llm,
            prompts: config.prompts
        )
        let asker = try LLMRefinerFactory.makeAsker(
            config: config.llm,
            systemPrompt: config.prompts.askSystemPrompt
        )
        let alternativeLLM = try makeAlternativeLLMClients(config: config)
        let clipboardWriter = MacOSClipboardWriter()
        let focusedInputDelivery = FocusedInputDelivery()
        let releaseLatencyLogger = try makeReleaseLatencyLogger(config.releaseLatencyLogging)
        let controller = VoiceAgentProtocolController(
            mode: protocolConfig.interactionMode,
            renderer: renderer,
            writer: protocolWriter,
            markers: protocolConfig.markers,
            initialOperators: protocolConfig.initialOperators,
            translationPolicy: protocolConfig.translationPolicy,
            translationUserPromptTemplate: config.prompts.translationUserPromptTemplate,
            verbose: config.verbose,
            refiner: refiner,
            translator: translator,
            compositeRefineTranslator: compositeRefineTranslator,
            asker: asker,
            alternativeLLM: alternativeLLM,
            askUserPromptTemplate: config.prompts.askUserPromptTemplate,
            askTranslatedUserPromptTemplate: config.prompts.askTranslatedUserPromptTemplate,
            askConversation: AskConversation(),
            selectionContextTemplate: config.prompts.selectionContextTemplate,
            askSelectionTemplate: config.prompts.askSelectionTemplate,
            askConversationTemplate: config.prompts.askConversationTemplate,
            screenshotContextTemplate: config.prompts.screenshotContextTemplate,
            askScreenshotTemplate: config.prompts.askScreenshotTemplate,
            clipboardWriter: { text in try await clipboardWriter.copy(text) },
            focusedInputWriter: { text in try await focusedInputDelivery.deliver(text) },
            diagnostics: diagnostics
        )
        let audioSource = AVFoundationAudioSource(options: AVFoundationAudioSourceOptions(config: config))
        let transcriber: RuntimeTranscriber
        switch config.sttProvider {
        case .soniox:
            transcriber = try SonioxTranscriber(options: SonioxTranscriberOptions(config: config))
        case .elevenlabs:
            transcriber = try ElevenLabsTranscriber(options: ElevenLabsTranscriberOptions(config: config))
        }

        return TranscriptionSessionRuntime(
            audioSource: audioSource,
            transcriber: transcriber,
            protocolController: controller,
            options: TranscriptionSessionRuntimeOptions(
                verbose: config.verbose,
                sttProviderLabel: config.sttProvider.rawValue,
                diagnostics: diagnostics,
                quickClose: config.quickClose,
                releaseLatencyLogger: releaseLatencyLogger,
                emit: { event in
                    switch event {
                    case .ready(let message):
                        stderr.write(message.hasSuffix("\n") ? message : "\(message)\n")
                    case .stateChanged(let state, let reason):
                        guard config.verbose else {
                            return
                        }
                        let detail = reason.map { " (\($0))" } ?? ""
                        stderr.write("[untype] session state: \(state.rawValue)\(detail)\n")
                    case .diagnostic:
                        return
                    case .audioActivity:
                        return
                    }
                },
                saveProtocolSettings: { snapshot in
                    try savePersistedProtocolSettings(snapshot)
                }
            )
        )
    }

    public static func makeForUI(
        config: ResolvedConfig,
        audioGate: RuntimeAudioGate? = nil,
        transcript: @escaping @Sendable (_ event: UITranscriptEvent) -> Void,
        protocolOutput: TextOutput,
        diagnosticsOutput: TextOutput,
        eventSink: @escaping @Sendable (_ event: TranscriptionSessionEvent) -> Void,
        focusedInputPreparation: @escaping @Sendable () async -> Void = {},
        focusedInputReconciliation: @escaping @Sendable (_ text: String) async -> LiveInputReconciliation = { _ in .notLive },
        streamingProgress: (@Sendable (String) -> Void)? = nil,
        turnContext: UntypeTurnContext? = nil,
        askConversation: AskConversation = AskConversation()
    ) throws -> UntypeRuntimeSession {
        let protocolConfig = try resolvedProtocolConfig(config.protocolConfig)
        let controllerDiagnostics = ProtocolControllerDiagnostics { line, warning in
            diagnosticsOutput.write(line.hasSuffix("\n") ? line : "\(line)\n")
            eventSink(.diagnostic(message: line, warning: warning))
        }
        let runtimeDiagnostics = ProtocolControllerDiagnostics { line, _ in
            diagnosticsOutput.write(line.hasSuffix("\n") ? line : "\(line)\n")
        }
        let renderer = UITranscriptRenderer(emit: transcript)
        let protocolWriter = try makeUIProtocolWriter(
            protocolConfig: protocolConfig,
            output: protocolOutput
        )
        let refiner = try LLMRefinerFactory.makeRefiner(config: config.llm)
        let translator = try LLMRefinerFactory.makeTranslator(
            config: config.llm,
            systemPrompt: config.prompts.translationSystemPrompt
        )
        let compositeRefineTranslator = try LLMRefinerFactory.makeCompositeRefineTranslator(
            config: config.llm,
            prompts: config.prompts
        )
        let asker = try LLMRefinerFactory.makeAsker(
            config: config.llm,
            systemPrompt: config.prompts.askSystemPrompt
        )
        let alternativeLLM = try makeAlternativeLLMClients(config: config)
        let clipboardWriter = MacOSClipboardWriter()
        let focusedInputDelivery = FocusedInputDelivery(forceInProcess: true)
        let livePasteDelivery = FocusedInputDelivery(method: .pasteKeycode, forceInProcess: true)
        let releaseLatencyLogger = try makeReleaseLatencyLogger(config.releaseLatencyLogging)
        let controller = VoiceAgentProtocolController(
            mode: protocolConfig.interactionMode,
            renderer: renderer,
            writer: protocolWriter,
            markers: protocolConfig.markers,
            initialOperators: protocolConfig.initialOperators,
            translationPolicy: protocolConfig.translationPolicy,
            translationUserPromptTemplate: config.prompts.translationUserPromptTemplate,
            verbose: config.verbose,
            refiner: refiner,
            translator: translator,
            compositeRefineTranslator: compositeRefineTranslator,
            asker: asker,
            alternativeLLM: alternativeLLM,
            askUserPromptTemplate: config.prompts.askUserPromptTemplate,
            askTranslatedUserPromptTemplate: config.prompts.askTranslatedUserPromptTemplate,
            turnContext: turnContext,
            askConversation: askConversation,
            selectionContextTemplate: config.prompts.selectionContextTemplate,
            askSelectionTemplate: config.prompts.askSelectionTemplate,
            askConversationTemplate: config.prompts.askConversationTemplate,
            screenshotContextTemplate: config.prompts.screenshotContextTemplate,
            askScreenshotTemplate: config.prompts.askScreenshotTemplate,
            clipboardWriter: { text in try await clipboardWriter.copy(text) },
            focusedInputWriter: { text in
                await focusedInputPreparation()
                // Text typed live during push-to-talk is edited in place with
                // keystrokes; only turns without live text use regular delivery.
                switch await focusedInputReconciliation(text) {
                case .notLive:
                    return try await focusedInputDelivery.deliver(text)
                case .completed:
                    return FocusedInputDeliveryResult.success(method: "live-typed")
                case .paste(let rest):
                    return try await livePasteDelivery.deliver(rest)
                }
            },
            diagnostics: controllerDiagnostics,
            visibleOperatorDiagnostics: true,
            streamingProgress: streamingProgress
        )
        let audioSource = AVFoundationAudioSource(options: AVFoundationAudioSourceOptions(config: config))
        let transcriber: RuntimeTranscriber
        switch config.sttProvider {
        case .soniox:
            transcriber = try SonioxTranscriber(options: SonioxTranscriberOptions(config: config))
        case .elevenlabs:
            transcriber = try ElevenLabsTranscriber(options: ElevenLabsTranscriberOptions(config: config))
        }

        return TranscriptionSessionRuntime(
            audioSource: audioSource,
            transcriber: transcriber,
            protocolController: controller,
            options: TranscriptionSessionRuntimeOptions(
                verbose: config.verbose,
                readyMessage: "[untype] UI session ready.",
                sttProviderLabel: config.sttProvider.rawValue,
                diagnostics: runtimeDiagnostics,
                audioGate: audioGate,
                quickClose: config.quickClose,
                submissionDiagnosticsEnabled: true,
                releaseLatencyLogger: releaseLatencyLogger,
                emit: eventSink,
                saveProtocolSettings: { snapshot in
                    try savePersistedProtocolSettings(snapshot)
                }
            )
        )
    }

    /// One Push-to-Act run: the selected text goes through `operators` (see
    /// `PushToActChoice`), translating in `translationPolicy` (nil: the
    /// configured one); with `operators.alternative` on, `secondAlternative`
    /// picks the second alternative LLM instead of the first. The result is delivered to the focused control,
    /// replacing the selection. Writes a release-latency record with trigger
    /// `push-to-act`. nil: nothing was processed.
    public static func runSelectionHotkey(
        config: ResolvedConfig,
        operators: OperatorState,
        translationPolicy: TranslationPolicy? = nil,
        secondAlternative: Bool = false,
        selectedText: String,
        screenshot: WindowScreenshot? = nil,
        askConversation: AskConversation,
        protocolOutput: TextOutput,
        diagnostics: @escaping @Sendable (_ line: String, _ warning: Bool) -> Void,
        selectionReplacer: (@Sendable (String) async -> FocusedInputDeliveryResult?)? = nil,
        focusedInputPreparation: @escaping @Sendable () async -> Void = {},
        streamingProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProtocolSubmissionSummary? {
        let started = DispatchTime.now().uptimeNanoseconds
        let releaseTimestamp = ISO8601DateFormatter().string(from: Date())
        let protocolConfig = try resolvedProtocolConfig(config.protocolConfig)
        let alternativeLLM = try makeAlternativeLLMClients(config: config, second: secondAlternative)
        let clipboardWriter = MacOSClipboardWriter()
        let focusedInputDelivery = FocusedInputDelivery(forceInProcess: true)
        let releaseLatencyLogger = try makeReleaseLatencyLogger(config.releaseLatencyLogging)
        let controller = VoiceAgentProtocolController(
            mode: protocolConfig.interactionMode,
            renderer: UITranscriptRenderer(emit: { _ in }),
            writer: try makeUIProtocolWriter(protocolConfig: protocolConfig, output: protocolOutput),
            markers: protocolConfig.markers,
            initialOperators: operators,
            translationPolicy: translationPolicy ?? protocolConfig.translationPolicy,
            translationUserPromptTemplate: config.prompts.translationUserPromptTemplate,
            verbose: config.verbose,
            refiner: try LLMRefinerFactory.makeRefiner(config: config.llm),
            translator: try LLMRefinerFactory.makeTranslator(
                config: config.llm,
                systemPrompt: config.prompts.translationSystemPrompt
            ),
            compositeRefineTranslator: try LLMRefinerFactory.makeCompositeRefineTranslator(
                config: config.llm,
                prompts: config.prompts
            ),
            asker: try LLMRefinerFactory.makeAsker(
                config: config.llm,
                systemPrompt: config.prompts.askSystemPrompt
            ),
            alternativeLLM: alternativeLLM,
            askUserPromptTemplate: config.prompts.askUserPromptTemplate,
            askTranslatedUserPromptTemplate: config.prompts.askTranslatedUserPromptTemplate,
            turnContext: SelectionHotkeyPlan.turnContext(selectedText: selectedText, screenshot: screenshot),
            askConversation: askConversation,
            selectionContextTemplate: config.prompts.selectionContextTemplate,
            askSelectionTemplate: config.prompts.askSelectionTemplate,
            askConversationTemplate: config.prompts.askConversationTemplate,
            screenshotContextTemplate: config.prompts.screenshotContextTemplate,
            askScreenshotTemplate: config.prompts.askScreenshotTemplate,
            clipboardWriter: { text in try await clipboardWriter.copy(text) },
            focusedInputWriter: { text in
                // The captured selection first (writes into its element,
                // whatever has the focus); ordinary delivery otherwise.
                if let selectionReplacer, let result = await selectionReplacer(text) {
                    return result
                }
                await focusedInputPreparation()
                return try await focusedInputDelivery.deliver(text)
            },
            diagnostics: ProtocolControllerDiagnostics(write: diagnostics),
            visibleOperatorDiagnostics: true,
            streamingProgress: streamingProgress
        )
        defer { controller.dispose() }
        try controller.startSession()
        let summary = try await controller.submitWithoutDictation()
        try await controller.endSession(reason: "push-to-act", options: EndProtocolSessionOptions(submitPending: false))
        if let releaseLatencyLogger, let summary {
            let record = ReleaseLatencyLogRecord(
                turnId: "push-to-act-\(UUID().uuidString.lowercased())",
                releaseTimestamp: releaseTimestamp,
                trigger: "push-to-act",
                sttProvider: "none",
                quickClose: false,
                textSource: "selection",
                outcome: summary.focusedInput?.ok == true ? "delivered" : "focused_input_failed",
                totalMs: releaseLatencyMilliseconds(from: started),
                durationsMs: ReleaseLatencyDurations(
                    protocolOperatorProcessingMs: summary.operatorProcessingMs,
                    refineMs: summary.refineMs,
                    translateMs: summary.translateMs,
                    askMs: summary.askMs,
                    clipboardMs: summary.clipboardMs,
                    focusedInputMs: summary.focusedInputMs
                ),
                sectionsProcessed: summary.sectionsProcessed,
                focusedInput: summary.focusedInput ?? .notAttempted()
            )
            do {
                try releaseLatencyLogger.append(record)
            } catch {
                diagnostics("[untype] WARNING: failed to write release latency log: \(error.localizedDescription)", true)
            }
        }
        return summary
    }

    private static func resolvedProtocolConfig(_ protocolConfig: ProtocolRuntimeConfig) throws -> ProtocolRuntimeConfig {
        let persisted = try loadPersistedProtocolSettings()
        return applyPersistedProtocolSettings(protocolConfig, persisted: persisted)
    }

    private static func makeProtocolWriter(
        protocolConfig: ProtocolRuntimeConfig,
        stdout: TextOutput
    ) throws -> JsonlProtocolWriter? {
        if let protocolOutput = protocolConfig.protocolOutput {
            return JsonlProtocolWriter(output: try FileTextOutput(path: protocolOutput))
        }
        if protocolConfig.interactionMode == .agentProtocol {
            return JsonlProtocolWriter(output: stdout)
        }
        return nil
    }

    private static func makeUIProtocolWriter(
        protocolConfig: ProtocolRuntimeConfig,
        output: TextOutput
    ) throws -> JsonlProtocolWriter? {
        if let protocolOutput = protocolConfig.protocolOutput {
            return JsonlProtocolWriter(output: try FileTextOutput(path: protocolOutput))
        }
        if protocolConfig.interactionMode == .agentProtocol || protocolConfig.interactionMode == .hybrid {
            return JsonlProtocolWriter(output: output)
        }
        return nil
    }

    private static func makeReleaseLatencyLogger(_ config: ReleaseLatencyLoggingConfig) throws -> ReleaseLatencyLogWriting? {
        guard config.enabled else {
            return nil
        }
        if config.resetOnStart {
            try ReleaseLatencyJsonlLogger.resetOnStartIfNeeded(path: config.path)
        }
        return ReleaseLatencyJsonlLogger(path: config.path)
    }
}

private final class UITranscriptRenderer: TranscriptRendering {
    private let emit: @Sendable (_ event: UITranscriptEvent) -> Void
    private var lastPartialText: String?
    private var disposed = false

    init(emit: @escaping @Sendable (_ event: UITranscriptEvent) -> Void) {
        self.emit = emit
    }

    func partial(_ text: String) {
        guard !disposed else {
            return
        }
        let filtered = uiFilterMarkerTokens(text)
        guard !filtered.isEmpty, filtered != lastPartialText else {
            return
        }
        lastPartialText = filtered
        emit(.partial(filtered))
    }

    func final(_ text: String) {
        guard !disposed else {
            return
        }
        lastPartialText = nil
        let filtered = uiFilterMarkerTokens(text)
        guard !filtered.isEmpty else {
            return
        }
        emit(.final(filtered))
    }

    func turnBoundary() {
        guard !disposed else {
            return
        }
        lastPartialText = nil
        emit(.turnBoundary)
    }

    func refined(_ text: String) {
        guard !disposed else {
            return
        }
        lastPartialText = nil
        let filtered = uiFilterMarkerTokens(text)
        guard !filtered.isEmpty else {
            return
        }
        emit(.processed(filtered))
    }

    func dispose() {
        disposed = true
        lastPartialText = nil
    }
}

private func uiFilterMarkerTokens(_ text: String) -> String {
    text
        .replacingOccurrences(of: "<end>", with: "")
        .replacingOccurrences(of: "<fin>", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
