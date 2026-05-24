@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import UntypeCore

@Test func pcm16MonoConverterRejectsInvalidSampleRate() throws {
    let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))

    #expect(throws: UntypeError.self) {
        _ = try PCM16MonoConverter(inputFormat: inputFormat, sampleRate: 0)
    }
}

@Test func pcm16MonoConverterConvertsSyntheticFloatBufferToInt16Data() throws {
    let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let inputBuffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4))
    inputBuffer.frameLength = 4
    let samples = try #require(inputBuffer.floatChannelData?[0])
    samples[0] = -1.0
    samples[1] = 0.0
    samples[2] = 0.5
    samples[3] = 1.0
    let converter = try PCM16MonoConverter(inputFormat: inputFormat, sampleRate: 16_000)

    let data = try converter.convert(inputBuffer)

    #expect(data.count == 8)
    #expect(data != Data(repeating: 0, count: 8))
}

@Test func pcm16MonoConverterReturnsEmptyDataForEmptyInputBuffer() throws {
    let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let inputBuffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4))
    inputBuffer.frameLength = 0
    let converter = try PCM16MonoConverter(inputFormat: inputFormat, sampleRate: 16_000)

    let data = try converter.convert(inputBuffer)

    #expect(data.isEmpty)
}
