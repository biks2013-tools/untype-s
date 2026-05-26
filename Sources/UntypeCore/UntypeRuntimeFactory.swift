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
        let translator = try LLMRefinerFactory.makeTranslator(config: config.llm)
        let clipboardWriter = MacOSClipboardWriter()
        let focusedInputDelivery = FocusedInputDelivery()
        let controller = VoiceAgentProtocolController(
            mode: protocolConfig.interactionMode,
            renderer: renderer,
            writer: protocolWriter,
            markers: protocolConfig.markers,
            initialOperators: protocolConfig.initialOperators,
            translationPolicy: protocolConfig.translationPolicy,
            verbose: config.verbose,
            refiner: refiner,
            translator: translator,
            clipboardWriter: { text in try await clipboardWriter.copy(text) },
            inputWriter: { text in try await focusedInputDelivery.send(text) },
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
        eventSink: @escaping @Sendable (_ event: TranscriptionSessionEvent) -> Void
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
        let translator = try LLMRefinerFactory.makeTranslator(config: config.llm)
        let clipboardWriter = MacOSClipboardWriter()
        let focusedInputDelivery = FocusedInputDelivery()
        let controller = VoiceAgentProtocolController(
            mode: protocolConfig.interactionMode,
            renderer: renderer,
            writer: protocolWriter,
            markers: protocolConfig.markers,
            initialOperators: protocolConfig.initialOperators,
            translationPolicy: protocolConfig.translationPolicy,
            verbose: config.verbose,
            refiner: refiner,
            translator: translator,
            clipboardWriter: { text in try await clipboardWriter.copy(text) },
            inputWriter: { text in try await focusedInputDelivery.send(text) },
            diagnostics: controllerDiagnostics,
            visibleOperatorDiagnostics: true
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
                emit: eventSink,
                saveProtocolSettings: { snapshot in
                    try savePersistedProtocolSettings(snapshot)
                }
            )
        )
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
