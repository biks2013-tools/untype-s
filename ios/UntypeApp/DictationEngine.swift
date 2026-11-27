import AVFoundation
import Foundation
import os
import SwiftUI
import UntypeCore

/// One dictation at a time: the microphone goes to Soniox, the words appear
/// as they are heard, and at the end Refine / Translate rewrite them.
@MainActor
final class DictationEngine: ObservableObject {
    nonisolated static let sampleRate = 16_000
    /// Counts and lengths only: never the words.
    nonisolated static let log = Logger(subsystem: "com.biks2013.untype", category: "dictation")

    enum Phase: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case processing(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// The text on screen; the user can edit it between dictations.
    @Published var text = ""
    @Published var problem: String?
    /// The text before the last Refine / Translate, to go back to.
    @Published private(set) var beforeProcessing: String?

    private var audio: AVFoundationAudioSource?
    private var transcriber: SonioxTranscriber?
    private var events: Task<Void, Never>?
    private var pump: AudioPump?
    /// The text that was there when the dictation started.
    private var base = ""
    /// Sentences of this dictation that are finished.
    private var finished = ""
    /// The sentence being spoken.
    private var current = ""
    private var corrector = DictionaryCorrector(.empty)
    private var partials = 0

    var isBusy: Bool {
        phase != .idle
    }

    func toggle(settings: AppSettings) {
        switch phase {
        case .idle:
            Task { await start(settings: settings) }
        case .listening:
            Task { await finish(settings: settings) }
        case .starting, .finishing, .processing:
            break
        }
    }

    private enum Heard {
        case partial(String)
        case final(String)
        case failed(String)
    }

    private func start(settings: AppSettings) async {
        problem = nil
        beforeProcessing = nil
        phase = .starting
        do {
            let options = try settings.sonioxOptions()
            corrector = DictionaryCorrector(settings.dictionary)
            base = text
            finished = ""
            current = ""
            partials = 0

            // During a call iOS gives the microphone to the call alone.
            if PhoneCall.isActive {
                Self.log.info("dictation not started: a call is in progress")
                throw AppError(PhoneCall.dictationBlocked)
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let transcriber = try SonioxTranscriber(options: options)
            let (stream, continuation) = AsyncStream<Heard>.makeStream()
            transcriber.setHandlers(TranscriberEventHandlers(
                partial: { continuation.yield(.partial($0)) },
                final: { continuation.yield(.final($0)) },
                error: { continuation.yield(.failed($0.localizedDescription)) }
            ))
            events = Task { [weak self] in
                for await event in stream {
                    self?.handle(event)
                }
            }
            self.transcriber = transcriber

            // The microphone starts first, so nothing said while Soniox
            // connects is lost; the audio waits in the pump.
            let pump = AudioPump(transcriber: transcriber) { message in
                continuation.yield(.failed(message))
            }
            self.pump = pump
            let audio = AVFoundationAudioSource(options: AVFoundationAudioSourceOptions(sampleRate: Self.sampleRate))
            self.audio = audio
            try await audio.start(handlers: AudioSourceEventHandlers(
                audio: { pcm in await pump.push(pcm) },
                error: { error in continuation.yield(.failed(error.localizedDescription)) },
                end: {}
            ))
            phase = .listening
            Self.log.info("microphone started at \(session.sampleRate, format: .fixed(precision: 0)) Hz, input: \(session.currentRoute.inputs.first?.portType.rawValue ?? "none", privacy: .public)")
            try await transcriber.start()
            await pump.connected()
            Self.log.info("soniox connected")
        } catch {
            Self.log.error("dictation could not start: \(error.localizedDescription, privacy: .public)")
            await tearDown()
            fail(PhoneCall.isActive ? PhoneCall.dictationBlocked : error.localizedDescription)
        }
    }

    private func handle(_ event: Heard) {
        switch event {
        case .partial(let heard):
            partials += 1
            current = corrector.apply(heard)
            render()
        case .final(let heard):
            Self.log.info("final text of \(heard.count) characters")
            finished = Self.joined(finished, corrector.apply(heard))
            current = ""
            render()
        case .failed(let message):
            guard phase == .listening || phase == .starting else {
                return
            }
            Task {
                await tearDown()
                fail(message)
            }
        }
    }

    private func render() {
        text = Self.joined(base, Self.joined(finished, current))
    }

    private static func joined(_ first: String, _ second: String) -> String {
        let second = second.trimmingCharacters(in: .whitespaces)
        guard !second.isEmpty else {
            return first
        }
        guard let last = first.last else {
            return second
        }
        return last.isWhitespace ? first + second : first + " " + second
    }

    private func finish(settings: AppSettings) async {
        phase = .finishing
        try? await audio?.stop()
        audio = nil
        if let pump {
            let sent = await pump.summary()
            Self.log.info("audio sent: \(sent.bytes) bytes, loudest sample \(sent.peak) of 32767; \(self.partials) text updates")
        }
        // Asks Soniox for the last words and waits for them.
        try? await transcriber?.commit()
        try? await Task.sleep(nanoseconds: 400_000_000)
        try? await transcriber?.stop()
        try? await Task.sleep(nanoseconds: 150_000_000)
        await tearDown()

        // Words still shown as being spoken are kept as they are.
        finished = Self.joined(finished, current)
        current = ""
        render()

        let dictated = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dictated.isEmpty, settings.refine || settings.translate else {
            phase = .idle
            return
        }
        await process(dictated, settings: settings)
    }

    private func process(_ input: String, settings: AppSettings) async {
        let refine = settings.refine
        let translate = settings.translate
        let target = settings.target.rawValue
        phase = .processing(translate ? (refine ? "Refining and translating…" : "Translating…") : "Refining…")
        do {
            let result: String
            if refine, translate {
                let config = try settings.modelConfig(systemPrompt: UntypePromptDefaults.compositeSystemPrompt)
                guard let client = try LLMRefinerFactory.makeCompositeRefineTranslator(config: config, prompts: .defaultValue) else {
                    throw AppError("The model client could not be created.")
                }
                defer { client.dispose() }
                result = try await client.refineAndTranslate(
                    CompositeRefineTranslateRequest(rawText: input, targetLanguageName: target)
                ).translatedText
            } else if translate {
                let config = try settings.modelConfig(systemPrompt: UntypePromptDefaults.translationSystemPrompt)
                guard let client = try LLMRefinerFactory.makeTranslator(config: config) else {
                    throw AppError("The model client could not be created.")
                }
                defer { client.dispose() }
                let prompt = UntypePromptDefaults.translationUserPromptTemplate
                    .replacingOccurrences(of: "{target_language}", with: target)
                    .replacingOccurrences(of: "{text}", with: input)
                result = try await client.refine(prompt)
            } else {
                let config = try settings.modelConfig(systemPrompt: UntypePromptDefaults.refinementSystemPrompt)
                guard let client = try LLMRefinerFactory.makeRefiner(config: config) else {
                    throw AppError("The model client could not be created.")
                }
                defer { client.dispose() }
                result = try await client.refine(input)
            }
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                throw AppError("The model returned no text. Your text is unchanged.")
            }
            beforeProcessing = text
            text = cleaned
            phase = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Puts back the text as it was before Refine / Translate.
    func undoProcessing() {
        guard let beforeProcessing else {
            return
        }
        text = beforeProcessing
        self.beforeProcessing = nil
    }

    func clear() {
        text = ""
        beforeProcessing = nil
        problem = nil
    }

    private func fail(_ message: String) {
        problem = message
        phase = .idle
    }

    private func tearDown() async {
        try? await audio?.stop()
        audio = nil
        try? await transcriber?.stop()
        transcriber = nil
        pump = nil
        events?.cancel()
        events = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Carries the microphone's audio to Soniox in order; what is captured
/// before the connection is ready waits here.
private actor AudioPump {
    private let transcriber: SonioxTranscriber
    private let onFailure: @Sendable (String) -> Void
    private var waiting: [Data] = []
    private var isConnected = false
    private var failed = false
    private var bytes = 0
    private var peak = 0

    init(transcriber: SonioxTranscriber, onFailure: @escaping @Sendable (String) -> Void) {
        self.transcriber = transcriber
        self.onFailure = onFailure
    }

    func push(_ pcm: Data) async {
        guard isConnected else {
            waiting.append(pcm)
            return
        }
        await send(pcm)
    }

    func connected() async {
        // What arrives while the queue is being sent joins the queue, so
        // the audio stays in order.
        while !waiting.isEmpty {
            let queued = waiting
            waiting = []
            for pcm in queued {
                await send(pcm)
            }
        }
        isConnected = true
    }

    /// How much audio was sent and how loud it got.
    func summary() -> (bytes: Int, peak: Int) {
        (bytes, peak)
    }

    private func send(_ pcm: Data) async {
        guard !failed else {
            return
        }
        bytes += pcm.count
        pcm.withUnsafeBytes { raw in
            for sample in raw.bindMemory(to: Int16.self) {
                peak = max(peak, abs(Int(sample)))
            }
        }
        do {
            try await transcriber.pushAudio(pcm)
        } catch {
            failed = true
            onFailure(error.localizedDescription)
        }
    }
}
