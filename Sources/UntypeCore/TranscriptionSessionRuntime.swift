import Foundation

public struct AudioSourceEventHandlers {
    public let audio: (_ pcm: Data) async -> Void
    public let error: (_ error: Error) async -> Void
    public let end: () async -> Void

    public init(
        audio: @escaping (_ pcm: Data) async -> Void,
        error: @escaping (_ error: Error) async -> Void,
        end: @escaping () async -> Void
    ) {
        self.audio = audio
        self.error = error
        self.end = end
    }
}

private actor FinalTranscriptWaiter {
    private var generation = 0
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func currentGeneration() -> Int {
        generation
    }

    func noteFinal() {
        generation += 1
        let continuations = Array(waiters.values)
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitForNext(after previousGeneration: Int, timeoutNanoseconds: UInt64) async -> Bool {
        if generation > previousGeneration {
            return true
        }
        guard timeoutNanoseconds > 0 else {
            return false
        }

        let id = UUID()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    return false
                }
                await self.wait(id: id, after: previousGeneration)
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let result = await group.next() ?? false
            removeWaiter(id)
            group.cancelAll()
            return result
        }
    }

    private func wait(id: UUID, after previousGeneration: Int) async {
        if generation > previousGeneration {
            return
        }
        await withCheckedContinuation { continuation in
            waiters[id] = continuation
        }
    }

    private func removeWaiter(_ id: UUID) {
        if let continuation = waiters.removeValue(forKey: id) {
            continuation.resume()
        }
    }
}

public protocol RuntimeAudioSource: AnyObject {
    func start(handlers: AudioSourceEventHandlers) async throws
    func stop() async throws
}

public struct TranscriberEventHandlers {
    public let partial: (_ text: String) -> Void
    public let final: (_ text: String) async -> Void
    public let error: (_ error: Error) async -> Void

    public init(
        partial: @escaping (_ text: String) -> Void,
        final: @escaping (_ text: String) async -> Void,
        error: @escaping (_ error: Error) async -> Void
    ) {
        self.partial = partial
        self.final = final
        self.error = error
    }
}

public protocol RuntimeTranscriber: AnyObject {
    func setHandlers(_ handlers: TranscriberEventHandlers)
    func start() async throws
    func pushAudio(_ pcm: Data) async throws
    func commit() async throws
    func stop() async throws
}

public protocol RuntimeAudioGate: AnyObject, Sendable {
    func isOpen() -> Bool
}

public enum UITranscriptEvent: Sendable, Equatable {
    case partial(String)
    case final(String)
    case turnBoundary
    case processed(String)
}

public enum TranscriptionSessionState: String, Sendable, Equatable {
    case initialized
    case starting
    case listening
    case stopping
    case stopped
}

public enum TranscriptionSessionEvent: Sendable, Equatable {
    case stateChanged(TranscriptionSessionState, reason: String?)
    case ready(message: String)
    case diagnostic(message: String, warning: Bool)
    case audioActivity(AudioActivitySnapshot)
}

public struct AudioActivitySnapshot: Sendable, Equatable {
    public let peak: Double
    public let byteCount: Int
    public let mutedByGate: Bool

    public init(peak: Double, byteCount: Int, mutedByGate: Bool) {
        self.peak = peak
        self.byteCount = byteCount
        self.mutedByGate = mutedByGate
    }
}

public struct TranscriptionSessionRuntimeOptions {
    public let verbose: Bool
    public let readyMessage: String
    public let sttProviderLabel: String
    public let diagnostics: ProtocolControllerDiagnostics
    public let audioGate: RuntimeAudioGate?
    public let finalTranscriptWaitNanoseconds: UInt64
    public let submissionDiagnosticsEnabled: Bool
    public let emit: (_ event: TranscriptionSessionEvent) -> Void
    public let saveProtocolSettings: (_ snapshot: ProtocolSettingsSnapshot) throws -> Void

