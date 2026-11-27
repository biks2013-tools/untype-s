#if os(macOS)
import Foundation

/// The video digest's settings on the Mac (plan-080), from the shell and
/// `~/.tool-agents/untype/.env`. None has a default: a missing one is named.
public struct VideoDigestMacSettings: Sendable, Equatable {
    public static let libraryKey = "UNTYPE_VIDEO_LIBRARY"
    public static let ytDlpKey = "UNTYPE_YTDLP_PATH"
    public static let ffmpegKey = "UNTYPE_FFMPEG_PATH"
    public static let denoKey = "UNTYPE_DENO_PATH"

    /// Where the video folders go (the user's choice: iCloud Drive/untype/Videos).
    public let library: URL
    public let ytDlp: URL
    public let ffmpeg: URL
    /// yt-dlp needs a JavaScript runtime for YouTube's challenges.
    public let deno: URL

    public init(library: URL, ytDlp: URL, ffmpeg: URL, deno: URL) {
        self.library = library
        self.ytDlp = ytDlp
        self.ffmpeg = ffmpeg
        self.deno = deno
    }

    public static func load(_ environment: [String: String]) throws -> VideoDigestMacSettings {
        var missing: [String] = []
        func path(_ key: String) -> URL? {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                missing.append(key)
                return nil
            }
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        let library = path(libraryKey), ytDlp = path(ytDlpKey), ffmpeg = path(ffmpegKey), deno = path(denoKey)
        guard let library, let ytDlp, let ffmpeg, let deno else {
            throw VideoDigestError.configuration("The video digest needs these settings in ~/.tool-agents/untype/.env: \(missing.joined(separator: ", ")). (yt-dlp, ffmpeg and deno: `brew install yt-dlp ffmpeg deno`, then their paths from `which`.)")
        }
        for (key, tool) in [(ytDlpKey, ytDlp), (ffmpegKey, ffmpeg), (denoKey, deno)] where !FileManager.default.isExecutableFile(atPath: tool.path) {
            throw VideoDigestError.configuration("\(key) is not a program: \(tool.path)")
        }
        return VideoDigestMacSettings(library: library, ytDlp: ytDlp, ffmpeg: ffmpeg, deno: deno)
    }
}

/// Audio and screenshots through yt-dlp and ffmpeg.
public struct YtDlpMediaSource: VideoMediaSource {
    public let settings: VideoDigestMacSettings

    public init(settings: VideoDigestMacSettings) {
        self.settings = settings
    }

    public var canDownloadAudio: Bool { true }
    public var canTakeScreenshots: Bool { true }

    public func downloadAudio(_ video: VideoInfo, to destination: URL) async throws {
        let work = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        try await run(settings.ytDlp, [
            "--no-update", "--no-playlist", "--quiet", "--no-warnings",
            "--ffmpeg-location", settings.ffmpeg.path,
            "-f", "bestaudio[ext=m4a]/bestaudio",
            "--remux-video", "m4a",
            "-o", work.appendingPathComponent("audio.%(ext)s").path,
            video.url
        ])
        guard let file = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "m4a" }) else {
            throw VideoDigestError.source("yt-dlp did not give an .m4a audio file.")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: file, to: destination)
    }

    /// About 24 s of the video around `seconds` (1080p at most), a frame
    /// every 3 s, at most 8.
    public func frames(_ video: VideoInfo, around seconds: Int) async throws -> [Data] {
        let work = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let from = max(0, seconds - 4)
        let to = video.durationSeconds > 0 ? min(video.durationSeconds, seconds + 20) : seconds + 20
        try await run(settings.ytDlp, [
            "--no-update", "--no-playlist", "--quiet", "--no-warnings",
            "--ffmpeg-location", settings.ffmpeg.path,
            "-f", "bv*[ext=mp4][height<=1080]/bv*[height<=1080]/b[height<=1080]",
            "--download-sections", "*\(from)-\(max(to, from + 2))",
            "-o", work.appendingPathComponent("clip.%(ext)s").path,
            video.url
        ])
        guard let clip = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent.hasPrefix("clip.") }) else {
            throw VideoDigestError.source("yt-dlp did not give the video at \(VideoDigestTime.label(seconds)).")
        }
        try await run(settings.ffmpeg, ["-v", "error", "-y", "-ss", "1", "-i", clip.path, "-vf", "fps=1/3", "-frames:v", "8", "-q:v", "2", work.appendingPathComponent("frame-%02d.jpg").path])
        let frames = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("frame-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? Data(contentsOf: $0) }
        guard !frames.isEmpty else {
            throw VideoDigestError.source("ffmpeg took no frame at \(VideoDigestTime.label(seconds)).")
        }
        return frames
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("untype-video-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs a tool and waits; its error output is in the error.
    private func run(_ tool: URL, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        // yt-dlp finds deno (and ffmpeg) on PATH; an app opened from the
        // Finder has no Homebrew folder there.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [settings.deno.deletingLastPathComponent().path, settings.ffmpeg.deletingLastPathComponent().path, "/usr/bin", "/bin"].joined(separator: ":")
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let last = output.split(separator: "\n").last.map(String.init) ?? "exit \(finished.terminationStatus)"
                    continuation.resume(throwing: VideoDigestError.source("\(tool.lastPathComponent): \(last)"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: VideoDigestError.configuration("\(tool.path) could not be started: \(error.localizedDescription)"))
            }
        }
    }
}
#endif
