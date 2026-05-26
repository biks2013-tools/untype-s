import Foundation

public struct PromptConfig: Equatable, Sendable {
    public let refinementSystemPrompt: String
    public let translationSystemPrompt: String
    public let translationUserPromptTemplate: String
    public let compositeSystemPrompt: String
    public let compositeRefinementPromptTemplate: String
    public let compositeTranslationPromptTemplate: String
    public let sonioxTranscriptionContext: String?
    public let elevenLabsPreviousText: String?
    public let elevenLabsKeyterms: [String]

    public init(
        refinementSystemPrompt: String,
        translationSystemPrompt: String,
        translationUserPromptTemplate: String,
        compositeSystemPrompt: String,
        compositeRefinementPromptTemplate: String,
        compositeTranslationPromptTemplate: String,
        sonioxTranscriptionContext: String?,
        elevenLabsPreviousText: String?,
        elevenLabsKeyterms: [String]
    ) {
        self.refinementSystemPrompt = refinementSystemPrompt
        self.translationSystemPrompt = translationSystemPrompt
        self.translationUserPromptTemplate = translationUserPromptTemplate
        self.compositeSystemPrompt = compositeSystemPrompt
        self.compositeRefinementPromptTemplate = compositeRefinementPromptTemplate
        self.compositeTranslationPromptTemplate = compositeTranslationPromptTemplate
        self.sonioxTranscriptionContext = sonioxTranscriptionContext
        self.elevenLabsPreviousText = elevenLabsPreviousText
        self.elevenLabsKeyterms = elevenLabsKeyterms
    }

    public static let defaultValue = PromptConfig(
        refinementSystemPrompt: UntypePromptDefaults.refinementSystemPrompt,
        translationSystemPrompt: UntypePromptDefaults.translationSystemPrompt,
        translationUserPromptTemplate: UntypePromptDefaults.translationUserPromptTemplate,
        compositeSystemPrompt: UntypePromptDefaults.compositeSystemPrompt,
        compositeRefinementPromptTemplate: UntypePromptDefaults.compositeRefinementPromptTemplate,
        compositeTranslationPromptTemplate: UntypePromptDefaults.compositeTranslationPromptTemplate,
        sonioxTranscriptionContext: nil,
        elevenLabsPreviousText: nil,
        elevenLabsKeyterms: []
    )
}

public enum UntypePromptDefaults {
    public static let refinementSystemPrompt = "You are a transcript-cleanup assistant. The input is a verbatim transcript of someone speaking and may contain disfluencies, filler words, false starts, and grammatical noise. Rewrite the text so it is grammatically correct and easy to read, preserving the speaker's meaning AND the original language. Respond with ONLY the cleaned text - no preamble, no quotes, no markdown, no explanation."

    public static let translationSystemPrompt = "You are a translation assistant for live dictated agent commands. Translate the user's text to the requested target language. Preserve technical terms, filenames, command names, and code identifiers. Respond with ONLY the translated text - no preamble, no quotes, no markdown, no explanation."

    public static let translationUserPromptTemplate = "Translate the following text to {target_language}. Return only the translated text.\n\n{text}"

    public static let compositeSystemPrompt = "You are a transcript cleanup and translation assistant for live dictated agent commands. Perform both tasks in one response: first refine the transcript while preserving the speaker's meaning and original language, then translate the refined text to the requested target language. Preserve technical terms, filenames, command names, and code identifiers. Respond with ONLY valid JSON, no markdown and no explanation, using exactly this shape: {\"refined_text\":\"...\",\"translated_text\":\"...\"}."

    public static let compositeRefinementPromptTemplate = "Refine the following transcript while preserving the speaker's meaning and original language.\n\n{text}"

    public static let compositeTranslationPromptTemplate = "Translate the refined text to {target_language}. Preserve technical terms, filenames, command names, and code identifiers."

    public static let promptFiles: [(name: String, defaultContent: String, required: Bool)] = [
        ("001-refinement-system.txt", refinementSystemPrompt, true),
        ("002-translation-system.txt", translationSystemPrompt, true),
        ("003-translation-user-template.txt", translationUserPromptTemplate, true),
        ("004-soniox-transcription-context.txt", "", false),
        ("005-elevenlabs-previous-text.txt", "", false),
        ("006-elevenlabs-keyterms.txt", "", false),
        ("007-composite-refine-translate-system.txt", compositeSystemPrompt, true),
        ("008-composite-refinement-template.txt", compositeRefinementPromptTemplate, true),
        ("009-composite-translation-template.txt", compositeTranslationPromptTemplate, true)
    ]
}
