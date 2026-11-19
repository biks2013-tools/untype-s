import AVFoundation
import Foundation

// Prints, for the microphone as the app captures it (AVAudioEngine input tap,
// no voice processing), whether each buffer carries a valid host time, how
// late it arrives after that time, and whether the times are continuous.
//
//   swiftc -O microphone-timing.swift -o microphone-timing && ./microphone-timing [seconds]
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "10") ?? 10

// Is the host-time clock the clock of ProcessInfo.systemUptime?
let clockOffset = AVAudioTime.seconds(forHostTime: mach_absolute_time()) - ProcessInfo.processInfo.systemUptime
print(String(format: "host-time clock minus systemUptime: %.6f s", clockOffset))

final class Collector: @unchecked Sendable {
    let lock = NSLock()
    var delays: [Double] = []
    var starts: [Double] = []
    var lengths: [Double] = []
    var invalid = 0
}
let collector = Collector()
let engine = AVAudioEngine()
let input = engine.inputNode
let format = input.outputFormat(forBus: 0)
print("input format: \(format)")
input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, when in
    let now = ProcessInfo.processInfo.systemUptime
    collector.lock.lock()
    defer { collector.lock.unlock() }
    guard when.isHostTimeValid else {
        collector.invalid += 1
        return
    }
    let start = AVAudioTime.seconds(forHostTime: when.hostTime)
    collector.delays.append(now - start)
    collector.starts.append(start)
    collector.lengths.append(Double(buffer.frameLength) / buffer.format.sampleRate)
}
do {
    try engine.start()
} catch {
    print("microphone did not start: \(error.localizedDescription)")
    exit(2)
}
Thread.sleep(forTimeInterval: seconds)
engine.stop()
input.removeTap(onBus: 0)

collector.lock.lock()
let delays = collector.delays.sorted()
guard !delays.isEmpty else {
    print("no buffers with a valid host time (\(collector.invalid) without)")
    exit(1)
}
var breaks = 0
var worst = 0.0
for index in 1..<collector.starts.count {
    let error = collector.starts[index] - (collector.starts[index - 1] + collector.lengths[index - 1])
    if abs(error) > 0.002 { breaks += 1 }
    worst = max(worst, abs(error))
}
print(String(format: "%d buffers of %.1f ms, %d without a host time; arrival minus host time: min %.1f ms, median %.1f ms, max %.1f ms",
             delays.count, collector.lengths[0] * 1000, collector.invalid, delays.first! * 1000, delays[delays.count / 2] * 1000, delays.last! * 1000))
print(String(format: "host times: %d breaks of more than 2 ms, largest %.2f ms", breaks, worst * 1000))
// Do the host times advance as fast as the samples are counted?
let spanned = collector.starts.last! - collector.starts.first!
let counted = collector.lengths.dropLast().reduce(0, +)
print(String(format: "over %.1f s the host times advance %.3f ms more than the audio counted (%.0f ppm)", counted, (spanned - counted) * 1000, (spanned - counted) / counted * 1_000_000))
