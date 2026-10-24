import AppKit
import Foundation

/// Geometry of the push-to-talk overlay: fixed size, bottom-centred on the screen
/// under the mouse: the microphone trace with the R/T/C/I operator chips
/// under it. It carries no transcript text (dictated text goes straight to the
/// focused control), so its size never changes.
public struct UntypeOverlayLayout: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let bottomOffset: CGFloat

    public init(
        width: CGFloat = 180,
        height: CGFloat = 84,
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

/// Recent microphone samples for the push-to-talk oscilloscope. PCM16 mono
/// chunks are averaged down to `pointsPerSecond` points (a gentle low-pass that
/// keeps voice fundamentals) and kept in a ring of `duration` seconds.
/// Thread-safe: chunks arrive on the audio path, the overlay reads at 60 fps.
public final class UntypeWaveformBuffer: @unchecked Sendable {
    public static let pointsPerSecond = 2_000.0
    private let lock = NSLock()
    private var ring: [Float]
    private var total = 0
    private var decimation = 8
    private var pending: Float = 0
    private var pendingCount = 0
    private var lastAppendTime: TimeInterval = 0
    private var lastChunkPoints = 0

    public init(duration: TimeInterval = 1.0) {
        ring = Array(repeating: 0, count: max(64, Int(duration * Self.pointsPerSecond)))
    }

    public func configure(sampleRate: Int) {
        lock.lock()
        decimation = max(1, Int((Double(sampleRate) / Self.pointsPerSecond).rounded()))
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        for index in ring.indices { ring[index] = 0 }
        total = 0
        pending = 0
        pendingCount = 0
        lastChunkPoints = 0
        lock.unlock()
    }

    public func append(pcm: Data, at time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let before = total
        var index = pcm.startIndex
        while index + 1 < pcm.endIndex {
            let raw = UInt16(pcm[index]) | (UInt16(pcm[index + 1]) << 8)
            pending += Float(Int16(bitPattern: raw)) / 32_768
            pendingCount += 1
            if pendingCount == decimation {
                ring[total % ring.count] = pending / Float(decimation)
                total += 1
                pending = 0
                pendingCount = 0
            }
            index += 2
        }
        lastChunkPoints = total - before
        lastAppendTime = time
    }

    /// The `count` most recent points, delayed by one chunk and advanced by
    /// the time since that chunk arrived, so the trace scrolls continuously
    /// instead of jumping once per audio buffer.
    public func window(count: Int, at time: TimeInterval) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let count = min(count, ring.count - lastChunkPoints - 1)
        guard count > 0 else { return [] }
        let advance = min(Double(lastChunkPoints), max(0, time - lastAppendTime) * Self.pointsPerSecond)
        let end = total - lastChunkPoints + Int(advance)
        return (0..<count).map { offset in
            let position = end - count + offset
            return position < 0 ? 0 : ring[position % ring.count]
        }
    }
}

/// Oscilloscope scaling for the push-to-talk pill.
public enum UntypeWaveform {
    /// Gain that brings the window's peak to `target` height, capped so
    /// silence stays a small ripple instead of amplified noise.
    public static func gain(forPeak peak: Float, target: Float = 0.92, maxGain: Float = 14) -> Float {
        min(maxGain, target / max(peak, target / maxGain))
    }

    /// Exponential smoothing per frame: quick to lower the gain when the
    /// voice gets louder (no clipping), slower to raise it again.
    public static func smoothed(previous: Float, target: Float, elapsed: TimeInterval) -> Float {
        let dt = Float(min(0.1, max(0, elapsed)))
        let rate: Float = target < previous ? 25 : 4
        return previous + (target - previous) * (1 - exp(-rate * dt))
    }
}
