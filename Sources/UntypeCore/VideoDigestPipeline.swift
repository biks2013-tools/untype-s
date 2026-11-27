import CoreGraphics
import Foundation
import ImageIO

/// What a device can fetch of a video beyond its captions: the Mac (yt-dlp,
/// ffmpeg) both audio and screenshots; the iPhone neither (YouTube refuses
/// full downloads there, plan-080 spikes 1 and 2).
public protocol VideoMediaSource: Sendable {
    var canDownloadAudio: Bool { get }
    var canTakeScreenshots: Bool { get }
    /// The video's audio as an `.m4a` file at `destination`.
    func downloadAudio(_ video: VideoInfo, to destination: URL) async throws
    /// JPEG frames of the video around `seconds` (a few seconds before to
    /// some twenty after: a slide is often shown after it is announced),
    /// in time order.
    func frames(_ video: VideoInfo, around seconds: Int) async throws -> [Data]
}

/// What the device cannot do.
public struct CaptionsOnlyMediaSource: VideoMediaSource {
    public init() {}
    public var canDownloadAudio: Bool { false }
    public var canTakeScreenshots: Bool { false }
    public func downloadAudio(_ video: VideoInfo, to destination: URL) async throws {
        throw VideoDigestError.noTranscript("This video has no captions, and its audio can be downloaded only on the Mac. Send it to the Mac instead.")
    }
    public func frames(_ video: VideoInfo, around seconds: Int) async throws -> [Data] {
        throw VideoDigestError.source("Screenshots are taken on the Mac.")
    }
}

/// The files of one digested video, in the layout of a recording so untype
/// studio opens it (when it has audio) and everything the digest made beside it:
///
///     <title>-recording-2026-11-27-10-30/
///       <stem>.video.json                 the request, the video, the stages done
///       <stem>.m4a                        the audio (Mac, or when no captions)
///       <stem>.segments.jsonl             the transcript (untype's segments)
///       <stem>.system.transcript.jsonl    the same in ntakker's format (studio)
///       <stem>.transcript.txt             `[00:01:05] Speaker 1 [en]: …`
///       <stem>.studio.json                audioStart, exact timing
///       <stem>.digest.json                the model's digest
///       <stem>.digest.html / .digest.docx
///       screenshots/thumbnail.jpg, screenshots/01-12-05.jpg, …
public struct VideoDigestFolder: Sendable {
    public let url: URL
    public let names: MeetingFileNames

    public init(url: URL) throws {
        guard let stem = MeetingNaming.stem(of: url.lastPathComponent) else {
            throw VideoDigestError.output("\(url.lastPathComponent) is not a video digest folder.")
        }
        self.url = url
        names = MeetingFileNames(stem: stem)
    }

    /// A new folder in `library` named after the video.
    public static func create(in library: URL, title: String, start: Date) throws -> VideoDigestFolder {
        let stem = MeetingFileNames(start: start).stem
        let base = MeetingNaming.folderName(current: stem, title: title)
        var url = library.appendingPathComponent(base, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = library.appendingPathComponent("\(base) (\(counter))", isDirectory: true)
            counter += 1
        }
        do {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
        } catch {
            throw VideoDigestError.output(error.localizedDescription)
        }
        return try VideoDigestFolder(url: url)
    }

    public func file(_ suffix: String) -> URL { url.appendingPathComponent(names.stem + suffix) }
    public var job: URL { file(".video.json") }
    public var audio: URL { url.appendingPathComponent(names.mixedAudio) }
    public var segments: URL { url.appendingPathComponent(names.segments) }
    public var digest: URL { file(".digest.json") }
    public var html: URL { file(".digest.html") }
    public var docx: URL { file(".digest.docx") }
    public var screenshots: URL { url.appendingPathComponent("screenshots", isDirectory: true) }

    func exists(_ file: URL) -> Bool { FileManager.default.fileExists(atPath: file.path) }
}

/// The state of a digest, kept in `<stem>.video.json`.
public struct VideoDigestJob: Codable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable {
        case started, transcribed, analyzed, screenshots, done
    }

    public var request: VideoDigestRequest
    public var video: VideoInfo?
    public var source: VideoTranscriptSource?
    public var stage: Stage
    public var error: String?
    /// Where it was made: "mac" / "iphone".
    public var device: String
    public var started: Date
    public var updated: Date
}

/// Runs a digest from the address to the documents. Every stage is written
/// to the folder before the next one starts, so `resume` continues a digest
/// that was stopped (an iPhone app sent to the background, a Mac restart).
public struct VideoDigestPipeline: Sendable {
    public let media: VideoMediaSource
    public let analyzer: VideoDigestAnalyzer
    /// Soniox, for videos without captions (nil: not available here).
    public let transcriber: SonioxFileTranscriber?
    public let device: String
    public let onEvent: @Sendable (String) -> Void

