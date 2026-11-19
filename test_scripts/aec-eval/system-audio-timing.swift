import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

// Prints, for the system audio ScreenCaptureKit delivers, how late each
// buffer arrives after the time it carries (its presentation time).
final class Probe: NSObject, SCStreamOutput, SCStreamDelegate {
    var delays: [Double] = []
    var levels: [Double] = []
    var first: Double?
    var ptsList: [Double] = []
    var frameList: [Int] = []
    var stall = 0.0
    let started = ProcessInfo.processInfo.systemUptime

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        var level = -120.0
        if let block = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            if CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr, let pointer {
                let count = length / 4
                pointer.withMemoryRebound(to: Float.self, capacity: count) { samples in
                    var sum = 0.0
                    for index in 0..<count { sum += Double(samples[index]) * Double(samples[index]) }
                    level = 10 * log10(sum / Double(max(1, count)) + 1e-12)
                }
            }
        }
        if first == nil {
            first = now
            print(String(format: "first buffer %.3f s after start; pts %.3f, uptime %.3f, frames %d", now - started, pts, now, frames))
        }
        delays.append(now - pts)
        levels.append(level)
        ptsList.append(pts)
        frameList.append(frames)
        if stall > 0, delays.count == 100 {
            // A blocked delivery queue, as a busy app would have.
            Thread.sleep(forTimeInterval: stall)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("stopped: \(error.localizedDescription)")
    }
}

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "15") ?? 15
let probe = Probe()
probe.stall = Double(CommandLine.arguments.dropFirst(2).first ?? "0") ?? 0
let content: SCShareableContent
do {
    content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
} catch {
    print("no access to ScreenCaptureKit: \(error.localizedDescription)")
    exit(2)
}
guard let display = content.displays.first else { print("no display"); exit(2) }
let configuration = SCStreamConfiguration()
configuration.capturesAudio = true
configuration.excludesCurrentProcessAudio = true
configuration.sampleRate = 48_000
configuration.channelCount = 2
configuration.width = 2
configuration.height = 2
configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
configuration.queueDepth = 5
configuration.showsCursor = false
let stream = SCStream(filter: SCContentFilter(display: display, excludingApplications: [], exceptingWindows: []), configuration: configuration, delegate: probe)
try stream.addStreamOutput(probe, type: .audio, sampleHandlerQueue: DispatchQueue(label: "probe"))
try await stream.startCapture()
try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
try? await stream.stopCapture()
// Is the audio continuous by its own timestamps (no buffer lost, none repeated)?
var gaps = 0
var worst = 0.0
for index in 1..<max(1, probe.ptsList.count) {
    let expected = probe.ptsList[index - 1] + Double(probe.frameList[index - 1]) / 48_000
    let error = probe.ptsList[index] - expected
    if abs(error) > 0.002 { gaps += 1 }
    worst = max(worst, abs(error))
}
print(String(format: "timestamps: %d breaks of more than 2 ms, largest %.1f ms; audio covered %.2f s", gaps, worst * 1000, (probe.ptsList.last ?? 0) - (probe.ptsList.first ?? 0)))
if probe.stall == 0, probe.ptsList.count > 1 {
    // Do the timestamps advance as fast as the samples are counted?
    let spanned = probe.ptsList.last! - probe.ptsList.first!
    let counted = Double(probe.frameList.dropLast().reduce(0, +)) / 48_000
    print(String(format: "over %.1f s the timestamps advance %.3f ms more than the audio counted (%.0f ppm)", counted, (spanned - counted) * 1000, (spanned - counted) / counted * 1_000_000))
}
if probe.stall == 0, seconds >= 120 {
    // Does the timestamps' clock drift against the system clock? The
    // smallest delivery delay per minute shows it (a steady change is drift).
    let perMinute = Int(60 / 0.02)
    var floors: [String] = []
    var start = 0
    while start + perMinute <= probe.delays.count {
        floors.append(String(format: "%.2f", probe.delays[start..<start + perMinute].min()! * 1000))
        start += perMinute
    }
    print("smallest arrival minus presentation time per minute (ms): \(floors.joined(separator: " "))")
}
if probe.stall > 0 {
    let after = probe.delays[100..<min(probe.delays.count, 112)].map { String(format: "%.0f", $0 * 1000) }.joined(separator: " ")
    print("arrival minus presentation time of the 12 buffers after the stall (ms): \(after)")
    print(String(format: "last buffer: %.0f ms", probe.delays.last! * 1000))
}
let delays = probe.delays.sorted()
guard !delays.isEmpty else { print("no audio buffers in \(seconds) s"); exit(1) }
let loud = probe.levels.filter { $0 > -60 }.count
print(String(format: "%d buffers in %.0f s (%d with sound); arrival minus presentation time: min %.0f ms, median %.0f ms, max %.0f ms",
             delays.count, seconds, loud, delays.first! * 1000, delays[delays.count / 2] * 1000, delays.last! * 1000))
