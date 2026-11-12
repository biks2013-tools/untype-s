@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public enum MeetingError: LocalizedError {
    case screenRecordingPermission
    case requiresSoniox(String)
    case capture(String)
    case soniox(String)

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermission:
            return "untype needs Screen & System Audio Recording permission to hear the call. Allow it in System Settings → Privacy & Security → Screen & System Audio Recording, then start the meeting again."
        case .requiresSoniox(let provider):
            return "Meeting recording uses Soniox, but the speech provider is \(provider). Set the speech provider to Soniox (with SONIOX_API_KEY) in Settings."
        case .capture(let message):
            return "Meeting audio capture failed: \(message)"
        case .soniox(let message):
            return "Meeting transcription failed: \(message)"
        }
    }
}

/// Why a meeting recording ended.
public enum MeetingStopReason: Sendable, Equatable {
    case user
    case silence(minutes: Int)
    case failure(String)
}

/// Settings of one meeting recording.
public struct MeetingRecordingOptions: Sendable {
    public let apiKey: String
    public let model: String
    public let endpoint: URL
    public let folderRoot: URL
    public let silenceMinutes: Int
    public let language: MeetingTranscriptLanguage
    public let llm: LLMConfig

    public init(apiKey: String, model: String, endpoint: URL, folderRoot: URL, silenceMinutes: Int, language: MeetingTranscriptLanguage, llm: LLMConfig) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.folderRoot = folderRoot
        self.silenceMinutes = silenceMinutes
        self.language = language
        self.llm = llm
    }

    /// Soniox key, model and endpoint from untype's configuration, plus the
    /// meeting settings.
    public init(config: ResolvedConfig, folderRoot: URL, silenceMinutes: Int, language: MeetingTranscriptLanguage) throws {
        guard config.sttProvider == .soniox else {
            throw MeetingError.requiresSoniox(config.sttProvider.rawValue)
        }
        guard let endpoint = URL(string: config.endpoint), endpoint.scheme == "wss" || endpoint.scheme == "ws" else {
            throw MeetingError.soniox("The Soniox endpoint must be a ws:// or wss:// URL. Got: '\(config.endpoint)'.")
        }
        self.init(
            apiKey: config.apiKey,
            model: config.model,
            endpoint: endpoint,
            folderRoot: folderRoot,
            silenceMinutes: silenceMinutes,
            language: language,
            llm: config.llm
        )
    }
}

/// Records a meeting: the microphone ("You") and the call's sound (system
/// audio of every other app, speakers told apart by Soniox) go to two Soniox
/// streams; segments are written live to `transcript.original.txt` in the
/// meeting folder, and at the end the transcript is ordered, translated to
/// English when asked, and saved as `transcript.txt`, `transcript.original.txt`
/// and `transcript.jsonl`. Separate from push-to-talk: its own microphone
/// capture and its own Soniox sessions.
@MainActor
public final class MeetingRecorder {
    public nonisolated static let sampleRate = 16_000

    public private(set) var isRecording = false
    public private(set) var startDate: Date?
    public private(set) var folder: URL?
    public let micWaveform = UntypeWaveformBuffer()
    public let callWaveform = UntypeWaveformBuffer()

    /// Log lines (`diagnostic.info: …` / `diagnostic.warning: …`).
    public var onEvent: (String) -> Void = { _ in }
    /// The recording ended (or failed to start); `folder` holds the saved
    /// transcript, or nil when nothing was saved.
    public var onFinished: (_ reason: MeetingStopReason, _ folder: URL?) -> Void = { _, _ in }

    private var options: MeetingRecordingOptions?
    private var segments: [MeetingSegment] = []
    private var liveFile: FileHandle?
    private var startUptime: TimeInterval = 0
    private var silence = MeetingSilenceMonitor(limit: 0, start: 0)
    private var silenceTimer: Timer?
    private var microphone: AVFoundationAudioSource?
    private var systemAudio: MeetingSystemAudioCapture?
    private var micStream: MeetingSonioxStream?
    private var callStream: MeetingSonioxStream?
    private var stopping = false

