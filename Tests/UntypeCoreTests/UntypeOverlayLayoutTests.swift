import Foundation
import Testing
@testable import UntypeCore

@Test func overlayLayoutUsesConfiguredFixedSize() {
    let layout = UntypeOverlayLayout(width: 240, height: 44)
    let visibleFrame = CGRect(x: 100, y: 200, width: 1000, height: 700)

    let frame = layout.panelFrame(in: visibleFrame)

    #expect(frame.width == 240)
    #expect(frame.height == 44)
}

@Test func overlayLayoutFrameIsBottomCentered() {
    let layout = UntypeOverlayLayout(width: 240, height: 44, bottomOffset: 46)
    let visibleFrame = CGRect(x: 100, y: 200, width: 1000, height: 700)

    let frame = layout.panelFrame(in: visibleFrame)

    #expect(frame.midX == visibleFrame.midX)
    #expect(frame.minY == visibleFrame.minY + layout.bottomOffset)
}

private func pcm16(_ samples: [Int16]) -> Data {
    var data = Data()
    for sample in samples {
        let bits = UInt16(bitPattern: sample)
        data.append(UInt8(bits & 0xFF))
        data.append(UInt8(bits >> 8))
    }
    return data
}

@Test func waveformBufferAveragesSamplesDownToDisplayPoints() {
    let buffer = UntypeWaveformBuffer(duration: 1)
    buffer.configure(sampleRate: 16_000) // 8 samples per point
    buffer.append(pcm: pcm16(Array(repeating: 16_384, count: 8) + Array(repeating: -16_384, count: 8)), at: 10)
    buffer.append(pcm: pcm16(Array(repeating: 0, count: 16)), at: 10)

    // One chunk behind the newest audio, 10 s later (fully advanced).
    let window = buffer.window(count: 4, at: 20)
    #expect(window == [0.5, -0.5, 0, 0])
}

@Test func waveformBufferScrollsSmoothlyBetweenChunks() {
    let buffer = UntypeWaveformBuffer(duration: 1)
    buffer.configure(sampleRate: 16_000)
    buffer.append(pcm: pcm16(Array(repeating: 8_192, count: 80)), at: 0)
    buffer.append(pcm: pcm16(Array(repeating: -8_192, count: 80)), at: 1)

    let atArrival = buffer.window(count: 10, at: 1)
    let halfway = buffer.window(count: 10, at: 1 + 5.5 / UntypeWaveformBuffer.pointsPerSecond)
    #expect(atArrival.allSatisfy { $0 == 0.25 })
    #expect(halfway.suffix(5).allSatisfy { $0 == -0.25 })
    #expect(halfway.prefix(5).allSatisfy { $0 == 0.25 })
}

@Test func waveformBufferClearResetsTheTrace() {
    let buffer = UntypeWaveformBuffer(duration: 1)
    buffer.configure(sampleRate: 16_000)
    buffer.append(pcm: pcm16(Array(repeating: 30_000, count: 160)), at: 0)
    buffer.clear()
    #expect(buffer.window(count: 20, at: 1).allSatisfy { $0 == 0 })
}

@Test func waveformGainLiftsQuietSpeechButCapsSilence() {
    #expect(abs(UntypeWaveform.gain(forPeak: 0.1) - 9.2) < 0.001)
    #expect(UntypeWaveform.gain(forPeak: 0) == 14)
    #expect(UntypeWaveform.gain(forPeak: 0.001) == 14)
    #expect(abs(UntypeWaveform.gain(forPeak: 0.92) - 1) < 0.001)
}

@Test func waveformGainSmoothingDropsFasterThanItRises() {
    let drop = 10 - UntypeWaveform.smoothed(previous: 10, target: 1, elapsed: 1.0 / 60.0)
    let rise = UntypeWaveform.smoothed(previous: 1, target: 10, elapsed: 1.0 / 60.0) - 1
    #expect(drop > rise)
    #expect(UntypeWaveform.smoothed(previous: 3, target: 9, elapsed: 0) == 3)
}