    public init(
        verbose: Bool = false,
        readyMessage: String = "[untype] Ready to listen. Press Control-C to stop the listening tool.",
        sttProviderLabel: String = "STT provider",
        diagnostics: ProtocolControllerDiagnostics = ProtocolControllerDiagnostics(write: { _, _ in }),
        audioGate: RuntimeAudioGate? = nil,
        finalTranscriptWaitNanoseconds: UInt64 = 1_500_000_000,
        submissionDiagnosticsEnabled: Bool = false,
        emit: @escaping (_ event: TranscriptionSessionEvent) -> Void = { _ in },
        saveProtocolSettings: @escaping (_ snapshot: ProtocolSettingsSnapshot) throws -> Void = { _ in }
    ) {
        self.verbose = verbose
        self.readyMessage = readyMessage
        self.sttProviderLabel = sttProviderLabel
        self.diagnostics = diagnostics
        self.audioGate = audioGate
        self.finalTranscriptWaitNanoseconds = finalTranscriptWaitNanoseconds
        self.submissionDiagnosticsEnabled = submissionDiagnosticsEnabled
        self.emit = emit
        self.saveProtocolSettings = saveProtocolSettings
    }
}

public final class TranscriptionSessionRuntime {
    private let audioSource: RuntimeAudioSource
    private let transcriber: RuntimeTranscriber
    private let protocolController: VoiceAgentProtocolController
    private let options: TranscriptionSessionRuntimeOptions

    private var state: TranscriptionSessionState = .initialized
    private var transcriberStarted = false
    private var audioStarted = false
    private var stopping = false
    private var stopped = false
    private var recordedError: Error?
    private var partialCommandCommitInFlight = false
    private var lastPartialCommandCommitSignature: String?
    private var latestPartialTranscript: String?
    private var pendingSubmissionInProgress = false
    private var suppressLateProviderPartials = false
    private let finalTranscriptWaiter = FinalTranscriptWaiter()

    public init(
        audioSource: RuntimeAudioSource,
        transcriber: RuntimeTranscriber,
        protocolController: VoiceAgentProtocolController,
        options: TranscriptionSessionRuntimeOptions = TranscriptionSessionRuntimeOptions()
    ) {
        self.audioSource = audioSource
        self.transcriber = transcriber
        self.protocolController = protocolController
        self.options = options
    }

    public func start() async throws {
        guard state == .initialized else {
            return
        }
        transition(to: .starting, reason: nil)

        transcriber.setHandlers(TranscriberEventHandlers(
            partial: { [weak self] text in
                guard let self else {
                    return
                }
                guard self.shouldAcceptProviderPartial else {
                    return
                }
                self.rememberPartialTranscript(text)
                self.protocolController.partial(text)
                self.commitIfPartialContainsActionableCommand(text)
            },
            final: { [weak self] text in
                guard let self else {
                    return
                }
                do {
                    try await self.protocolController.final(text)
                    self.latestPartialTranscript = nil
                    if self.pendingSubmissionInProgress {
                        self.suppressLateProviderPartials = true
                    }
                    await self.finalTranscriptWaiter.noteFinal()
                } catch {
                    self.record(error)
                    await self.stop(reason: "protocol-error")
                }
            },
            error: { [weak self] error in
                guard let self else {
                    return
                }
                self.record(error)
                await self.stop(reason: "transcriber-error")
            }
        ))

        do {
            try protocolController.startSession()
            if startupWasStopped {
                return
            }
            diagnostic("[untype] starting microphone capture", warning: false)
            try await audioSource.start(handlers: AudioSourceEventHandlers(
                audio: { [weak self] pcm in
                    guard let self else {
                        return
                    }
                    do {
                        let gated = self.audioChunkForGate(pcm)
                        self.emitAudioActivity(raw: pcm, gated: gated)
                        try await self.transcriber.pushAudio(gated)
                    } catch {
                        self.record(error)
                        await self.stop(reason: "audio-push-error")
                    }
                },
                error: { [weak self] error in
                    guard let self else {
                        return
                    }
                    self.record(error)
                    await self.stop(reason: "mic-error")
                },
                end: { [weak self] in
                    guard let self else {
                        return
                    }
                    await self.stop(reason: "mic-end")
                }
            ))
            audioStarted = true
            if startupWasStopped {
                await stop(reason: "startup-cancelled")
                return
            }
            diagnostic("[untype] microphone capture started", warning: false)
            diagnostic("[untype] connecting \(options.sttProviderLabel) realtime stream", warning: false)
            try await transcriber.start()
            transcriberStarted = true
            if startupWasStopped {
                await stop(reason: "startup-cancelled")
                return
            }
            diagnostic("[untype] \(options.sttProviderLabel) realtime stream connected", warning: false)
            transition(to: .listening, reason: nil)
            options.emit(.ready(message: options.readyMessage))
            if options.verbose {
                diagnostic("[untype] session runtime started", warning: false)
            }
        } catch {
            record(error)
            await stop(reason: "startup-error")
            throw error
        }
    }

