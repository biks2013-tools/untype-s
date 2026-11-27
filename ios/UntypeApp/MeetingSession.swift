@preconcurrency import AVFoundation
import Foundation
import os
import SwiftUI
import UntypeCore

/// Recording a meeting on the iPhone or iPad: the microphone goes to an
/// audio file, and, while the transcript is on, to Soniox. The transcript
/// can be switched on and off during the recording; every line keeps its
/// place in the audio.
@MainActor
final class MeetingSession: ObservableObject {
    static let shared = MeetingSession()
    nonisolated static let sampleRate = 16_000
    /// Counts, lengths and durations only: never the words.
    nonisolated static let log = Logger(subsystem: "com.biks2013.untype", category: "meeting")

    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case saving
    }

    @Published private(set) var phase: Phase = .idle
    /// Seconds of audio recorded.
    @Published private(set) var elapsed: TimeInterval = 0
    /// The loudest sound of the last tenth of a second, 0…1.
    @Published private(set) var level: Double = 0
    /// The lines heard so far, in time order.
    @Published private(set) var segments: [MeetingSegment] = []
    /// The words of the line being spoken.
    @Published private(set) var inProgress = ""
    /// Whether the transcript is being made now.
    @Published private(set) var transcribing = false
    /// The transcript is connecting or finishing.
    @Published private(set) var transcriptBusy = false
    /// A phone call or another app took the microphone.
    @Published private(set) var interrupted = false
    @Published var problem: String?
    /// The meeting saved last (to open it after the recording).
    @Published private(set) var lastSaved: SavedMeeting?
    /// The meeting just saved, until the Meetings tab has opened it.
    @Published var savedToOpen: SavedMeeting?
    /// Set by the "Record meeting" shortcut; the app starts a recording.
    @Published var quickStartRequested = false

    private var microphone: MeetingMicrophone?
    private var pipe: MeetingAudioPipe?
    private var files: MeetingFolderWriter?
    private var stream: MeetingTranscriptionStream?
    private var interruptionObserver: NSObjectProtocol?

    var isActive: Bool {
        phase != .idle
    }

    // MARK: - Recording

    func start(settings: AppSettings, transcribe: Bool) async {
        guard phase == .idle else {
            return
        }
        problem = nil
        lastSaved = nil
        segments = []
        inProgress = ""
        elapsed = 0
        level = 0
        interrupted = false
        phase = .starting
        do {
            guard await MeetingMicrophone.permission() else {
                throw AppError("untype may not use the microphone. Allow it in Settings → Privacy & Security → Microphone.")
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let start = Date()
            let files = try MeetingFolderWriter(root: MeetingLibrary.root, start: start)
            let writer = try MeetingAudioWriter(url: files.audioURL, sampleRate: Self.sampleRate)
            let pipe = MeetingAudioPipe(writer: writer, sampleRate: Self.sampleRate)
            pipe.onProgress = { [weak self] samples, level in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.elapsed = Double(samples) / Double(Self.sampleRate)
                        self?.level = level
                    }
                }
            }
            pipe.onFailure = { [weak self] message in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.problem = "The audio could not be written: \(message)"
                        Task { await self?.stop() }
                    }
                }
            }
            let microphone = MeetingMicrophone(sampleRate: Self.sampleRate) { [weak pipe] pcm in
                pipe?.push(pcm)
            }
            try microphone.start()
            self.files = files
            self.pipe = pipe
            self.microphone = microphone
            observeInterruptions()
            phase = .recording
            Self.log.info("meeting recording started, input: \(session.currentRoute.inputs.first?.portType.rawValue ?? "none", privacy: .public)")
            if transcribe {
                await startTranscript(settings: settings)
            }
        } catch {
            Self.log.error("meeting recording could not start: \(error.localizedDescription, privacy: .public)")
            microphone?.stop()
            microphone = nil
            _ = pipe?.finish()
            pipe = nil
            files = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            problem = error.localizedDescription
            phase = .idle
        }
    }

    func stop() async {
        guard phase == .recording || phase == .starting else {
            return
        }
        phase = .saving
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        microphone?.stop()
        microphone = nil
        // The audio already heard reaches the transcript before it ends.
        let last = pipe?.detach()
        let samples = pipe?.finish() ?? 0
        pipe = nil
        stream = nil
        if let last {
            transcriptBusy = true
            if let segment = await last.finish() {
                add(segment)
            }
            transcriptBusy = false
        }
        transcribing = false
        inProgress = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let files {
            do {
                try files.finish(segments)
            } catch {
                problem = "The transcript could not be saved: \(error.localizedDescription)"
            }
            lastSaved = SavedMeeting(folder: files.folder)
            savedToOpen = lastSaved
            Self.log.info("meeting saved: \(Double(samples) / Double(Self.sampleRate), format: .fixed(precision: 1)) s of audio, \(self.segments.count) lines")
        }
        files = nil
        phase = .idle
    }

    // MARK: - Transcript

    /// Switches the transcript on or off during the recording.
    func setTranscript(_ on: Bool, settings: AppSettings) async {
        guard phase == .recording, !transcriptBusy, on != transcribing else {
            return
        }
        if on {
            await startTranscript(settings: settings)
        } else {
            await stopTranscript()
        }
    }

    private func startTranscript(settings: AppSettings) async {
        guard let pipe else {
            return
        }
        let options: SonioxTranscriberOptions
        do {
            options = try settings.sonioxOptions()
        } catch {
            problem = "The transcript is off: \(error.localizedDescription) The audio is being recorded."
            return
        }
        transcriptBusy = true
        defer { transcriptBusy = false }
        let stream: MeetingTranscriptionStream
        do {
            stream = try pipe.attach { offset in
                try MeetingTranscriptionStream(
                    options: options,
                    offsetMs: offset,
                    onSegment: { [weak self] segment in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated { self?.add(segment) }
                        }
                    },
                    onInProgress: { [weak self] text in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                guard self?.transcribing == true else { return }
                                self?.inProgress = text
                            }
                        }
                    },
                    onError: { [weak self] message in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                guard let self, self.transcribing else { return }
                                Self.log.error("meeting transcript failed: \(message, privacy: .public)")
                                self.problem = "The transcript stopped: \(message) The audio is still being recorded."
                                Task { await self.stopTranscript() }
                            }
                        }
                    }
                )
            }
        } catch {
            problem = error.localizedDescription
            return
        }
        self.stream = stream
        transcribing = true
        do {
            try await stream.start()
            Self.log.info("meeting transcript connected")
        } catch {
            _ = pipe.detach()
            self.stream = nil
            transcribing = false
            problem = "\(error.localizedDescription) The audio is being recorded without a transcript."
        }
    }

    private func stopTranscript() async {
        guard let pipe, transcribing else {
            return
        }
        transcriptBusy = true
        transcribing = false
        let stream = pipe.detach()
        self.stream = nil
        if let segment = await stream?.finish() {
            add(segment)
        }
        inProgress = ""
        transcriptBusy = false
    }

    private func add(_ segment: MeetingSegment) {
        let index = segments.firstIndex { $0.startMs > segment.startMs } ?? segments.endIndex
        segments.insert(segment, at: index)
        files?.append(segment)
    }

    // MARK: - Interruptions

    /// A phone call stops the microphone; when it ends, recording goes on in
    /// the same file (the call's time is not in the audio).
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated {
                self?.interruption(type)
            }
        }
    }

    private func interruption(_ type: AVAudioSession.InterruptionType?) {
        guard phase == .recording, let type else {
            return
        }
        switch type {
        case .began:
            interrupted = true
            Self.log.info("meeting recording interrupted")
        case .ended:
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                microphone?.stop()
                try microphone?.start()
                interrupted = false
                Self.log.info("meeting recording resumed")
            } catch {
                problem = "The microphone could not be started again: \(error.localizedDescription)"
            }
        @unknown default:
            break
        }
    }
}
