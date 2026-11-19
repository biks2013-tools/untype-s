@preconcurrency import AVFoundation
import Foundation

/// Never with Apple's voice processing: it changes the microphone for the
/// whole Mac and silenced it for the call application (Teams, 2026-11-19).
/// The meeting removes the loudspeakers' sound in software instead
/// (`MeetingEchoCanceller`, plan-072).
public struct AVFoundationAudioSourceOptions: Sendable, Equatable {
    public let sampleRate: Int
    public let bufferFrameCount: AVAudioFrameCount

    public init(sampleRate: Int, bufferFrameCount: AVAudioFrameCount = 1_024) {
        self.sampleRate = sampleRate
        self.bufferFrameCount = bufferFrameCount
    }

    public init(config: ResolvedConfig, bufferFrameCount: AVAudioFrameCount = 1_024) {
        self.init(sampleRate: config.sampleRate, bufferFrameCount: bufferFrameCount)
    }
}

public final class AVFoundationAudioSource: RuntimeAudioSource, @unchecked Sendable {
    private let options: AVFoundationAudioSourceOptions
    private let engine: AVAudioEngine
    private var converter: PCM16MonoConverter?
    private var handlers: AudioSourceEventHandlers?
    private var started = false

    public init(
        options: AVFoundationAudioSourceOptions,
        engine: AVAudioEngine = AVAudioEngine()
    ) {
        self.options = options
        self.engine = engine
    }

    public func start(handlers: AudioSourceEventHandlers) async throws {
        guard !started else {
            throw UntypeError.microphoneCapture("AVFoundation audio source start() called more than once.")
        }
        try await Self.ensureMicrophonePermission()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let converter = try PCM16MonoConverter(inputFormat: inputFormat, sampleRate: options.sampleRate)
        self.converter = converter
        self.handlers = handlers

        inputNode.installTap(
            onBus: 0,
            bufferSize: options.bufferFrameCount,
            format: inputFormat
        ) { [weak self] buffer, when in
            self?.handleInputBuffer(buffer, at: when)
        }

        do {
            engine.prepare()
            try engine.start()
            started = true
        } catch {
            inputNode.removeTap(onBus: 0)
            self.converter = nil
            self.handlers = nil
            throw UntypeError.microphoneCapture("Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }

    public func stop() async throws {
        guard started else {
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        handlers = nil
        started = false
    }

    /// When the first sample of a tap buffer was captured, on the
    /// `ProcessInfo.systemUptime` clock: the buffer's host time (measured
    /// 2026-11-19: the same clock within microseconds; buffers arrive their
    /// own length plus a few ms after it), or, without a valid host time,
    /// the arrival time minus the buffer's length.
    static func captureTime(
        of when: AVAudioTime,
        frames: AVAudioFrameCount,
        sampleRate: Double,
        arrivedAt now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> TimeInterval {
        if when.isHostTimeValid {
            return AVAudioTime.seconds(forHostTime: when.hostTime)
        }
        return now - Double(frames) / max(1, sampleRate)
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
        guard let converter, let handlers else {
            return
        }
        let capturedAt = Self.captureTime(of: when, frames: buffer.frameLength, sampleRate: buffer.format.sampleRate)
        do {
            let pcm = try converter.convert(buffer)
            guard !pcm.isEmpty else {
                return
            }
            Task {
                if let timedAudio = handlers.timedAudio {
                    await timedAudio(pcm, capturedAt)
                } else {
                    await handlers.audio(pcm)
                }
            }
        } catch {
            Task {
                await handlers.error(error)
            }
        }
    }

    private static func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                return
            }
            throw UntypeError.microphonePermission("Microphone permission was denied. Grant microphone access to the untype executable or app bundle in macOS Privacy & Security settings.")
        case .denied:
            throw UntypeError.microphonePermission("Microphone permission is denied. Grant microphone access to the untype executable or app bundle in macOS Privacy & Security settings.")
        case .restricted:
            throw UntypeError.microphonePermission("Microphone access is restricted by macOS policy.")
        @unknown default:
            throw UntypeError.microphonePermission("Microphone permission is unavailable because macOS returned an unknown authorization status.")
        }
    }
}

public final class PCM16MonoConverter: @unchecked Sendable {
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    public init(inputFormat: AVAudioFormat, sampleRate: Int) throws {
        guard sampleRate > 0 else {
            throw UntypeError.microphoneCapture("Audio sample rate must be positive. Got: \(sampleRate).")
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw UntypeError.microphoneCapture("Failed to create mono PCM16 output audio format.")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw UntypeError.microphoneCapture("Failed to create AVAudioConverter for microphone input.")
        }
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
    }

    public func convert(_ capturedBuffer: AVAudioPCMBuffer) throws -> Data {
        guard capturedBuffer.frameLength > 0 else {
            return Data()
        }
        let inputBuffer = capturedBuffer

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw UntypeError.microphoneCapture("Failed to allocate PCM16 output buffer.")
        }

        let inputBox = PCMInputBufferBox(inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputBox.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBox.didProvideInput = true
            outStatus.pointee = .haveData
            return inputBox.buffer
        }

        if let conversionError {
            throw UntypeError.microphoneCapture("Failed to convert microphone audio to PCM16: \(conversionError.localizedDescription)")
        }
        if status == .error {
            throw UntypeError.microphoneCapture("Failed to convert microphone audio to PCM16.")
        }
        guard outputBuffer.frameLength > 0 else {
            return Data()
        }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else {
            return Data()
        }
        return Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
    }
}

private final class PCMInputBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideInput = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