    public init() {
        micWaveform.configure(sampleRate: Self.sampleRate)
        callWaveform.configure(sampleRate: Self.sampleRate)
    }

    public func start(options: MeetingRecordingOptions) async throws {
        guard !isRecording, !stopping else {
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw MeetingError.screenRecordingPermission
        }
        let now = Date()
        let folder = try Self.makeFolder(root: options.folderRoot, date: now)
        let liveURL = folder.appendingPathComponent("transcript.original.txt")
        FileManager.default.createFile(atPath: liveURL.path, contents: nil)
        let liveFile = try FileHandle(forWritingTo: liveURL)

        self.options = options
        self.folder = folder
        self.liveFile = liveFile
        segments = []
        startDate = now
        startUptime = ProcessInfo.processInfo.systemUptime
        silence = MeetingSilenceMonitor(limit: TimeInterval(options.silenceMinutes * 60), start: startUptime)
        micWaveform.clear()
        callWaveform.clear()

        do {
            // Audio starts first (the overlay's red trace moves at once);
            // chunks wait in each stream's queue until Soniox is connected.
            let micStream = makeStream(side: .you, options: options)
            let callStream = makeStream(side: .call, options: options)
            self.micStream = micStream
            self.callStream = callStream

            let systemAudio = MeetingSystemAudioCapture(sampleRate: Self.sampleRate, onPCM: { [callWaveform] pcm in
                callWaveform.append(pcm: pcm, at: ProcessInfo.processInfo.systemUptime)
                callStream.push(pcm)
            }, onError: { [weak self] error in
                dispatchMeeting { self?.fail("system audio: \(error.localizedDescription)") }
            })
            self.systemAudio = systemAudio
            try await systemAudio.start()

            let microphone = AVFoundationAudioSource(options: AVFoundationAudioSourceOptions(sampleRate: Self.sampleRate))
            self.microphone = microphone
            try await Self.startMicrophone(microphone, waveform: micWaveform, stream: micStream) { [weak self] error in
                dispatchMeeting { self?.fail("microphone: \(error.localizedDescription)") }
            }
            try await Self.connect(micStream, callStream)
        } catch {
            await tearDown()
            liveFile.closeFile()
            try? FileManager.default.removeItem(at: folder)
            self.folder = nil
            startDate = nil
            throw error
        }

        isRecording = true
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            dispatchMeeting { self?.checkSilence() }
        }
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
        onEvent("diagnostic.info: [untype] meeting recording started (\(folder.lastPathComponent); auto-stop after \(options.silenceMinutes) min of silence)")
    }

    /// Stops the recording and saves the transcript.
    public func stop(reason: MeetingStopReason = .user) async {
        guard isRecording, !stopping else {
            return
        }
        stopping = true
        isRecording = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        onEvent("diagnostic.info: [untype] meeting recording stopping (\(Self.describe(reason)))")
        await tearDown()
        liveFile?.closeFile()
        liveFile = nil
        let folder = self.folder
        if let folder, let options {
            await save(to: folder, options: options)
        }
        stopping = false
        startDate = nil
        onFinished(reason, folder)
    }

    // MARK: - Internals

    private nonisolated static func connect(_ first: MeetingSonioxStream, _ second: MeetingSonioxStream) async throws {
        async let a: Void = first.start()
        async let b: Void = second.start()
        _ = try await (a, b)
    }

    private nonisolated static func startMicrophone(
        _ microphone: AVFoundationAudioSource,
        waveform: UntypeWaveformBuffer,
        stream: MeetingSonioxStream,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        try await microphone.start(handlers: AudioSourceEventHandlers(
            audio: { pcm in
                waveform.append(pcm: pcm, at: ProcessInfo.processInfo.systemUptime)
                stream.push(pcm)
            },
            error: { error in onError(error) },
            end: {}
        ))
    }

    private func makeStream(side: MeetingSide, options: MeetingRecordingOptions) -> MeetingSonioxStream {
        MeetingSonioxStream(
            side: side,
            options: options,
            diarize: side == .call,
            offsetMs: Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1000),
            onSegment: { [weak self] segment in
                dispatchMeeting { self?.add(segment) }
            },
            onSpeech: { [weak self] in
                dispatchMeeting { self?.silence.speechHeard(at: ProcessInfo.processInfo.systemUptime) }
            },
            onError: { [weak self] message in
                dispatchMeeting { self?.fail("Soniox (\(side.rawValue)): \(message)") }
            }
        )
    }

    private func add(_ segment: MeetingSegment) {
        segments.append(segment)
        if let data = (MeetingTranscriptFormat.originalLine(segment) + "\n").data(using: .utf8) {
            liveFile?.write(data)
        }
    }

    private func checkSilence() {
        guard isRecording, let options, silence.shouldStop(at: ProcessInfo.processInfo.systemUptime) else {
            return
        }
        Task { await stop(reason: .silence(minutes: options.silenceMinutes)) }
    }

    private func fail(_ message: String) {
        guard isRecording else {
            return
        }
        onEvent("diagnostic.warning: [untype] meeting recording: \(message)")
        Task { await stop(reason: .failure(message)) }
    }

    private func tearDown() async {
        try? await microphone?.stop()
        microphone = nil
        await systemAudio?.stop()
        systemAudio = nil
        let streams = [micStream, callStream].compactMap { $0 }
        micStream = nil
        callStream = nil
        for stream in streams {
            for segment in await stream.finish() {
                add(segment)
            }
        }
    }

    private func save(to folder: URL, options: MeetingRecordingOptions) async {
        var ordered = MeetingTranscriptFormat.ordered(segments)
        if options.language == .english {
            ordered = await translateToEnglish(ordered, llm: options.llm)
        }
        let original = ordered.map(MeetingTranscriptFormat.originalLine).joined(separator: "\n")
        let main = options.language == .english
            ? ordered.map(MeetingTranscriptFormat.englishLine).joined(separator: "\n")
            : original
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let jsonl = ordered.compactMap { try? encoder.encode($0) }.compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n")
        do {
            try (original + "\n").write(to: folder.appendingPathComponent("transcript.original.txt"), atomically: true, encoding: .utf8)
            try (main + "\n").write(to: folder.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
            try (jsonl + "\n").write(to: folder.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
            onEvent("diagnostic.info: [untype] meeting transcript saved (\(ordered.count) lines) in \(folder.path)")
        } catch {
            onEvent("diagnostic.warning: [untype] meeting transcript could not be saved: \(error.localizedDescription)")
        }
    }

    /// Fills `english` for every segment not already in English, chunk by
    /// chunk; a chunk the model fails on keeps the text as spoken.
    private func translateToEnglish(_ segments: [MeetingSegment], llm: LLMConfig) async -> [MeetingSegment] {
        var result = segments
        let indices = segments.indices.filter { segments[$0].language != "en" }
        guard !indices.isEmpty else {
            return result
        }
        let translator: TextRefining
        do {
            guard let made = try LLMRefinerFactory.makeTranslator(config: llm, systemPrompt: MeetingTranslationChunks.systemPrompt) else {
                onEvent("diagnostic.warning: [untype] meeting transcript kept as spoken: no LLM is configured for translation")
                return result
            }
            translator = made
        } catch {
            onEvent("diagnostic.warning: [untype] meeting transcript kept as spoken: \(error.localizedDescription)")
            return result
        }
        defer { translator.dispose() }
        let texts = indices.map { segments[$0].text }
        var position = 0
        for chunk in MeetingTranslationChunks.chunks(texts, maxCharacters: 1_500, maxLines: 25) {
            let chunkIndices = Array(indices[position..<(position + chunk.count)])
            position += chunk.count
            do {
                let answer = try await translator.refine(MeetingTranslationChunks.request(chunk))
                if let english = MeetingTranslationChunks.parse(answer, count: chunk.count) {
                    for (index, text) in zip(chunkIndices, english) {
                        result[index].english = text
                    }
                } else {
                    onEvent("diagnostic.warning: [untype] meeting translation: the model's answer did not match \(chunk.count) lines; those lines are kept as spoken")
                }
            } catch {
                onEvent("diagnostic.warning: [untype] meeting translation failed for \(chunk.count) lines (kept as spoken): \(error.localizedDescription)")
            }
        }
        return result
    }

    private static func makeFolder(root: URL, date: Date) throws -> URL {
        let base = MeetingTranscriptFormat.folderName(for: date)
        var folder = root.appendingPathComponent(base, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = root.appendingPathComponent("\(base) (\(counter))", isDirectory: true)
            counter += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func describe(_ reason: MeetingStopReason) -> String {
        switch reason {
        case .user: return "stopped by the user"
        case .silence(let minutes): return "\(minutes) min of silence"
        case .failure(let message): return "error: \(message)"
        }
    }
}

private func dispatchMeeting(_ work: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            work()
        }
    }
}

/// One Soniox real-time session of a meeting (one side of the call).
/// Audio is sent in order through a single consumer task.
final class MeetingSonioxStream: @unchecked Sendable {
    private let side: MeetingSide
    private let socket: URLSessionRealtimeWebSocketClient
    private let configFrame: String
    private let lock = NSLock()
    private var aggregator: MeetingTokenAggregator
    private let audio: AsyncStream<Data>
    private let audioContinuation: AsyncStream<Data>.Continuation
    private var sender: Task<Void, Never>?
    private var keepalive: Task<Void, Never>?
    private var finished = false
    private var finishWaiter: CheckedContinuation<Void, Never>?
    private let onSegment: @Sendable (MeetingSegment) -> Void
    private let onSpeech: @Sendable () -> Void
    private let onError: @Sendable (String) -> Void
    /// The words heard so far, final or not, after every result frame (nil:
    /// nobody shows them).
    private let onLiveText: (@Sendable (String) -> Void)?
    private var liveText = MeetingLiveText()

    init(
        side: MeetingSide,
        options: MeetingRecordingOptions,
        diarize: Bool,
        offsetMs: Int,
        onSegment: @escaping @Sendable (MeetingSegment) -> Void,
        onSpeech: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void,
        onLiveText: (@Sendable (String) -> Void)? = nil
    ) {
        self.side = side
        self.onLiveText = onLiveText
        socket = URLSessionRealtimeWebSocketClient(url: options.endpoint)
        configFrame = Self.configFrame(options: options, side: side, diarize: diarize)
        aggregator = MeetingTokenAggregator(side: side, offsetMs: offsetMs)
        (audio, audioContinuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        self.onSegment = onSegment
        self.onSpeech = onSpeech
        self.onError = onError
    }

    static func configFrame(options: MeetingRecordingOptions, side: MeetingSide, diarize: Bool) -> String {
        let frame: [String: Any] = [
            "api_key": options.apiKey,
            "model": options.model,
            "audio_format": "pcm_s16le",
            "sample_rate": MeetingRecorder.sampleRate,
            "num_channels": 1,
            "language_hints": ["el", "en"],
            "enable_language_identification": true,
            "enable_endpoint_detection": true,
            "enable_speaker_diarization": diarize,
            "client_reference_id": "untype-meeting-\(side.rawValue)"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func start() async throws {
        socket.setHandlers(RealtimeWebSocketHandlers(
            text: { [weak self] text in
                self?.handle(text)
            },
            error: { [weak self] error in
                self?.reportError(error.localizedDescription)
            },
            closed: { [weak self] in
                self?.markFinished()
            }
        ))
        do {
            try await socket.connect()
            try await socket.sendText(configFrame)
        } catch {
            throw MeetingError.soniox(error.localizedDescription)
        }
        let socket = socket
        let audio = audio
        sender = Task {
            for await chunk in audio {
                try? await socket.sendBinary(chunk)
            }
            // End of audio: Soniox finishes the stream and answers `finished`.
            try? await socket.sendText("")
        }
        keepalive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                try? await socket.sendText(#"{"type":"keepalive"}"#)
            }
        }
    }

    func push(_ pcm: Data) {
        audioContinuation.yield(pcm)
    }

    /// Ends the audio, waits (up to 8 s) for Soniox to finish, and returns
    /// the segments still pending.
    func finish() async -> [MeetingSegment] {
        keepalive?.cancel()
        audioContinuation.finish()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
                return
            }
            finishWaiter = continuation
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self?.markFinished()
            }
        }
        socket.close()
        return flushPending().map { [$0] } ?? []
    }

    private func flushPending() -> MeetingSegment? {
        lock.withLock { aggregator.flush() }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let code = object["error_code"] {
            let message = object["error_message"] as? String ?? "error \(code)"
            reportError(message)
            return
        }
        if let tokens = object["tokens"] as? [[String: Any]] {
            let parsed = MeetingToken.parse(tokens)
            lock.lock()
            let segments = aggregator.add(parsed)
            let heard = onLiveText == nil ? nil : liveText.add(parsed)
            lock.unlock()
            if let heard {
                onLiveText?(heard)
            }
            if parsed.contains(where: { !$0.isMarker && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
                onSpeech()
            }
            segments.forEach(onSegment)
        }
        if object["finished"] as? Bool == true {
            markFinished()
        }
    }

    private func reportError(_ message: String) {
        lock.lock()
        let done = finished
        lock.unlock()
        if !done {
            onError(message)
        }
    }

    private func markFinished() {
        lock.lock()
        finished = true
        let waiter = finishWaiter
        finishWaiter = nil
        lock.unlock()
        waiter?.resume()
    }
}

/// System audio of every app except untype, through ScreenCaptureKit
/// (audio only; the tiny video frames are discarded), converted to PCM16
/// mono at `sampleRate`.
final class MeetingSystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let sampleRate: Int
    private let onPCM: @Sendable (Data) -> Void
    private let onError: @Sendable (Error) -> Void
    private let queue = DispatchQueue(label: "untype.meeting.system-audio")
    private var stream: SCStream?
    private var converter: PCM16MonoConverter?
    private var converterFormat: AVAudioFormat?

    init(sampleRate: Int, onPCM: @escaping @Sendable (Data) -> Void, onError: @escaping @Sendable (Error) -> Void) {
        self.sampleRate = sampleRate
        self.onPCM = onPCM
        self.onError = onError
    }

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw MeetingError.screenRecordingPermission
        }
        guard let display = content.displays.first else {
            throw MeetingError.capture("no display is available for system audio capture")
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 5
        configuration.showsCursor = false
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            throw MeetingError.capture(error.localizedDescription)
        }
        self.stream = stream
    }

    func stop() async {
        guard let stream else {
            return
        }
        self.stream = nil
        try? await stream.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let buffer = Self.pcmBuffer(sampleBuffer) else {
            return
        }
        do {
            if converter == nil || converterFormat != buffer.format {
                converter = try PCM16MonoConverter(inputFormat: buffer.format, sampleRate: sampleRate)
                converterFormat = buffer.format
            }
            guard let converter else {
                return
            }
            let pcm = try converter.convert(buffer)
            if !pcm.isEmpty {
                onPCM(pcm)
            }
        } catch {
            onError(error)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }

    private static func pcmBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return nil
        }
        var streamDescription = basic.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            return nil
        }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}