    public init(media: VideoMediaSource, analyzer: VideoDigestAnalyzer, transcriber: SonioxFileTranscriber?, device: String, onEvent: @escaping @Sendable (String) -> Void = { _ in }) {
        self.media = media
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.device = device
        self.onEvent = onEvent
    }

    /// A new digest in `library`; returns its folder.
    public func run(_ request: VideoDigestRequest, library: URL, progress: @escaping @Sendable (String) -> Void) async throws -> VideoDigestFolder {
        guard let id = YouTubeVideo.videoID(from: request.url) else {
            throw VideoDigestError.notAVideo(request.url)
        }
        progress("Reading the video's details")
        let (video, tracks) = try await YouTubeVideo.fetch(id)
        let now = Date()
        let folder = try VideoDigestFolder.create(in: library, title: video.title, start: now)
        var job = VideoDigestJob(request: request, video: video, source: nil, stage: .started, error: nil, device: device, started: now, updated: now)
        try save(job, folder)
        onEvent("video digest started: \(video.durationSeconds) s video, \(tracks.count) caption tracks")
        return try await continueJob(&job, folder: folder, tracks: tracks, progress: progress)
    }

    /// Continues a digest that stopped.
    public func resume(_ folder: VideoDigestFolder, progress: @escaping @Sendable (String) -> Void) async throws -> VideoDigestFolder {
        var job = try Self.job(folder)
        let tracks: [YouTubeCaptionTrack]
        if job.stage == .started || job.video == nil {
            guard let id = YouTubeVideo.videoID(from: job.request.url) else {
                throw VideoDigestError.notAVideo(job.request.url)
            }
            let fetched = try await YouTubeVideo.fetch(id)
            job.video = fetched.0
            tracks = fetched.1
        } else {
            tracks = []
        }
        return try await continueJob(&job, folder: folder, tracks: tracks, progress: progress)
    }

    public static func job(_ folder: VideoDigestFolder) throws -> VideoDigestJob {
        do {
            return try decoder.decode(VideoDigestJob.self, from: Data(contentsOf: folder.job))
        } catch {
            throw VideoDigestError.output("The digest's state could not be read: \(error.localizedDescription)")
        }
    }

