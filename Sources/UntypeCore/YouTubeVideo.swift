import Foundation

/// What untype reads of a YouTube video without downloading it (plan-080):
/// the metadata and the caption tracks, through YouTube's player API (the
/// request the YouTube Android app makes). Works the same on the Mac and the
/// iPhone. Captions are read only for a video the user asked for: YouTube
/// blocks every caption route for hours when they are read in bulk.
public enum YouTubeVideo {
    public static let playerURL = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
    static let clientName = "ANDROID"
    static let clientVersion = "20.10.38"
    static let userAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip"

    /// The 11-character id of a YouTube address (watch, youtu.be, shorts,
    /// embed, live) or of a bare id; nil when there is none.
    public static func videoID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?:v=|youtu\.be/|shorts/|embed/|live/)([A-Za-z0-9_-]{11})(?![A-Za-z0-9_-])"#,
            #"^([A-Za-z0-9_-]{11})$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let range = Range(match.range(at: 1), in: trimmed) else {
                continue
            }
            return String(trimmed[range])
        }
        return nil
    }

    public static func watchURL(_ id: String, at seconds: Int? = nil) -> String {
        "https://www.youtube.com/watch?v=\(id)" + (seconds.map { "&t=\(max(0, $0))s" } ?? "")
    }

    /// The video's metadata and caption tracks.
    public static func fetch(_ id: String, session: URLSession = .shared) async throws -> (VideoInfo, [YouTubeCaptionTrack]) {
        var request = URLRequest(url: playerURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "context": ["client": [
                "clientName": clientName, "clientVersion": clientVersion, "hl": "en",
                "androidSdkVersion": 30, "osName": "Android", "osVersion": "11"
            ]],
            "videoId": id,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw VideoDigestError.source("YouTube answered HTTP \(status) for the video's details.")
        }
        return try parsePlayer(data, id: id)
    }

    static func parsePlayer(_ data: Data, id: String) throws -> (VideoInfo, [YouTubeCaptionTrack]) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VideoDigestError.source("YouTube's answer about the video was not readable.")
        }
        let playability = json["playabilityStatus"] as? [String: Any]
        let status = playability?["status"] as? String ?? "?"
        guard status == "OK" else {
            let reason = playability?["reason"] as? String ?? status
            throw VideoDigestError.source("YouTube does not play this video here: \(reason)")
        }
        let details = json["videoDetails"] as? [String: Any] ?? [:]
        let description = details["shortDescription"] as? String ?? ""
        let info = VideoInfo(
            id: id,
            url: watchURL(id),
            title: details["title"] as? String ?? id,
            channel: details["author"] as? String ?? "",
            durationSeconds: Int(details["lengthSeconds"] as? String ?? "") ?? 0,
            description: description,
            chapters: VideoInfo.chapters(in: description),
            thumbnailURL: "https://img.youtube.com/vi/\(id)/hqdefault.jpg",
            spokenLanguage: originalAudioLanguage(json)
        )
        let renderer = (json["captions"] as? [String: Any])?["playerCaptionsTracklistRenderer"] as? [String: Any]
        let tracks = (renderer?["captionTracks"] as? [[String: Any]] ?? []).compactMap { track -> YouTubeCaptionTrack? in
            guard let base = track["baseUrl"] as? String, let language = track["languageCode"] as? String else {
                return nil
            }
            return YouTubeCaptionTrack(
                language: language,
                isAutomatic: (track["kind"] as? String) == "asr",
                url: base.replacingOccurrences(of: "&fmt=srv3", with: "")
            )
        }
        return (info, tracks)
    }

    /// The language of the video's own audio: a video YouTube dubbed into
    /// other languages has one audio track per language, the original one
    /// marked as the default (`en-US.4`, "English (US) original").
    static func originalAudioLanguage(_ json: [String: Any]) -> String? {
        let formats = (json["streamingData"] as? [String: Any])?["adaptiveFormats"] as? [[String: Any]] ?? []
        for format in formats {
            guard let track = format["audioTrack"] as? [String: Any],
                  track["audioIsDefault"] as? Bool == true,
                  track["isAutoDubbed"] as? Bool != true,
                  let id = track["id"] as? String,
                  let language = id.split(separator: ".").first else {
                continue
            }
            return String(language)
        }
        return nil
    }

    /// The language spoken in the video: the original audio's, else that of
    /// the only automatic track (made from the audio), else of the only
    /// track, else nil. With dubbed audio there is an automatic track per
    /// dubbed language, so the first one says nothing.
    public static func spokenLanguage(_ tracks: [YouTubeCaptionTrack], original: String? = nil) -> String? {
        if let original {
            return original
        }
        let automatic = tracks.filter(\.isAutomatic)
        if automatic.count == 1 {
            return automatic[0].language
        }
        return tracks.count == 1 ? tracks[0].language : nil
    }

    /// The track to read: in the spoken language, written by a person
    /// before automatic; without a known spoken language, a written track
    /// before an automatic one. Never a track of a dubbed language.
    public static func bestTrack(_ tracks: [YouTubeCaptionTrack], original: String? = nil) -> YouTubeCaptionTrack? {
        if let spoken = spokenLanguage(tracks, original: original).map(baseLanguage) {
            let same = tracks.filter { baseLanguage($0.language) == spoken }
            return same.first(where: { !$0.isAutomatic }) ?? same.first
        }
        return tracks.first(where: { !$0.isAutomatic }) ?? (tracks.filter(\.isAutomatic).count == 1 ? tracks.first(where: \.isAutomatic) : nil)
    }

    static func baseLanguage(_ code: String) -> String {
        String(code.lowercased().split(separator: "-").first ?? Substring(code))
    }

    /// The lines of a caption track as segments of the video's transcript.
    public static func captions(_ track: YouTubeCaptionTrack, session: URLSession = .shared) async throws -> [MeetingSegment] {
        guard let url = URL(string: track.url) else {
            throw VideoDigestError.source("The caption address is not valid.")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw VideoDigestError.captionsBlocked(status)
        }
        return parseCaptions(String(decoding: data, as: UTF8.self), language: baseLanguage(track.language))
    }

    /// `<text start="1.36" dur="1.68">…</text>` lines (timedtext XML).
    static func parseCaptions(_ xml: String, language: String) -> [MeetingSegment] {
        guard let regex = try? NSRegularExpression(pattern: #"<text start="([\d.]+)"(?: dur="([\d.]+)")?[^>]*>(.*?)</text>"#, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            guard let startRange = Range(match.range(at: 1), in: xml),
                  let textRange = Range(match.range(at: 3), in: xml),
                  let start = Double(xml[startRange]) else {
                return nil
            }
            let duration = Range(match.range(at: 2), in: xml).flatMap { Double(xml[$0]) } ?? 0
            let text = unescape(unescape(String(xml[textRange])))
                .replacingOccurrences(of: "\n", with: " ")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else {
                return nil
            }
            return MeetingSegment(
                startMs: Int(start * 1000),
                endMs: Int((start + duration) * 1000),
                side: .call,
                speaker: nil,
                language: language,
                text: text
            )
        }
    }

    static func unescape(_ text: String) -> String {
        guard text.contains("&") else {
            return text
        }
        var result = text
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") {
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let whole = Range(match.range, in: result),
                      let hexRange = Range(match.range(at: 1), in: result),
                      let digits = Range(match.range(at: 2), in: result),
                      let code = UInt32(result[digits], radix: result[hexRange].isEmpty ? 10 : 16),
                      let scalar = Unicode.Scalar(code) else {
                    continue
                }
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}

public struct YouTubeCaptionTrack: Codable, Sendable, Equatable {
    public var language: String
    /// Made by YouTube from the audio (`kind: asr`), not written by a person.
    public var isAutomatic: Bool
    public var url: String
}
