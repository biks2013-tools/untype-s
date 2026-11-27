import Foundation

/// Transcribes a recorded audio file with Soniox's async API (plan-080):
/// upload, create a transcription, wait, read the tokens, then delete both
/// the transcription and the file (they stay on the account otherwise).
public struct SonioxFileTranscriber: Sendable {
    public static let baseURL = URL(string: "https://api.soniox.com")!
    /// `stt-async-v5` is removed on 2026-12-15.
    public static let model = "stt-async-v6"

    public let apiKey: String
    public let languageHints: [String]
    public let terms: [String]

    public init(apiKey: String, languageHints: [String], terms: [String] = []) {
        self.apiKey = apiKey
        self.languageHints = languageHints
        self.terms = terms
    }

    /// The transcript as segments (speakers told apart); `progress` gets
    /// short status lines.
    public func transcribe(_ file: URL, session: URLSession = .shared, progress: @Sendable (String) -> Void = { _ in }) async throws -> [MeetingSegment] {
        progress("Uploading the audio to Soniox")
        let fileID = try await upload(file, session: session)
        var transcriptionID: String?
        do {
            let segments = try await run(fileID: fileID, session: session, progress: progress) { transcriptionID = $0 }
            await cleanUp(fileID: fileID, transcriptionID: transcriptionID, session: session)
            return segments
        } catch {
            await cleanUp(fileID: fileID, transcriptionID: transcriptionID, session: session)
            throw error
        }
    }

    private func cleanUp(fileID: String, transcriptionID: String?, session: URLSession) async {
        if let transcriptionID {
            _ = try? await call("DELETE", "/v1/transcriptions/\(transcriptionID)", session: session)
        }
        _ = try? await call("DELETE", "/v1/files/\(fileID)", session: session)
    }

    private func run(fileID: String, session: URLSession, progress: @Sendable (String) -> Void, created onCreated: (String) -> Void) async throws -> [MeetingSegment] {
        var config: [String: Any] = [
            "model": Self.model,
            "file_id": fileID,
            "enable_language_identification": true,
            "enable_speaker_diarization": true,
            "client_reference_id": "untype-video-digest"
        ]
        if !languageHints.isEmpty {
            config["language_hints"] = languageHints
        }
        if !terms.isEmpty {
            config["context"] = ["terms": terms]
        }
        let created = try await call("POST", "/v1/transcriptions", json: config, session: session)
        guard let id = created["id"] as? String else {
            throw VideoDigestError.transcription("Soniox did not return a transcription id.")
        }
        onCreated(id)
        progress("Transcribing")
        var waited = 0.0
        while true {
            let status = try await call("GET", "/v1/transcriptions/\(id)", session: session)
            switch status["status"] as? String {
            case "completed":
                let transcript = try await call("GET", "/v1/transcriptions/\(id)/transcript", session: session)
                let tokens = MeetingToken.parse(transcript["tokens"] as? [[String: Any]] ?? [])
                return Self.segments(tokens.map { var token = $0; token.isFinal = true; return token })
            case "error":
                throw VideoDigestError.transcription(status["error_message"] as? String ?? "Soniox reported an error.")
            default:
                let step = waited < 30 ? 1.0 : 3.0
                try await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                waited += step
                if waited > 3 * 3600 {
                    throw VideoDigestError.transcription("Soniox did not finish within three hours.")
                }
            }
        }
    }

    /// Segments from file tokens: a new segment at a new speaker, after a
    /// pause of 1.5 s, or after a sentence once it is 20 s long (the file API
    /// sends no end-of-utterance markers).
    public static func segments(_ tokens: [MeetingToken]) -> [MeetingSegment] {
        var result: [MeetingSegment] = []
        var current: [MeetingToken] = []
        func flush() {
            let text = current.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let start = current.compactMap(\.startMs).min() ?? 0
                let languages = current.compactMap(\.language)
                result.append(MeetingSegment(
                    startMs: start,
                    endMs: current.compactMap(\.endMs).max() ?? start,
                    side: .call,
                    speaker: current.compactMap(\.speaker).first,
                    language: Dictionary(grouping: languages, by: { $0 }).max { $0.value.count < $1.value.count }?.key,
                    text: text
                ))
            }
            current.removeAll()
        }
        for token in tokens where !token.isMarker {
            if let last = current.last {
                let speakerChanged = token.speaker != nil && last.speaker != nil && token.speaker != last.speaker
                let pause = (token.startMs ?? 0) - (last.endMs ?? 0) > 1_500
                let endsSentence = last.text.trimmingCharacters(in: .whitespaces).last.map { ".?!;…".contains($0) } ?? false
                let long = (last.endMs ?? 0) - (current.first?.startMs ?? 0) > 20_000
                if speakerChanged || pause || (endsSentence && long) {
                    flush()
                }
            }
            current.append(token)
        }
        flush()
        return result
    }

    private func upload(_ file: URL, session: URLSession) async throws -> String {
        let boundary = "untype-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(try Data(contentsOf: file))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/files"), timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, from: body)
        let object = try Self.object(data, response)
        guard let id = object["id"] as? String else {
            throw VideoDigestError.transcription("Soniox did not return a file id.")
        }
        return id
    }

    @discardableResult
    private func call(_ method: String, _ path: String, json: [String: Any]? = nil, session: URLSession) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: path, relativeTo: Self.baseURL)!, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await session.data(for: request)
        return try Self.object(data, response)
    }

    private static func object(_ data: Data, _ response: URLResponse) throws -> [String: Any] {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = object["message"] as? String ?? object["error_message"] as? String ?? "HTTP \(status)"
            throw VideoDigestError.transcription("Soniox: \(message)")
        }
        return object
    }
}
