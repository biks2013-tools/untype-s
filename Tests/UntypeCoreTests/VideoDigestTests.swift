import CoreGraphics
import Foundation
import Testing
@testable import UntypeCore

@Test func youTubeVideoIDsFromEveryAddressForm() {
    #expect(YouTubeVideo.videoID(from: "https://www.youtube.com/watch?v=LCEmiRjPEtQ&t=30s") == "LCEmiRjPEtQ")
    #expect(YouTubeVideo.videoID(from: "https://youtu.be/LCEmiRjPEtQ?si=x") == "LCEmiRjPEtQ")
    #expect(YouTubeVideo.videoID(from: "https://www.youtube.com/shorts/LCEmiRjPEtQ") == "LCEmiRjPEtQ")
    #expect(YouTubeVideo.videoID(from: " LCEmiRjPEtQ ") == "LCEmiRjPEtQ")
    #expect(YouTubeVideo.videoID(from: "https://example.com/watch") == nil)
    #expect(YouTubeVideo.watchURL("LCEmiRjPEtQ", at: 90) == "https://www.youtube.com/watch?v=LCEmiRjPEtQ&t=90s")
}

@Test func captionLinesBecomeSegmentsWithEntitiesDecoded() {
    let xml = #"<transcript><text start="1.36" dur="1.68">It&amp;#39;s &quot;fine&quot;</text><text start="3.5" dur="2">a"# + "\n" + #"b</text><text start="6" dur="1"> </text></transcript>"#
    let segments = YouTubeVideo.parseCaptions(xml, language: "en")
    #expect(segments.count == 2)
    #expect(segments[0].text == "It's \"fine\"")
    #expect(segments[0].startMs == 1_360)
    #expect(segments[0].endMs == 3_040)
    #expect(segments[1].text == "a b")
    #expect(segments[1].side == .call)
}

@Test func theOriginalAudiosLanguageChoosesTheCaptionsOfADubbedVideo() {
    // A video YouTube dubbed: an automatic track per dubbed language, Arabic first.
    let tracks = [
        YouTubeCaptionTrack(language: "ar", isAutomatic: true, url: "a"),
        YouTubeCaptionTrack(language: "en", isAutomatic: true, url: "e"),
        YouTubeCaptionTrack(language: "de-DE", isAutomatic: true, url: "d")
    ]
    #expect(YouTubeVideo.bestTrack(tracks, original: "en-US")?.url == "e")
    // Without the original's language, an automatic track of many is not guessed.
    #expect(YouTubeVideo.bestTrack(tracks) == nil)
    // A written track in the spoken language beats the automatic one.
    let written = [YouTubeCaptionTrack(language: "en", isAutomatic: true, url: "auto"), YouTubeCaptionTrack(language: "en", isAutomatic: false, url: "manual"), YouTubeCaptionTrack(language: "de", isAutomatic: false, url: "de")]
    #expect(YouTubeVideo.bestTrack(written)?.url == "manual")
}

@Test func theOriginalAudioTrackIsReadFromThePlayerAnswer() throws {
    let json: [String: Any] = [
        "playabilityStatus": ["status": "OK"],
        "videoDetails": ["title": "T", "author": "C", "lengthSeconds": "120", "shortDescription": "0:00 Intro\n1:05 Main part\nhttps://github.com/x/y\nhttps://example.com/?utm_source=z"],
        "streamingData": ["adaptiveFormats": [
            ["audioTrack": ["id": "ar.10", "audioIsDefault": false, "isAutoDubbed": true]],
            ["audioTrack": ["id": "en-US.4", "audioIsDefault": true]]
        ]]
    ]
    let (video, tracks) = try YouTubeVideo.parsePlayer(JSONSerialization.data(withJSONObject: json), id: "abcdefghijk")
    #expect(video.spokenLanguage == "en-US")
    #expect(video.durationSeconds == 120)
    #expect(video.chapters == [VideoChapter(title: "Intro", start: 0), VideoChapter(title: "Main part", start: 65)])
    #expect(video.links == ["https://github.com/x/y"])
    #expect(tracks.isEmpty)
}

@Test func fileTranscriptTokensAreCutAtSpeakersPausesAndLongSentences() {
    func token(_ text: String, _ start: Int, _ end: Int, _ speaker: String) -> MeetingToken {
        MeetingToken(text: text, isFinal: true, speaker: speaker, language: "en", startMs: start, endMs: end)
    }
    let tokens = [
        token("Hello", 0, 400, "1"), token(" there.", 400, 800, "1"),
        token(" Hi", 900, 1_100, "2"),
        token(" again", 4_000, 4_300, "2")
    ]
    let segments = SonioxFileTranscriber.segments(tokens)
    #expect(segments.map(\.text) == ["Hello there.", "Hi", "again"])
    #expect(segments.map(\.speaker) == ["1", "2", "2"])
    #expect(segments[2].startMs == 4_000)
}