    public func submitPending() async throws {
        guard state == .listening, transcriberStarted, !stopping else {
            submissionDiagnostic(
                "[untype] WARNING: push-to-talk release ignored because the session is \(state.rawValue); no transcript was submitted.",
                warning: true
            )
            return
        }
        submissionDiagnostic("[untype] push-to-talk release: requesting provider final text", warning: false)
        try await finalizePendingUtterance()
    }

    public func toggleOperator(_ key: OperatorKey) async throws {
        try await protocolController.toggleOperator(key)
    }

    public func stop(reason: String, submitPending: Bool = false) async {
        guard !stopping, !stopped else {
            return
        }
        if submitPending {
            if state == .listening, transcriberStarted {
                do {
                    submissionDiagnostic("[untype] push-to-talk release: requesting provider final text", warning: false)
                    try await finalizePendingUtterance()
                } catch {
                    record(error)
                    diagnostic("[untype] WARNING: failed to submit pending utterance: \(error.localizedDescription)", warning: true)
                }
            } else {
                submissionDiagnostic(
                    "[untype] WARNING: push-to-talk release happened before the \(options.sttProviderLabel) stream was ready; no transcript was submitted.",
                    warning: true
                )
            }
        }

        stopping = true
        transition(to: .stopping, reason: reason)
        if options.verbose {
            diagnostic("[untype] shutting down: \(reason)", warning: false)
        }

        if audioStarted || state == .starting {
            do {
                try await audioSource.stop()
            } catch {
                record(error)
                if options.verbose {
                    diagnostic("[untype] mic.stop() error: \(error.localizedDescription)", warning: true)
                }
            }
        }

        if transcriberStarted || state == .starting {
            do {
                try await transcriber.stop()
            } catch {
                record(error)
                if options.verbose {
                    diagnostic("[untype] transcriber.stop() error: \(error.localizedDescription)", warning: true)
                }
            }
        }

        do {
            try await protocolController.endSession(
                reason: reason,
                options: EndProtocolSessionOptions(submitPending: false)
            )
            try options.saveProtocolSettings(protocolController.settingsSnapshot())
        } catch {
            record(error)
            diagnostic("[untype] WARNING: failed to finish protocol session: \(error.localizedDescription)", warning: true)
        }

        protocolController.dispose()
        stopped = true
        transition(to: .stopped, reason: reason)
    }

    public func recordedFailure() -> Error? {
        recordedError
    }

    private func record(_ error: Error) {
        if recordedError == nil {
            recordedError = error
        }
    }

    private func transition(to next: TranscriptionSessionState, reason: String?) {
        state = next
        options.emit(.stateChanged(next, reason: reason))
    }

    private var startupWasStopped: Bool {
        stopping || stopped || Task.isCancelled
    }

    private func diagnostic(_ message: String, warning: Bool) {
        options.diagnostics.write(message, warning)
        options.emit(.diagnostic(message: message, warning: warning))
    }

    private func submissionDiagnostic(_ message: String, warning: Bool) {
        guard warning || options.verbose || options.submissionDiagnosticsEnabled else {
            return
        }
        diagnostic(message, warning: warning)
    }