    private func continueJob(_ job: inout VideoDigestJob, folder: VideoDigestFolder, tracks: [YouTubeCaptionTrack], progress: @escaping @Sendable (String) -> Void) async throws -> VideoDigestFolder {
        do {
            guard let video = job.video else {
                throw VideoDigestError.source("The video's details are missing.")
            }
            // 1. Transcript.
            var segments = Self.readSegments(folder)
            if segments.isEmpty {
                let (made, source) = try await transcript(video, tracks: tracks, folder: folder, progress: progress)
                segments = made
                job.source = source
                try writeTranscript(segments, video: video, folder: folder, exact: source != .soniox || folder.exists(folder.audio), start: job.started)
                job.stage = .transcribed
                try save(job, folder)
                onEvent("video digest: transcript of \(segments.count) lines (\(source.rawValue))")
            } else if media.canDownloadAudio, !folder.exists(folder.audio) {
                // Made on the iPhone from captions: the Mac adds the audio, so studio opens it.
                progress("Downloading the audio")
                try? await media.downloadAudio(video, to: folder.audio)
            }
            let source = job.source ?? .captions

            // 2. Analysis.
            var analysis: VideoDigestAnalysis
            if let saved = try? Self.decoder.decode(VideoDigestAnalysis.self, from: Data(contentsOf: folder.digest)) {
                analysis = saved
            } else {
                let language = job.request.language
                    ?? VideoDigestAnalyzer.languageName(video.spokenLanguage ?? Self.spokenLanguage(segments))
                    ?? "the language spoken in the video"
                analysis = try await analyzer.analyze(video: video, transcript: segments, source: source, language: language, progress: progress)
                try Self.encoder.encode(analysis).write(to: folder.digest, options: .atomic)
                job.stage = .analyzed
                try save(job, folder)
                onEvent("video digest: \(analysis.keyPoints.count) key points, \(analysis.sections.count) sections, \(analysis.moments.count) moments")
            }

            // 3. Screenshots.
            var images: [String: Data] = [:]
            if media.canTakeScreenshots {
                for index in analysis.moments.indices {
                    let moment = analysis.moments[index]
                    let path = "screenshots/" + String(format: "%02d-%@.jpg", index + 1, VideoDigestTime.label(moment.time).replacingOccurrences(of: ":", with: "-"))
                    let file = folder.url.appendingPathComponent(path)
                    if !folder.exists(file) {
                        progress("Screenshot \(index + 1) of \(analysis.moments.count)")
                        do {
                            let frames = try await media.frames(video, around: moment.time)
                            let chosen = await choose(frames, for: moment)
                            try chosen.write(to: file, options: .atomic)
                        } catch {
                            onEvent("video digest: screenshot \(index + 1) failed: \(error.localizedDescription)")
                            continue
                        }
                    }
                    analysis.moments[index].screenshot = path
                }
                try Self.encoder.encode(analysis).write(to: folder.digest, options: .atomic)
                job.stage = .screenshots
                try save(job, folder)
            }
            for moment in analysis.moments {
                if let path = moment.screenshot, let data = try? Data(contentsOf: folder.url.appendingPathComponent(path)) {
                    images[path] = Self.forDocument(data) ?? data
                }
            }

            // 4. Documents.
            progress("Writing the documents")
            let thumbnail = try await thumbnail(video, folder: folder)
            let document = VideoDigestDocument(video: video, analysis: analysis, source: source, images: images, thumbnail: thumbnail)
            try Data(document.html().utf8).write(to: folder.html, options: .atomic)
            if job.request.docx {
                try document.docx().write(to: folder.docx, options: .atomic)
            }
            job.stage = .done
            job.error = nil
            try save(job, folder)
            onEvent("video digest done: \(images.count) screenshots, docx \(job.request.docx)")
            return folder
        } catch {
            // The stage stays where it got to: `resume` goes on from there.
            job.error = error.localizedDescription
            try? save(job, folder)
            onEvent("video digest stopped: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Stages

    private func transcript(_ video: VideoInfo, tracks: [YouTubeCaptionTrack], folder: VideoDigestFolder, progress: @escaping @Sendable (String) -> Void) async throws -> ([MeetingSegment], VideoTranscriptSource) {
        if let track = YouTubeVideo.bestTrack(tracks, original: video.spokenLanguage) {
            progress("Reading the captions")
            do {
                let lines = try await YouTubeVideo.captions(track)
                if !lines.isEmpty {
                    if media.canDownloadAudio {
                        progress("Downloading the audio")
                        try? await media.downloadAudio(video, to: folder.audio)
                    }
                    return (lines, track.isAutomatic ? .automaticCaptions : .captions)
                }
            } catch VideoDigestError.captionsBlocked(let status) {
                onEvent("video digest: captions refused (HTTP \(status)); transcribing the audio")
            }
        }
        guard media.canDownloadAudio else {
            throw VideoDigestError.noTranscript("This video has no usable captions, and its audio can be downloaded only on the Mac. Send it to the Mac instead.")
        }
        guard let transcriber else {
            throw VideoDigestError.configuration("The video has no usable captions, and no Soniox key is set to transcribe its audio.")
        }
        progress("Downloading the audio")
        try await media.downloadAudio(video, to: folder.audio)
        let segments = try await transcriber.transcribe(folder.audio, progress: progress)
        guard !segments.isEmpty else {
            throw VideoDigestError.noTranscript("No speech was found in the video's audio.")
        }
        return (segments, .soniox)
    }

    /// The frame that shows the moment: chosen by the model from a numbered
    /// contact sheet of the candidates; the sharpest when it cannot choose.
    private func choose(_ frames: [Data], for moment: VideoDigestAnalysis.Moment) async -> Data {
        let usable = frames.filter { Self.sharpness($0) > 2 }
        let candidates = usable.isEmpty ? frames : usable
        guard candidates.count > 1 else {
            return candidates.first ?? Data()
        }
        let sharpest = candidates.max { Self.sharpness($0) < Self.sharpness($1) } ?? candidates[0]
        guard let sheet = Self.contactSheet(candidates),
              let index = await analyzer.chooseFrame(sheet: sheet, count: candidates.count, moment: moment),
              candidates.indices.contains(index) else {
            onEvent("video digest: frame for a moment chosen by sharpness")
            return sharpest
        }
        return candidates[index]
    }

    /// The frames side by side, numbered from 1, four to a row.
    static func contactSheet(_ frames: [Data]) -> LLMImageAttachment? {
        let cellWidth = 480, cellHeight = 270, columns = min(4, frames.count)
        let rows = (frames.count + columns - 1) / columns
        let width = cellWidth * columns, height = cellHeight * rows
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (index, data) in frames.enumerated() {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let column = index % columns, row = index / columns
            let cell = CGRect(x: column * cellWidth, y: height - (row + 1) * cellHeight, width: cellWidth, height: cellHeight)
            context.draw(image, in: cell.insetBy(dx: 3, dy: 3))
            let label = String(index + 1)
            let box = CGRect(x: cell.minX + 8, y: cell.maxY - 52, width: 30 * CGFloat(label.count) + 14, height: 44)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
            context.fill(box)
            drawDigits(label, in: context, at: CGPoint(x: box.minX + 7, y: box.minY + 6))
        }
        guard let image = context.makeImage(), let jpeg = jpeg(image, quality: 0.8) else {
            return nil
        }
        return LLMImageAttachment(data: jpeg, mediaType: "image/jpeg", pixelWidth: width, pixelHeight: height)
    }

    /// White seven-segment digits (no fonts needed, the same on macOS and iOS).
    private static func drawDigits(_ text: String, in context: CGContext, at origin: CGPoint) {
        let map: [Character: String] = ["0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"]
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(5)
        context.setLineCap(.round)
        let w: CGFloat = 18, h: CGFloat = 32
        for (offset, character) in text.enumerated() {
            let x = origin.x + CGFloat(offset) * 30, y = origin.y
            let segments: [Character: (CGPoint, CGPoint)] = [
                "a": (CGPoint(x: x, y: y + h), CGPoint(x: x + w, y: y + h)),
                "b": (CGPoint(x: x + w, y: y + h), CGPoint(x: x + w, y: y + h / 2)),
                "c": (CGPoint(x: x + w, y: y + h / 2), CGPoint(x: x + w, y: y)),
                "d": (CGPoint(x: x, y: y), CGPoint(x: x + w, y: y)),
                "e": (CGPoint(x: x, y: y + h / 2), CGPoint(x: x, y: y)),
                "f": (CGPoint(x: x, y: y + h), CGPoint(x: x, y: y + h / 2)),
                "g": (CGPoint(x: x, y: y + h / 2), CGPoint(x: x + w, y: y + h / 2))
            ]
            for segment in map[character] ?? "" {
                guard let (from, to) = segments[segment] else { continue }
                context.move(to: from)
                context.addLine(to: to)
            }
            context.strokePath()
        }
    }

    private func writeTranscript(_ segments: [MeetingSegment], video: VideoInfo, folder: VideoDigestFolder, exact: Bool, start: Date) throws {
        let ordered = MeetingTranscriptFormat.ordered(segments)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let jsonl = ordered.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
        try jsonl.write(to: folder.segments, atomically: true, encoding: .utf8)
        try (ordered.map(MeetingTranscriptFormat.originalLine).joined(separator: "\n") + "\n")
            .write(to: folder.url.appendingPathComponent(folder.names.mainTranscript), atomically: true, encoding: .utf8)
        try MeetingSidecarLine.file(ordered, side: .call, meetingStart: start)
            .write(to: folder.url.appendingPathComponent(folder.names.systemTranscript), atomically: true, encoding: .utf8)
        // Times are positions in the video's audio, which starts at `start`.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let studio: [String: Any] = [
            "version": 1,
            "audioStart": formatter.string(from: start),
            "exactTimingTranscripts": exact ? [folder.names.systemTranscript] : []
        ]
        try JSONSerialization.data(withJSONObject: studio, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.url.appendingPathComponent(folder.names.studioMetadata), options: .atomic)
    }

    private func thumbnail(_ video: VideoInfo, folder: VideoDigestFolder) async throws -> Data? {
        let file = folder.screenshots.appendingPathComponent("thumbnail.jpg")
        if let data = try? Data(contentsOf: file) {
            return data
        }
        for name in ["maxresdefault", "hqdefault"] {
            guard let url = URL(string: "https://img.youtube.com/vi/\(video.id)/\(name).jpg"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                continue
            }
            try? data.write(to: file, options: .atomic)
            return data
        }
        return nil
    }

    private func save(_ job: VideoDigestJob, _ folder: VideoDigestFolder) throws {
        var job = job
        job.updated = Date()
        do {
            try Self.encoder.encode(job).write(to: folder.job, options: .atomic)
        } catch {
            throw VideoDigestError.output(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    static func readSegments(_ folder: VideoDigestFolder) -> [MeetingSegment] {
        guard let text = try? String(contentsOf: folder.segments, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(MeetingSegment.self, from: Data($0.utf8)) }
    }

    static func spokenLanguage(_ segments: [MeetingSegment]) -> String? {
        Dictionary(grouping: segments.compactMap(\.language), by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// A copy at most 1280 px wide, JPEG 0.72, for embedding.
    static func forDocument(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1280,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else {
            return nil
        }
        return jpeg(image, quality: 0.72)
    }

    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return out as Data
    }

    /// How sharp an image is: the mean squared difference of neighbouring
    /// pixels of a 320 px grey copy (a frame in a transition or blurred by
    /// motion scores low).
    public static func sharpness(_ data: Data) -> Double {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320
              ] as CFDictionary) else {
            return 0
        }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0.0
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let p = Double(pixels[y * width + x])
                let dx = p - Double(pixels[y * width + x + 1])
                let dy = p - Double(pixels[(y + 1) * width + x])
                total += dx * dx + dy * dy
            }
        }
        return total / Double(max(1, (width - 1) * (height - 1)))
    }
}
