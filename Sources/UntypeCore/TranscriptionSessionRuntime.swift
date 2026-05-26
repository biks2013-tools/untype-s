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

private enum AudioActivityCategory: Sendable, Equatable {
    case active
    case silent
    case muted
}

public struct TranscriptionSessionRuntimeOptions {
    public let verbose: Bool
    public let readyMessage: String
    public let sttProviderLabel: String
    public let diagnostics: ProtocolControllerDiagnostics
    public let audioGate: RuntimeAudioGate?
    public let finalTranscriptWaitNanoseconds: UInt64
    public let quickClose: Bool
    public let submissionDiagnosticsEnabled: Bool
    public let releaseLatencyLogger: ReleaseLatencyLogWriting?
    public let audioActivityInterval: TimeInterval
    public let audioActivityNow: @Sendable () -> Date
    public let emit: (_ event: TranscriptionSessionEvent) -> Void
    public let saveProtocolSettings: (_ snapshot: ProtocolSettingsSnapshot) throws -> Void

    public init(
        verbose: Bool = false,
        readyMessage: String = "[untype] Ready to listen. Press Control-C to stop the listening tool.",
        sttProviderLabel: String = "STT provider",
        diagnostics: ProtocolControllerDiagnostics = ProtocolControllerDiagnostics(write: { _, _ in }),
        audioGate: RuntimeAudioGate? = nil,
        finalTranscriptWaitNanoseconds: UInt64 = 1_500_000_000,
        quickClose: Bool = false,
        submissionDiagnosticsEnabled: Bool = false,
        releaseLatencyLogger: ReleaseLatencyLogWriting? = nil,
        audioActivityInterval: TimeInterval = 0.25,
        audioActivityNow: @escaping @Sendable () -> Date = Date.init,
        emit: @escaping (_ event: TranscriptionSessionEvent) -> Void = { _ in },
        saveProtocolSettings: @escaping (_ snapshot: ProtocolSettingsSnapshot) throws -> Void = { _ in }
    ) {
        self.verbose = verbose
        self.readyMessage = readyMessage
        self.sttProviderLabel = sttProviderLabel
        self.diagnostics = diagnostics
        self.audioGate = audioGate
        self.finalTranscriptWaitNanoseconds = finalTranscriptWaitNanoseconds
        self.quickClose = quickClose
        self.submissionDiagnosticsEnabled = submissionDiagnosticsEnabled
        self.releaseLatencyLogger = releaseLatencyLogger
        self.audioActivityInterval = audioActivityInterval
        self.audioActivityNow = audioActivityNow
        self.emit = emit
        self.saveProtocolSettings = saveProtocolSettings
    }
}

private struct GatedAudioChunk: Sendable {
    let data: Data
    let mutedByGate: Bool
}

private final class ReleaseLatencyTurn {
    let turnId = UUID().uuidString
    let releaseTimestamp: String
    let trigger: String
    let startedNanoseconds: UInt64
    var textSource = "unknown"
    var durations = ReleaseLatencyDurations()
    var sectionsProcessed = 0
    var focusedInput = ReleaseLatencyFocusedInput.notAttempted()
    var finished = false

