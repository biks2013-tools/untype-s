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

@Test func waveformAmplitudeKeepsAFloorDuringSilence() {
    #expect(UntypeWaveform.amplitude(forPeak: 0) == UntypeWaveform.floorAmplitude)
    #expect(UntypeWaveform.amplitude(forPeak: -1) == UntypeWaveform.floorAmplitude)
}

@Test func waveformAmplitudeGrowsWithPeakAndClampsAtOne() {
    let quiet = UntypeWaveform.amplitude(forPeak: 0.02)
    let speech = UntypeWaveform.amplitude(forPeak: 0.2)
    #expect(quiet > UntypeWaveform.floorAmplitude)
    #expect(speech > quiet)
    #expect(UntypeWaveform.amplitude(forPeak: 1) == 1)
    #expect(UntypeWaveform.amplitude(forPeak: 5) == 1)
}

@Test func waveformSmoothingRisesFasterThanItFalls() {
    let rise = UntypeWaveform.smoothed(previous: 0, target: 1, elapsed: 1.0 / 60.0)
    let fall = 1 - UntypeWaveform.smoothed(previous: 1, target: 0, elapsed: 1.0 / 60.0)
    #expect(rise > 0 && rise < 1)
    #expect(fall > 0 && fall < rise)
    #expect(UntypeWaveform.smoothed(previous: 0.3, target: 0.9, elapsed: 0) == 0.3)
}