@Test func modelTimesBeyondTheVideoAreDroppedAndMomentsSpreadOut() {
    let video = VideoInfo(id: "abcdefghijk", url: "u", title: "T", channel: "C", durationSeconds: 600, description: "https://github.com/x/y", chapters: [], thumbnailURL: "t")
    let transcript = [100, 200, 300].map { MeetingSegment(startMs: $0 * 1000, endMs: $0 * 1000 + 5000, side: .call, speaker: nil, language: "en", text: "x") }
    let analysis = VideoDigestAnalysis(
        title: "T", standfirst: "S", language: "English", speakers: [],
        keyPoints: [.init(lead: "a", text: "b", time: 700), .init(lead: "c", text: "d", time: 50)],
        delivery: .init(summary: "", tone: "", structure: "", techniques: [], evidence: ""),
        sections: [.init(title: "late", start: 900, paragraphs: []), .init(title: "two", start: 200, paragraphs: []), .init(title: "one", start: 0, paragraphs: [])],
        quotes: [.init(text: "q", time: 9_999, speaker: nil, translation: nil)],
        moments: [.init(time: 205, title: "m1", why: "w", screenshot: nil), .init(time: 210, title: "too close", why: "w", screenshot: nil), .init(time: 650, title: "beyond", why: "w", screenshot: nil)],
        resources: [.init(title: "repo", url: "https://github.com/x/y"), .init(title: "made up", url: "https://invented.example")]
    )
    let result = VideoDigestAnalyzer.validated(analysis, video: video, transcript: transcript)
    #expect(result.keyPoints.map(\.time) == [nil, 50])
    #expect(result.sections.map(\.title) == ["one", "two"])
    #expect(result.quotes.isEmpty)
    #expect(result.moments.map(\.time) == [200])
    #expect(result.resources.map(\.title) == ["repo"])
}

@Test func theWordDocumentIsAValidZipWithItsParts() throws {
    let video = VideoInfo(id: "abcdefghijk", url: "https://www.youtube.com/watch?v=abcdefghijk", title: "T & <b>", channel: "C", durationSeconds: 60, description: "", chapters: [], thumbnailURL: "t")
    let analysis = VideoDigestAnalysis(
        title: "Title", standfirst: "S", language: "English", speakers: ["A"],
        keyPoints: [.init(lead: "Lead", text: "Text", time: 5)],
        delivery: .init(summary: "How", tone: "Calm", structure: "Linear", techniques: ["Story"], evidence: "None"),
        sections: [.init(title: "One", start: 0, paragraphs: ["P"])],
        quotes: [.init(text: "Q", time: 10, speaker: "A", translation: nil)],
        moments: [.init(time: 20, title: "M", why: "W", screenshot: nil)],
        resources: []
    )
    let document = VideoDigestDocument(video: video, analysis: analysis, source: .captions, images: [:], thumbnail: nil)
    let docx = try document.docx()
    #expect(docx.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
    let text = String(decoding: docx, as: UTF8.self)
    #expect(text.contains("word/document.xml"))
    #expect(text.contains("T &amp; &lt;b&gt;"))
    #expect(ZipStoreWriter.crc32(Data("123456789".utf8)) == 0xCBF43926)
    let html = document.html()
    #expect(html.contains("href=\"https://www.youtube.com/watch?v=abcdefghijk&amp;t=5s\""))
    #expect(html.contains("No screenshots"))
}

@Test func candidateFramesBecomeANumberedSheetFourToARow() throws {
    let context = try #require(CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
    let image = try #require(context.makeImage())
    let frame = try #require(VideoDigestPipeline.jpeg(image, quality: 0.8))
    let sheet = try #require(VideoDigestPipeline.contactSheet(Array(repeating: frame, count: 6)))
    #expect(sheet.pixelWidth == 4 * 480)
    #expect(sheet.pixelHeight == 2 * 270)
    #expect(sheet.mediaType == "image/jpeg")
}

#if os(macOS)
@Test func anInboxRequestIsClaimedOnceAndEndsInDoneOrFailed() throws {
    let library = FileManager.default.temporaryDirectory.appendingPathComponent("untype-inbox-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: library) }
    let request = VideoDigestInboxRequest(url: "https://youtu.be/LCEmiRjPEtQ", language: nil, docx: true, from: "iphone")
    try VideoDigestInbox.send(request, library: library)
    let waiting = VideoDigestInbox.waiting(library)
    #expect(waiting.count == 1)
    let claimed = try #require(VideoDigestInbox.claim(waiting[0]))
    #expect(claimed.0.id == request.id && claimed.0.url == request.url && claimed.0.docx && claimed.0.language == nil)
    // A second Mac finds nothing to claim.
    #expect(VideoDigestInbox.claim(waiting[0]) == nil)
    #expect(VideoDigestInbox.waiting(library).isEmpty)
    VideoDigestInbox.finish(claimed.0, claimed: claimed.1, folder: library.appendingPathComponent("T-recording-2026-11-27-10-55"), error: nil)
    let done = VideoDigestInbox.folder(library).appendingPathComponent("done/\(request.id).json")
    let result = try VideoDigestInbox.decoder.decode(VideoDigestInboxRequest.self, from: Data(contentsOf: done))
    #expect(result.folder == "T-recording-2026-11-27-10-55")
    #expect(!FileManager.default.fileExists(atPath: claimed.1.path))
}
#endif
