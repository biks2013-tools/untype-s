@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import UntypeCore

/// Writes PCM16 mono samples to an AAC `.m4a` file as they arrive, in
/// fragments of two seconds (as the Mac's meeting recorder does), so what is
/// on disk plays even when the recording never gets to close the file.
final class MeetingAudioWriter {
    static let fragmentSeconds: Int64 = 2

    let url: URL
    private let sampleRate: Int
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let formatDescription: CMAudioFormatDescription
    private(set) var written: Int64 = 0
    private var closed = false

    init(url: URL, sampleRate: Int) throws {
        self.url = url
        self.sampleRate = sampleRate
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )
        guard status == noErr, let format else {
            throw AppError("The audio format could not be made (\(status)).")
        }
        formatDescription = format
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        // Not optimised for network use: that keeps the audio in a temporary
        // file until the end, which defeats writing as it arrives.
        writer.shouldOptimizeForNetworkUse = false
        writer.movieFragmentInterval = CMTime(value: Self.fragmentSeconds, timescale: 1)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw AppError("The audio file does not take AAC audio.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw AppError(writer.error?.localizedDescription ?? "The audio file could not be started.")
        }
        writer.startSession(atSourceTime: .zero)
    }

    func write(_ pcm: Data) throws {
        let count = pcm.count / MemoryLayout<Int16>.size
        guard !closed, count > 0 else {
            return
        }
        let byteCount = count * MemoryLayout<Int16>.size
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &block
        )
        guard status == kCMBlockBufferNoErr, let block else {
            throw AppError("The audio buffer could not be made (\(status)).")
        }
        status = pcm.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard status == kCMBlockBufferNoErr else {
            throw AppError("The audio buffer could not be filled (\(status)).")
        }
        var sampleBuffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDescription,
            sampleCount: count,
            presentationTimeStamp: CMTime(value: written, timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw AppError("The audio sample could not be made (\(status)).")
        }
        var waited = 0
        while !input.isReadyForMoreMediaData, writer.status == .writing, waited < 2_000 {
            usleep(1_000)
            waited += 1
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData, input.append(sampleBuffer) else {
            throw AppError(writer.error?.localizedDescription ?? "The audio file stopped taking audio.")
        }
        written += Int64(count)
    }

    func close() {
        guard !closed else {
            return
        }
        closed = true
        guard writer.status == .writing else {
            return
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting {
            done.signal()
        }
        _ = done.wait(timeout: .now() + 10)
    }
}

/// The microphone for a meeting: every tap buffer is converted to PCM16
/// mono and handed over on the tap's own thread, in the order it was heard
/// (the order the audio file and the transcript need).
final class MeetingMicrophone {
    private let engine = AVAudioEngine()
    private var converter: PCM16MonoConverter?
    private let sampleRate: Int
    private let onAudio: (Data) -> Void

    init(sampleRate: Int, onAudio: @escaping (Data) -> Void) {
        self.sampleRate = sampleRate
        self.onAudio = onAudio
    }

    static func permission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw AppError("No microphone is available.")
        }
        let converter = try PCM16MonoConverter(inputFormat: format, sampleRate: sampleRate)
        self.converter = converter
        let onAudio = onAudio
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            guard let pcm = try? converter.convert(buffer), !pcm.isEmpty else {
                return
            }
            onAudio(pcm)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AppError("The microphone could not be started: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }
}

/// Carries the microphone's audio, in order, to the audio file and (while
/// the transcript is on) to the transcription stream. Counts the samples
/// written: the position in the audio is the meeting's clock, so transcript
/// lines stay on their place in the audio even across an interruption.
final class MeetingAudioPipe: @unchecked Sendable {
    let sampleRate: Int
    private let queue = DispatchQueue(label: "com.biks2013.untype.meeting-audio")
    private let writer: MeetingAudioWriter
    private var stream: MeetingTranscriptionStream?
    private var failed = false
    private var peak: Int = 0
    private var lastReport: Int64 = 0
    /// Called on the pipe's queue about ten times a second: samples written
    /// and the loudest sample since the last call (0…1).
    var onProgress: ((Int64, Double) -> Void)?
    var onFailure: ((String) -> Void)?

    init(writer: MeetingAudioWriter, sampleRate: Int) {
        self.writer = writer
        self.sampleRate = sampleRate
    }

    func push(_ pcm: Data) {
        queue.async { [self] in
            guard !failed else {
                return
            }
            do {
                try writer.write(pcm)
            } catch {
                failed = true
                onFailure?(error.localizedDescription)
                return
            }
            stream?.push(pcm)
            pcm.withUnsafeBytes { raw in
                for sample in raw.bindMemory(to: Int16.self) {
                    peak = max(peak, abs(Int(sample)))
                }
            }
            if writer.written - lastReport >= Int64(sampleRate / 10) {
                lastReport = writer.written
                onProgress?(writer.written, min(1, Double(peak) / 32_767))
                peak = 0
            }
        }
    }

    /// Makes a transcription stream that starts at the current position in
    /// the audio (ms, given to `make`); from then on the audio also goes to
    /// it, from exactly that position.
    func attach(_ make: (Int) throws -> MeetingTranscriptionStream) rethrows -> MeetingTranscriptionStream {
        try queue.sync {
            let made = try make(Int(writer.written * 1000 / Int64(sampleRate)))
            stream = made
            return made
        }
    }

    /// Stops sending audio to the transcription stream; returns it.
    func detach() -> MeetingTranscriptionStream? {
        queue.sync {
            defer { stream = nil }
            return stream
        }
    }

    /// Waits for the audio already pushed, then finishes the file.
    func finish() -> Int64 {
        queue.sync {
            writer.close()
            return writer.written
        }
    }
}