    private func finalizePendingUtterance() async throws {
        pendingSubmissionInProgress = true
        defer {
            pendingSubmissionInProgress = false
        }
        let shouldWaitForFinal = !protocolController.hasPendingContent
        let finalGeneration = shouldWaitForFinal ? await finalTranscriptWaiter.currentGeneration() : nil
        try await transcriber.commit()
        var receivedFinal = false
        if let finalGeneration {
            receivedFinal = await finalTranscriptWaiter.waitForNext(
                after: finalGeneration,
                timeoutNanoseconds: options.finalTranscriptWaitNanoseconds
            )
        }
        if !protocolController.hasPendingContent {
            if shouldWaitForFinal && !receivedFinal {
                if let fallback = latestPartialTranscript {
                    diagnostic(
                        "[untype] WARNING: push-to-talk release did not receive finalized transcript from \(options.sttProviderLabel) before timeout; submitting latest partial transcript.",
                        warning: true
                    )
                    suppressLateProviderPartials = true
                    try await protocolController.final(fallback)
                } else {
                    diagnostic(
                        "[untype] WARNING: push-to-talk release did not receive finalized transcript from \(options.sttProviderLabel) before timeout; no text was submitted.",
                        warning: true
                    )
                    return
                }
            } else {
                return
            }
        }
        submissionDiagnostic("[untype] push-to-talk release: submitting transcript for processing", warning: false)
        try await protocolController.submitPending()
        latestPartialTranscript = nil
        suppressLateProviderPartials = true
        submissionDiagnostic("[untype] push-to-talk release: processing completed", warning: false)
    }

    private var shouldAcceptProviderPartial: Bool {
        state == .listening && !stopping && !stopped && !suppressLateProviderPartials
    }

    private func rememberPartialTranscript(_ text: String) {
        let normalized = normalizePayloadWhitespace(
            text
                .replacingOccurrences(of: "<end>", with: "")
                .replacingOccurrences(of: "<fin>", with: "")
        )
        guard !normalized.isEmpty else {
            return
        }
        latestPartialTranscript = normalized
    }

    private func commitIfPartialContainsActionableCommand(_ text: String) {
        guard state == .listening,
              transcriberStarted,
              !stopping,
              protocolController.partialContainsActionableCommand(text)
        else {
            return
        }
        let signature = normalizePayloadWhitespace(text)
        guard signature != lastPartialCommandCommitSignature,
              !partialCommandCommitInFlight
        else {
            return
        }
        partialCommandCommitInFlight = true
        lastPartialCommandCommitSignature = signature
        if options.verbose {
            diagnostic("[untype] protocol command detected in partial transcript; committing provider output", warning: false)
        }
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.transcriber.commit()
            } catch {
                self.record(error)
                await self.stop(reason: "partial-command-commit-error")
            }
            self.partialCommandCommitInFlight = false
        }
    }

    private func audioChunkForGate(_ pcm: Data) -> Data {
        guard let audioGate = options.audioGate, !audioGate.isOpen() else {
            return pcm
        }
        return Data(repeating: 0, count: pcm.count)
    }

    private func emitAudioActivity(raw: Data, gated: Data) {
        options.emit(.audioActivity(AudioActivitySnapshot(
            peak: Self.peakAmplitude(raw),
            byteCount: raw.count,
            mutedByGate: raw.count == gated.count && raw != gated
        )))
    }

    private static func peakAmplitude(_ pcm: Data) -> Double {
        guard pcm.count >= 2 else {
            return 0
        }
        var peak = 0
        var index = pcm.startIndex
        while index < pcm.endIndex {
            let next = pcm.index(after: index)
            guard next < pcm.endIndex else {
                break
            }
            let sample = Int16(littleEndian: Int16(bitPattern: UInt16(pcm[index]) | (UInt16(pcm[next]) << 8)))
            peak = max(peak, abs(Int(sample)))
            index = pcm.index(index, offsetBy: 2)
        }
        return min(1, Double(peak) / 32768.0)
    }
}