/// Listens to one short description of a saved meeting ("budget review with
/// Maria…") on its own microphone capture and Soniox session, separate from
/// push-to-talk. Ends after `pause` seconds without speech once something
/// was said, at `finish()`, or after 60 s; `onDone` gets the words (nil when
/// cancelled or nothing was heard).
@MainActor
public final class MeetingNamer {
    public let waveform = UntypeWaveformBuffer()
    public var onDone: (String?) -> Void = { _ in }
    /// The words heard so far, as they are recognized.
    public var onHeard: (String) -> Void = { _ in }
    public private(set) var isListening = false

    private var microphone: AVFoundationAudioSource?
    private var stream: MeetingSonioxStream?
    private var heard: [String] = []
    private var timeout: Task<Void, Never>?
    private var ending = false
    private var lastSpeech: TimeInterval?
    /// Seconds of quiet that end the description (a breath is shorter).
    public static let pause: TimeInterval = 4

    public init() {
        waveform.configure(sampleRate: MeetingRecorder.sampleRate)
    }

    public func start(options: MeetingRecordingOptions) async throws {
        guard !isListening else {
            return
        }
        heard = []
        ending = false
        lastSpeech = nil
        waveform.clear()
        let stream = MeetingSonioxStream(
            side: .you,
            options: options,
            diarize: false,
            offsetMs: 0,
            onSegment: { [weak self] segment in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.heard.append(segment.text)
                    }
                }
            },
            onSpeech: { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.lastSpeech = ProcessInfo.processInfo.systemUptime
                    }
                }
            },
            onError: { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        Task { await self?.finish() }
                    }
                }
            },
            onLiveText: { [weak self] text in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.isListening, !self.ending else {
                            return
                        }
                        self.onHeard(text)
                    }
                }
            }
        )
        self.stream = stream
        let microphone = AVFoundationAudioSource(options: AVFoundationAudioSourceOptions(sampleRate: MeetingRecorder.sampleRate))
        self.microphone = microphone
        do {
            try await stream.start()
            try await Self.startMicrophone(microphone, waveform: waveform, stream: stream)
        } catch {
            try? await microphone.stop()
            _ = await stream.finish()
            self.microphone = nil
            self.stream = nil
            throw error
        }
        isListening = true
        let started = ProcessInfo.processInfo.systemUptime
        timeout = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let paused = lastSpeech.map { now - $0 >= Self.pause } ?? false
                if paused || now - started >= 60 {
                    await finish()
                    return
                }
            }
        }
    }

    /// Stops listening and reports what was said.
    public func finish() async {
        await end(report: true)
    }

    /// Stops listening without naming.
    public func cancel() async {
        await end(report: false)
    }

    private func end(report: Bool) async {
        guard isListening, !ending else {
            return
        }
        ending = true
        timeout?.cancel()
        timeout = nil
        try? await microphone?.stop()
        microphone = nil
        if let stream {
            self.stream = nil
            for segment in await stream.finish() {
                heard.append(segment.text)
            }
        }
        isListening = false
        let text = heard.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        onDone(report && !text.isEmpty ? text : nil)
    }

    private nonisolated static func startMicrophone(
        _ microphone: AVFoundationAudioSource,
        waveform: UntypeWaveformBuffer,
        stream: MeetingSonioxStream
    ) async throws {
        try await microphone.start(handlers: AudioSourceEventHandlers(
            audio: { pcm in
                waveform.append(pcm: pcm, at: ProcessInfo.processInfo.systemUptime)
                stream.push(pcm)
            },
            error: { _ in },
            end: {}
        ))
    }

    /// A short English title from the spoken description, through the
    /// primary LLM (the description itself, cleaned, when no LLM is set up
    /// or the call fails).
    public static func title(from spoken: String, llm: LLMConfig) async -> String {
        guard let model = try? LLMRefinerFactory.makeTranslator(config: llm, systemPrompt: MeetingNaming.titlePrompt) else {
            return MeetingNaming.sanitize(spoken)
        }
        defer { model.dispose() }
        guard let answer = try? await model.refine(spoken) else {
            return MeetingNaming.sanitize(spoken)
        }
        let title = MeetingNaming.sanitize(answer.split(separator: "\n").first.map(String.init) ?? answer)
        return title.isEmpty ? MeetingNaming.sanitize(spoken) : title
    }
}
