@preconcurrency import AVFoundation
import Foundation

public struct AVFoundationAudioSourceOptions: Sendable, Equatable {
    public let sampleRate: Int
    public let bufferFrameCount: AVAudioFrameCount
    /// Apple's voice processing on the microphone: the sound the Mac itself
    /// plays (the loudspeakers) is removed from what the microphone hears.
    /// While it runs, any other capture in this process gets no audio.
    public let voiceProcessing: Bool

    public init(sampleRate: Int, bufferFrameCount: AVAudioFrameCount = 1_024, voiceProcessing: Bool = false) {
        self.sampleRate = sampleRate
        self.bufferFrameCount = bufferFrameCount
        self.voiceProcessing = voiceProcessing
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
        if options.voiceProcessing {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
            } catch {
                throw UntypeError.microphoneCapture("Failed to enable voice processing on the microphone: \(error.localizedDescription)")
            }
            // The other apps (the call) keep their volume as far as macOS allows.
            inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        // With voice processing the node has several channels; the first
        // carries the processed microphone.
        let converter = try PCM16MonoConverter(inputFormat: inputFormat, sampleRate: options.sampleRate, firstChannelOnly: options.voiceProcessing)
        self.converter = converter
        self.handlers = handlers

        inputNode.installTap(
            onBus: 0,
            bufferSize: options.bufferFrameCount,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            started = true
        } catch {
            inputNode.removeTap(onBus: 0)
            if options.voiceProcessing {
                try? inputNode.setVoiceProcessingEnabled(false)
            }
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
        if options.voiceProcessing {
            // Off again, so that an ordinary capture works afterwards.
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        converter = nil
        handlers = nil
        started = false
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let handlers else {
            return
        }
        do {
            let pcm = try converter.convert(buffer)
            guard !pcm.isEmpty else {
                return
            }
            Task {
                await handlers.audio(pcm)
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
    /// Set when only the first channel of a multichannel input is used.
    private let monoInputFormat: AVAudioFormat?

    public init(inputFormat: AVAudioFormat, sampleRate: Int, firstChannelOnly: Bool = false) throws {
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
        var monoInputFormat: AVAudioFormat?
        if firstChannelOnly, inputFormat.channelCount > 1 {
            guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false) else {
                throw UntypeError.microphoneCapture("Failed to create the mono format for the processed microphone.")
            }
            monoInputFormat = mono
        }
        guard let converter = AVAudioConverter(from: monoInputFormat ?? inputFormat, to: outputFormat) else {
            throw UntypeError.microphoneCapture("Failed to create AVAudioConverter for microphone input.")
        }
        self.monoInputFormat = monoInputFormat
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
    }

    public func convert(_ capturedBuffer: AVAudioPCMBuffer) throws -> Data {
        guard capturedBuffer.frameLength > 0 else {
            return Data()
        }
        let inputBuffer: AVAudioPCMBuffer
        if let monoInputFormat {
            guard let channels = capturedBuffer.floatChannelData,
                  let mono = AVAudioPCMBuffer(pcmFormat: monoInputFormat, frameCapacity: capturedBuffer.frameLength),
                  let target = mono.floatChannelData
            else {
                throw UntypeError.microphoneCapture("The processed microphone audio is not in the expected format.")
            }
            target[0].update(from: channels[0], count: Int(capturedBuffer.frameLength))
            mono.frameLength = capturedBuffer.frameLength
            inputBuffer = mono
        } else {
            inputBuffer = capturedBuffer
        }

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
