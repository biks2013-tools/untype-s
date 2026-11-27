import Foundation

/// Reads a video's transcript with a language model and returns the digest
/// (plan-080). A long transcript is read in parts (notes per part, then the
/// digest from the notes), so no single call runs into the model's limits.
/// Every time the model gives is checked against the video's length.
public struct VideoDigestAnalyzer: Sendable {
    /// Characters of transcript read in one call.
    public static let partCharacters = 60_000

    public let llm: LLMConfig

    /// `llm`: the model and keys (Refine's on the Mac); the timeout and output
    /// cap of the digest's calls are set here, for long answers.
    public init(llm: LLMConfig) {
        self.llm = llm
    }

    public func analyze(
        video: VideoInfo,
        transcript: [MeetingSegment],
        source: VideoTranscriptSource,
        language: String,
        progress: @Sendable (String) -> Void = { _ in }
    ) async throws -> VideoDigestAnalysis {
        let lines = Self.lines(transcript)
        guard !lines.isEmpty else {
            throw VideoDigestError.noTranscript("The video has no words to digest.")
        }
        let text = lines.joined(separator: "\n")
        let material: String
        if text.count <= Self.partCharacters {
            material = "TRANSCRIPT (\(source.description); [time] (speaker) words):\n" + text
        } else {
            let parts = MeetingTranslationChunks.chunks(lines, maxCharacters: Self.partCharacters, maxLines: .max)
            var notes: [String] = []
            for (index, part) in parts.enumerated() {
                progress("Reading part \(index + 1) of \(parts.count)")
                let answer = try await call(system: Self.notesPrompt, user: Self.header(video) + "\nPART \(index + 1) OF \(parts.count) OF THE TRANSCRIPT:\n" + part.joined(separator: "\n"))
                notes.append("NOTES ON PART \(index + 1) (\(part.first.flatMap(Self.timeOf) ?? "")–\(part.last.flatMap(Self.timeOf) ?? "")):\n" + answer)
            }
            material = "The transcript (\(source.description)) was too long to read at once; these are notes on its parts, in order, with times and verbatim quotes:\n\n" + notes.joined(separator: "\n\n")
        }
        progress("Writing the digest")
        let answer = try await call(system: Self.digestPrompt(language: language), user: Self.header(video) + "\n" + material)
        return try Self.validated(Self.parse(answer), video: video, transcript: transcript)
    }

    private func call(system: String, user: String) async throws -> String {
        let config = LLMConfig(
            enabled: true,
            provider: llm.provider,
            model: llm.model,
            systemPrompt: system,
            requestTimeoutMs: 300_000,
            providerConfig: llm.providerConfig,
            verbose: false,
            maxOutputTokens: 16_000,
            reasoningEffort: llm.reasoningEffort,
            streamingEnabled: llm.streamingEnabled
        )
        guard let client = try LLMRefinerFactory.makeTranslator(config: config, systemPrompt: system) else {
            throw VideoDigestError.configuration("No language model is configured for the digest.")
        }
        defer { client.dispose() }
        do {
            return try await client.refine(user)
        } catch {
            throw VideoDigestError.analysis(error.localizedDescription)
        }
    }

    /// Which of the numbered frames shows `moment` best (0-based); nil when
    /// the model cannot look at images or gives no number.
    public func chooseFrame(sheet: LLMImageAttachment, count: Int, moment: VideoDigestAnalysis.Moment) async -> Int? {
        let config = LLMConfig(
            enabled: true, provider: llm.provider, model: llm.model, systemPrompt: Self.framePrompt,
            requestTimeoutMs: 120_000, providerConfig: llm.providerConfig, verbose: false,
            maxOutputTokens: 2_000, reasoningEffort: llm.reasoningEffort, streamingEnabled: false
        )
        guard let client = try? LLMRefinerFactory.makeTranslator(config: config, systemPrompt: Self.framePrompt),
              let looking = client as? ImageInputRefining else {
            return nil
        }
        defer { client.dispose() }
        let question = "The image shows \(count) numbered frames (1 to \(count)) of a video, in time order. The moment: \(moment.title). Why it matters: \(moment.why)\nWhich frame should go on a presentation slide for this moment? Answer with the number only."
        guard let answer = try? await looking.refine(question, image: sheet, onProgress: nil),
              let number = answer.split(whereSeparator: { !$0.isNumber }).first.flatMap({ Int($0) }),
              (1...count).contains(number) else {
            return nil
        }
        return number - 1
    }

    static let framePrompt = "You pick the best frame of a video for a presentation slide. Prefer the frame where the slide, diagram, chart, code or demo the moment is about is shown fully and legibly, filling as much of the frame as possible. Avoid frames in a transition, blurred, with the content cut off, or showing only the speaker or the audience, unless the moment is about the speaker or the scene itself. Answer with the frame's number only."

    // MARK: - Material

    /// Transcript lines of about 30 s each: `[m:ss] (Speaker 2) words`.
    public static func lines(_ segments: [MeetingSegment]) -> [String] {
        var lines: [String] = []
        var start = 0
        var speaker: String?
        var words: [String] = []
        func flush() {
            guard !words.isEmpty else { return }
            let who = speaker.map { " (Speaker \($0.hasPrefix("spk:") ? String($0.dropFirst(4)) : $0))" } ?? ""
            lines.append("[\(VideoDigestTime.label(start / 1000))]\(who) \(words.joined(separator: " "))")
            words.removeAll()
        }
        for segment in MeetingTranscriptFormat.ordered(segments) {
            if words.isEmpty {
                start = segment.startMs
                speaker = segment.speaker
            } else if segment.speaker != speaker || segment.startMs - start >= 30_000 {
                flush()
                start = segment.startMs
                speaker = segment.speaker
            }
            words.append(segment.text)
        }
        flush()
        return lines
    }