    init(trigger: String, marker: ReleaseLatencyReleaseMarker? = nil) {
        self.trigger = trigger
        self.releaseTimestamp = marker?.releaseTimestamp ?? releaseLatencyTimestamp()
        self.startedNanoseconds = marker?.detectedNanoseconds ?? DispatchTime.now().uptimeNanoseconds
        if let marker {
            self.durations.runtimeSchedulingMs = releaseLatencyMilliseconds(from: marker.detectedNanoseconds)
        }
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
    private var suppressLateProviderFinals = false
    private var lastAudioActivityCategory: AudioActivityCategory?
    private var lastAudioActivityEmittedAt = Date.distantPast
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
                guard !self.suppressLateProviderFinals else {
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
                        self.emitAudioActivity(raw: pcm, mutedByGate: gated.mutedByGate)
                        try await self.transcriber.pushAudio(gated.data)
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
        let latencyTurn = beginReleaseLatencyTurn(trigger: "submitPending")
        guard state == .listening, transcriberStarted, !stopping else {
            submissionDiagnostic(
                "[untype] WARNING: push-to-talk release ignored because the session is \(state.rawValue); no transcript was submitted.",
                warning: true
            )
            finishReleaseLatencyTurn(
                latencyTurn,
                outcome: "ignored_release",
                errorCode: "session_not_listening",
                errorMessage: "Push-to-talk release ignored because the session was not listening."
            )
            return
        }
        submissionDiagnostic("[untype] push-to-talk release: requesting provider final text", warning: false)
        do {
            try await finalizePendingUtterance(latencyTurn: latencyTurn)
        } catch {
            finishReleaseLatencyTurn(
                latencyTurn,
                outcome: "failed",
                errorCode: releaseLatencyErrorCode(error),
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    public func toggleOperator(_ key: OperatorKey) async throws {
        try await protocolController.toggleOperator(key)
    }

    public func stop(reason: String, submitPending: Bool = false) async {
        await stop(reason: reason, submitPending: submitPending, releaseMarker: nil)
    }

    public func stop(
        reason: String,
        submitPending: Bool,
        releaseMarker: ReleaseLatencyReleaseMarker?
    ) async {
        guard !stopping, !stopped else {
            return
        }
        if submitPending {
            let latencyTurn = reason == "ui-hotkey-release"
                ? beginReleaseLatencyTurn(trigger: reason, marker: releaseMarker)
                : nil
            if state == .listening, transcriberStarted {
                do {
                    submissionDiagnostic("[untype] push-to-talk release: requesting provider final text", warning: false)
                    try await finalizePendingUtterance(latencyTurn: latencyTurn)
                } catch {
                    finishReleaseLatencyTurn(
                        latencyTurn,
                        outcome: "failed",
                        errorCode: releaseLatencyErrorCode(error),
                        errorMessage: error.localizedDescription
                    )
                    record(error)
                    diagnostic("[untype] WARNING: failed to submit pending utterance: \(error.localizedDescription)", warning: true)
                }
            } else {
                submissionDiagnostic(
                    "[untype] WARNING: push-to-talk release happened before the \(options.sttProviderLabel) stream was ready; no transcript was submitted.",
                    warning: true
                )
                finishReleaseLatencyTurn(
                    latencyTurn,
                    outcome: "no_text",
                    errorCode: "stream_not_ready",
                    errorMessage: "Push-to-talk release happened before the provider stream was ready."
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

    private func finalizePendingUtterance(latencyTurn: ReleaseLatencyTurn?) async throws {
        pendingSubmissionInProgress = true
        defer {
            pendingSubmissionInProgress = false
        }
        if options.quickClose, !protocolController.hasPendingContent {
            suppressLateProviderPartials = true
            suppressLateProviderFinals = true
            if let fallback = latestPartialTranscript {
                submissionDiagnostic(
                    "[untype] push-to-talk release: Quick Close submitting latest partial transcript",
                    warning: false
                )
                latencyTurn?.textSource = "quick_close_partial"
                try await protocolController.final(fallback)
                try await submitPendingTranscript(latencyTurn: latencyTurn)
            } else {
                diagnostic(
                    "[untype] WARNING: push-to-talk release did not have finalized or partial transcript text available for Quick Close; no text was submitted.",
                    warning: true
                )
                latencyTurn?.textSource = "no_submitted_text"
                finishReleaseLatencyTurn(
                    latencyTurn,
                    outcome: "no_text",
                    errorCode: "quick_close_no_text",
                    errorMessage: "Quick Close release had no finalized or partial transcript text."
                )
            }
            return
        }
        let shouldWaitForFinal = !protocolController.hasPendingContent
        let finalGeneration = shouldWaitForFinal ? await finalTranscriptWaiter.currentGeneration() : nil
        let commitStarted = DispatchTime.now().uptimeNanoseconds
        try await transcriber.commit()
        latencyTurn?.durations.providerCommitRequestMs = releaseLatencyMilliseconds(from: commitStarted)
        var receivedFinal = false
        if let finalGeneration {
            let waitStarted = DispatchTime.now().uptimeNanoseconds
            receivedFinal = await finalTranscriptWaiter.waitForNext(
                after: finalGeneration,
                timeoutNanoseconds: options.finalTranscriptWaitNanoseconds
            )
            latencyTurn?.durations.providerFinalWaitMs = releaseLatencyMilliseconds(from: waitStarted)
        }
        if !protocolController.hasPendingContent {
            if shouldWaitForFinal && !receivedFinal {
                if let fallback = latestPartialTranscript {
                    diagnostic(
                        "[untype] WARNING: push-to-talk release did not receive finalized transcript from \(options.sttProviderLabel) before timeout; submitting latest partial transcript.",
                        warning: true
                    )
                    suppressLateProviderPartials = true
                    suppressLateProviderFinals = true
                    latencyTurn?.textSource = "timeout_fallback_partial"
                    try await protocolController.final(fallback)
                } else {
                    diagnostic(
                        "[untype] WARNING: push-to-talk release did not receive finalized transcript from \(options.sttProviderLabel) before timeout; no text was submitted.",
                        warning: true
                    )
                    latencyTurn?.textSource = "no_submitted_text"
                    finishReleaseLatencyTurn(
                        latencyTurn,
                        outcome: "no_text",
                        errorCode: "provider_final_timeout_no_text",
                        errorMessage: "Provider final text did not arrive before timeout and no partial transcript was available."
                    )
                    return
                }
            } else {
                latencyTurn?.textSource = "no_submitted_text"
                finishReleaseLatencyTurn(
                    latencyTurn,
                    outcome: "no_text",
                    errorCode: "no_pending_content",
                    errorMessage: "Provider finalization completed without pending protocol content."
                )
                return
            }
        } else if shouldWaitForFinal {
            submissionDiagnostic("[untype] push-to-talk release: provider final text received", warning: false)
            latencyTurn?.textSource = "provider_final_text"
        } else {
            submissionDiagnostic("[untype] push-to-talk release: provider final text already available", warning: false)
            latencyTurn?.textSource = "provider_final_already_available"
        }
        try await submitPendingTranscript(latencyTurn: latencyTurn)
    }

    private func submitPendingTranscript(latencyTurn: ReleaseLatencyTurn?) async throws {
        submissionDiagnostic("[untype] push-to-talk release: submitting transcript for processing", warning: false)
        let submissionStarted = DispatchTime.now().uptimeNanoseconds
        let summary = try await protocolController.submitPending()
        latencyTurn?.durations.protocolSubmissionMs = releaseLatencyMilliseconds(from: submissionStarted)
        latencyTurn?.durations.protocolOperatorProcessingMs = summary.operatorProcessingMs
        latencyTurn?.durations.refineMs = summary.refineMs
        latencyTurn?.durations.translateMs = summary.translateMs
        latencyTurn?.durations.clipboardMs = summary.clipboardMs
        latencyTurn?.durations.focusedInputMs = summary.focusedInputMs
        latencyTurn?.sectionsProcessed = summary.sectionsProcessed
        latencyTurn?.focusedInput = summary.focusedInput ?? .notAttempted()
        latestPartialTranscript = nil
        suppressLateProviderPartials = true
        submissionDiagnostic("[untype] push-to-talk release: processing completed", warning: false)
        finishReleaseLatencyTurn(
            latencyTurn,
            outcome: releaseLatencyOutcome(for: summary)
        )
    }

    private func beginReleaseLatencyTurn(
        trigger: String,
        marker: ReleaseLatencyReleaseMarker? = nil
    ) -> ReleaseLatencyTurn? {
        guard options.releaseLatencyLogger != nil else {
            return nil
        }
        return ReleaseLatencyTurn(trigger: trigger, marker: marker)
    }

    private func finishReleaseLatencyTurn(
        _ latencyTurn: ReleaseLatencyTurn?,
        outcome: String,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        guard let latencyTurn, !latencyTurn.finished, let logger = options.releaseLatencyLogger else {
            return
        }
        latencyTurn.finished = true
        let record = ReleaseLatencyLogRecord(
            turnId: latencyTurn.turnId,
            releaseTimestamp: latencyTurn.releaseTimestamp,
            trigger: latencyTurn.trigger,
            sttProvider: options.sttProviderLabel,
            quickClose: options.quickClose,
            textSource: latencyTurn.textSource,
            outcome: outcome,
            totalMs: releaseLatencyMilliseconds(from: latencyTurn.startedNanoseconds),
            durationsMs: latencyTurn.durations,
            sectionsProcessed: latencyTurn.sectionsProcessed,
            focusedInput: latencyTurn.focusedInput,
            errorCode: errorCode,
            errorMessage: errorMessage
        )
        do {
            try logger.append(record)
        } catch {
            diagnostic("[untype] WARNING: failed to write release latency log: \(error.localizedDescription)", warning: true)
        }
    }

    private func releaseLatencyOutcome(for summary: ProtocolSubmissionSummary) -> String {
        guard let focusedInput = summary.focusedInput, focusedInput.attempted else {
            return "processed_without_focused_input"
        }
        if focusedInput.ok == true {
            return "delivered_to_focused_input"
        }
        return "focused_input_failed"
    }

    private func releaseLatencyErrorCode(_ error: Error) -> String {
        if let error = error as? FocusedInputDeliveryError {
            return error.code ?? "focused_input_failed"
        }
        if let error = error as? UntypeError {
            return error.code
        }
        return "runtime_error"
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

    private func audioChunkForGate(_ pcm: Data) -> GatedAudioChunk {
        guard let audioGate = options.audioGate, !audioGate.isOpen() else {
            return GatedAudioChunk(data: pcm, mutedByGate: false)
        }
        return GatedAudioChunk(data: Data(repeating: 0, count: pcm.count), mutedByGate: true)
    }

    private func emitAudioActivity(raw: Data, mutedByGate: Bool) {
        let peak = Self.peakAmplitude(raw)
        let category = Self.audioActivityCategory(peak: peak, mutedByGate: mutedByGate)
        let now = options.audioActivityNow()
        guard shouldEmitAudioActivity(category: category, now: now) else {
            return
        }
        lastAudioActivityCategory = category
        lastAudioActivityEmittedAt = now
        options.emit(.audioActivity(AudioActivitySnapshot(
            peak: peak,
            byteCount: raw.count,
            mutedByGate: mutedByGate
        )))
    }

    private func shouldEmitAudioActivity(category: AudioActivityCategory, now: Date) -> Bool {
        guard options.audioActivityInterval > 0 else {
            return true
        }
        guard lastAudioActivityCategory == category else {
            return true
        }
        return now.timeIntervalSince(lastAudioActivityEmittedAt) >= options.audioActivityInterval
    }

    private static func audioActivityCategory(peak: Double, mutedByGate: Bool) -> AudioActivityCategory {
        if mutedByGate {
            return .muted
        }
        if peak <= 0.01 {
            return .silent
        }
        return .active
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
