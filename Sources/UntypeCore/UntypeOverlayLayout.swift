import AppKit
import Foundation

/// Geometry of the push-to-talk pill: fixed size, bottom-centred on the screen
/// under the mouse. The pill carries no text (dictated text goes straight to
/// the focused control), so its size never changes.
public struct UntypeOverlayLayout: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let bottomOffset: CGFloat

    public init(
        width: CGFloat = 260,
        height: CGFloat = 44,
        bottomOffset: CGFloat = 46
    ) {
        self.width = width
        self.height = height
        self.bottomOffset = bottomOffset
    }

    public func panelFrame(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY + bottomOffset,
            width: width,
            height: height
        )
    }
}

/// Maps microphone peaks to the pill's wave amplitude.
public enum UntypeWaveform {
    /// Smallest amplitude, so the wave stays visible during silence.
    public static let floorAmplitude = 0.06

    /// Speech peaks sit far below full scale; a square root lifts quiet speech
    /// into view while keeping louder speech taller.
    public static func amplitude(forPeak peak: Double) -> Double {
        let clamped = min(1, max(0, peak))
        return min(1, max(floorAmplitude, clamped.squareRoot() * 1.6))
    }

    /// Exponential smoothing per frame: quick to rise with the voice, slower
    /// to fall, so the wave does not flicker between syllables.
    public static func smoothed(previous: Double, target: Double, elapsed: TimeInterval) -> Double {
        let dt = min(0.1, max(0, elapsed))
        let rate = target > previous ? 18.0 : 6.0
        let alpha = 1 - exp(-rate * dt)
        return previous + (target - previous) * alpha
    }
}