    static func timeOf(_ line: String) -> String? {
        guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return nil }
        return String(line[line.index(after: line.startIndex)..<end])
    }

    static func header(_ video: VideoInfo) -> String {
        var text = "VIDEO: \(video.title)\nCHANNEL: \(video.channel)\nLENGTH: \(VideoDigestTime.label(video.durationSeconds)) (\(video.durationSeconds) s)\n"
        if !video.chapters.isEmpty {
            text += "CHAPTERS (from the description):\n" + video.chapters.map { "\(VideoDigestTime.label($0.start)) \($0.title)" }.joined(separator: "\n") + "\n"
        }
        let description = video.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            text += "DESCRIPTION:\n\(String(description.prefix(3_000)))\n"
        }
        return text
    }

    static let notesPrompt = """
    You take notes on one part of a video's transcript, for someone who will write the digest of the whole video without seeing the transcript.
    Write plain text, in the video's language:
    - every point, claim, number, name, example and argument, each with its time [m:ss];
    - how it is said: tone, structure, rhetorical devices, evidence offered;
    - 2 to 5 verbatim quotes worth citing, with time and speaker;
    - moments a presenter could show on a slide (a slide or diagram on screen, a demo, a striking claim), with time and why.
    Never invent anything that is not in the transcript. Keep the times exactly as given.
    """

    static func digestPrompt(language: String) -> String {
        """
        You write the digest of a video for someone who has no time to watch it: what it says, and how it says it.
        Write every field in \(language), except "quotes[].text", which stays verbatim in the language spoken in the video (give "translation" in \(language) when that is another language, else null).
        Answer with ONE JSON object and nothing else, exactly with these fields:
        {
          "title": "a clear title of what the video is about",
          "standfirst": "one dense paragraph: the main claim, the key numbers, the conclusion",
          "language": "\(language)",
          "speakers": ["who speaks, by name when the video says it"],
          "keyPoints": [{"lead": "a short bold phrase", "text": "one to three sentences", "time": 123}],
          "delivery": {"summary": "a paragraph on how the message is delivered", "tone": "...", "structure": "how the argument is built", "techniques": ["rhetorical devices, examples, stories, demos"], "evidence": "what evidence is offered, and what is only asserted"},
          "sections": [{"title": "...", "start": 0, "paragraphs": ["2 to 4 detailed paragraphs"]}],
          "quotes": [{"text": "verbatim", "time": 123, "speaker": "name or null", "translation": "or null"}],
          "moments": [{"time": 123, "title": "what is on screen or said", "why": "why it is worth showing in a presentation"}],
          "resources": [{"title": "...", "url": "only links that appear in the description"}]
        }
        Rules: times are whole seconds from the start of the video, taken from the transcript's [m:ss] marks, never beyond the video's length. 8 to 12 key points; sections follow the chapters when there are any, else the topic shifts (4 to 12, by length); 3 to 8 quotes; 4 to 8 moments, the most useful for a presentation (slides, diagrams, demos, data, a quotable claim). Be specific: names, numbers, tools, examples. Never invent what is not in the material; say when something is only asserted.
        """
    }

    // MARK: - Answer

    static func parse(_ answer: String) throws -> VideoDigestAnalysis {
        guard let start = answer.firstIndex(of: "{"), let end = answer.lastIndex(of: "}"), start < end else {
            throw VideoDigestError.analysis("the model did not answer with the digest's data.")
        }
        do {
            return try JSONDecoder().decode(VideoDigestAnalysis.self, from: Data(answer[start...end].utf8))
        } catch {
            throw VideoDigestError.analysis("the model's answer did not have the digest's form (\(error.localizedDescription)).")
        }
    }

    /// Times within the video; moments at most 8, at least 20 s apart, set
    /// on the start of the transcript line they fall in.
    static func validated(_ analysis: VideoDigestAnalysis, video: VideoInfo, transcript: [MeetingSegment]) -> VideoDigestAnalysis {
        let length = video.durationSeconds > 0 ? video.durationSeconds : (transcript.map(\.endMs).max() ?? 0) / 1000
        func inside(_ time: Int?) -> Int? {
            guard let time, time >= 0, time <= length else { return nil }
            return time
        }
        var result = analysis
        result.keyPoints = analysis.keyPoints.map { var point = $0; point.time = inside(point.time); return point }
        result.sections = analysis.sections.filter { inside($0.start) != nil }.sorted { $0.start < $1.start }
        result.quotes = analysis.quotes.filter { inside($0.time) != nil }
        let starts = transcript.map { $0.startMs / 1000 }.sorted()
        var moments: [VideoDigestAnalysis.Moment] = []
        for moment in analysis.moments.sorted(by: { $0.time < $1.time }) {
            guard inside(moment.time) != nil else { continue }
            var placed = moment
            placed.time = starts.last(where: { $0 <= moment.time && moment.time - $0 <= 15 }) ?? moment.time
            placed.screenshot = nil
            if let previous = moments.last, placed.time - previous.time < 20 { continue }
            moments.append(placed)
        }
        result.moments = Array(moments.prefix(8))
        let links = Set(video.links)
        result.resources = analysis.resources.filter { links.contains($0.url) }
        return result
    }

    /// The name of a language code in English ("el" → "Greek").
    public static func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: YouTubeVideo.baseLanguage(code))
    }
}
