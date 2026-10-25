import Foundation
import Testing
@testable import UntypeCore

/// Live check of the configured LLM provider against the real
/// ~/.tool-agents/untype configuration (refine, translate, combined call).
/// Opt-in: `UNTYPE_LIVE_LLM_TEST=1 swift test --filter LiveLLM`. Extra flags
/// (e.g. `--llm-provider azure-anthropic --llm-model claude-opus-5-5`) come
/// from `UNTYPE_LIVE_LLM_ARGS`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["UNTYPE_LIVE_LLM_TEST"] == "1"))
func liveLLMProviderRefinesTranslatesAndCombines() async throws {
    let extra = (ProcessInfo.processInfo.environment["UNTYPE_LIVE_LLM_ARGS"] ?? "")
        .split(separator: " ").map(String.init)
    let config = try ConfigResolver().resolve(argv: ["--refine-default", "on"] + extra)
    print("[live] provider=\(config.llm.provider.rawValue) model=\(config.llm.model) streaming=\(config.llm.streamingEnabled)")

    let raw = "ehm so I I wanted to uh say that the the meeting is is moved to tomorrow"
    let refiner = try #require(try LLMRefinerFactory.makeRefiner(config: config.llm))
    var start = Date()
    let refined = try await refiner.refine(raw)
    print("[live] refine \(Int(Date().timeIntervalSince(start) * 1000)) ms: \(refined)")
    #expect(!refined.isEmpty && refined.lowercased().contains("tomorrow"))

    let translator = try #require(try LLMRefinerFactory.makeTranslator(
        config: config.llm,
        systemPrompt: config.prompts.translationSystemPrompt
    ))
    start = Date()
    let translated = try await translator.refine(
        config.prompts.translationUserPromptTemplate
            .replacingOccurrences(of: "{target_language}", with: "Greek")
            .replacingOccurrences(of: "{text}", with: "The meeting is moved to tomorrow.")
    )
    print("[live] translate \(Int(Date().timeIntervalSince(start) * 1000)) ms: \(translated)")
    #expect(translated.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) })

    let composite = try #require(try LLMRefinerFactory.makeCompositeRefineTranslator(config: config.llm, prompts: config.prompts))
    start = Date()
    let both = try await composite.refineAndTranslate(CompositeRefineTranslateRequest(rawText: raw, targetLanguageName: "Greek"))
    print("[live] refine+translate \(Int(Date().timeIntervalSince(start) * 1000)) ms: \(both.refinedText) | \(both.translatedText)")
    #expect(!both.refinedText.isEmpty && !both.translatedText.isEmpty)
}

/// Live check of the Ask operator's prompts: the reply must be the requested
/// text itself, in the request's language or the target language.
@Test(.enabled(if: ProcessInfo.processInfo.environment["UNTYPE_LIVE_LLM_TEST"] == "1"))
func liveLLMProviderAnswersDictatedRequests() async throws {
    let extra = (ProcessInfo.processInfo.environment["UNTYPE_LIVE_LLM_ARGS"] ?? "")
        .split(separator: " ").map(String.init)
    let config = try ConfigResolver().resolve(argv: ["--ask-default", "on"] + extra)
    let asker = try #require(try LLMRefinerFactory.makeAsker(config: config.llm, systemPrompt: config.prompts.askSystemPrompt))

    let requests = [
        "ehm write a a short reply to Maria thanking her for the report and uh proposing we meet on Tuesday",
        "γράψε μου σε δύο προτάσεις τι είναι το mutex",
        "Θέλω να μου προσθέσεις μερικά στοιχεία που να δείχνουν πώς τράπεζες μεγάλες τράπεζες στο εξωτερικό, εε, έχουν χρησιμοποιήσει, χρησιμοποιούν σήμερα την τεχνητή νοημοσύνη σε σενάρια εξυπηρετήσεων πελατών τους, αλλά και σε σενάρια που αφορούν την εσωτερική λειτουργία τους."
    ]
    for request in requests {
        let start = Date()
        let answer = try await asker.refine(config.prompts.askUserPromptTemplate.replacingOccurrences(of: "{text}", with: request))
        print("[live] ask \(Int(Date().timeIntervalSince(start) * 1000)) ms:\n\(answer)\n---")
        #expect(!answer.isEmpty)
        #expect(!answer.lowercased().hasPrefix("sure"))
        #expect(!answer.lowercased().hasPrefix("here is"))
    }

    let start = Date()
    let translated = try await asker.refine(
        config.prompts.askTranslatedUserPromptTemplate
            .replacingOccurrences(of: "{target_language}", with: "English")
            .replacingOccurrences(of: "{text}", with: "γράψε μια πρόταση για το γιατί είναι χρήσιμες οι δοκιμές λογισμικού")
    )
    print("[live] ask+translate \(Int(Date().timeIntervalSince(start) * 1000)) ms:\n\(translated)\n---")
    #expect(!translated.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) })
}
