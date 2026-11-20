import Foundation
import SwiftUI
import UntypeCore

/// The model providers the iPhone and iPad app can call for Refine and
/// Translate. The names of the keys are those of the Mac app.
enum ModelProvider: String, CaseIterable, Identifiable {
    case deepseek
    case google
    case azureOpenAI
    case azureAnthropic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .google: return "Google Gemini"
        case .azureOpenAI: return "Azure OpenAI"
        case .azureAnthropic: return "Claude (Azure Foundry)"
        }
    }

    var keyName: String {
        switch self {
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .google: return "GOOGLE_API_KEY"
        case .azureOpenAI: return "AZURE_OPENAI_API_KEY"
        case .azureAnthropic: return "ANTHROPIC_FOUNDRY_API_KEY"
        }
    }

    /// Whether the provider needs an address of the user's own.
    var needsEndpoint: Bool {
        self != .google
    }

    var endpointLabel: String {
        switch self {
        case .deepseek: return "API address"
        case .google: return ""
        case .azureOpenAI: return "Endpoint"
        case .azureAnthropic: return "Base URL"
        }
    }

    var endpointExample: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .google: return ""
        case .azureOpenAI: return "https://name.openai.azure.com"
        case .azureAnthropic: return "https://name.services.ai.azure.com/anthropic"
        }
    }
}

enum TargetLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case greek = "Greek"

    var id: String { rawValue }
}

/// What the user has set. Keys live in the Keychain, the rest in the app's
/// preferences. Nothing has a value until the user gives one: a missing
/// setting is reported when it is needed.
@MainActor
final class AppSettings: ObservableObject {
    static let sonioxKeyName = STTProvider.soniox.apiKeyEnvName

    @AppStorage("speech.languages") var languages = ""
    @AppStorage("model.provider") var providerRaw = ""
    @AppStorage("model.name") var modelName = ""
    @AppStorage("model.endpoint") var endpoint = ""
    @AppStorage("model.azureAPIVersion") var azureAPIVersion = ""
    @AppStorage("operators.refine") var refine = false
    @AppStorage("operators.translate") var translate = false
    @AppStorage("operators.target") var targetRaw = TargetLanguage.english.rawValue

    @Published private(set) var dictionary = UserDictionary.empty
    @Published var dictionaryProblem: String?

    init() {
        do {
            dictionary = try UserDictionaryStore.load()
        } catch {
            dictionaryProblem = error.localizedDescription
        }
    }

    var provider: ModelProvider? {
        ModelProvider(rawValue: providerRaw)
    }

    var target: TargetLanguage {
        TargetLanguage(rawValue: targetRaw) ?? .english
    }

    var hasSonioxKey: Bool {
        KeychainStore.read(Self.sonioxKeyName) != nil
    }

    var languageCodes: [String] {
        languages
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    func sonioxOptions() throws -> SonioxTranscriberOptions {
        guard let key = KeychainStore.read(Self.sonioxKeyName) else {
            throw AppError("Enter your Soniox key in Settings to dictate.")
        }
        let codes = languageCodes
        guard !codes.isEmpty else {
            throw AppError("Enter at least one language in Settings (for example: el, en).")
        }
        return SonioxTranscriberOptions(
            apiKey: key,
            model: STTProvider.soniox.defaultModel,
            endpoint: STTProvider.soniox.defaultEndpoint,
            languages: codes,
            sampleRate: DictationEngine.sampleRate,
            enableEndpointDetection: true,
            terms: dictionary.terms
        )
    }

    /// The model client's configuration for a call with `systemPrompt`.
    func modelConfig(systemPrompt: String) throws -> LLMConfig {
        guard let provider else {
            throw AppError("Choose a model provider in Settings to use Refine or Translate.")
        }
        guard let key = KeychainStore.read(provider.keyName) else {
            throw AppError("Enter the \(provider.title) key in Settings.")
        }
        let model = modelName.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else {
            throw AppError("Enter the model's name in Settings.")
        }
        let address = endpoint.trimmingCharacters(in: .whitespaces)
        if provider.needsEndpoint, address.isEmpty {
            throw AppError("Enter the \(provider.endpointLabel.lowercased()) of \(provider.title) in Settings.")
        }
        let coreProvider: LLMProvider
        let providerConfig: ProviderConfig
        switch provider {
        case .deepseek:
            coreProvider = .deepseek
            providerConfig = .openAICompatible(apiKey: key, baseURL: address)
        case .google:
            coreProvider = .google
            providerConfig = .google(apiKey: key)
        case .azureOpenAI:
            let version = azureAPIVersion.trimmingCharacters(in: .whitespaces)
            guard !version.isEmpty else {
                throw AppError("Enter the Azure OpenAI API version in Settings.")
            }
            coreProvider = .azureOpenAI
            providerConfig = .azureOpenAI(apiKey: key, endpoint: address, deployment: model, apiVersion: version)
        case .azureAnthropic:
            coreProvider = .azureAnthropic
            providerConfig = .anthropic(apiKey: key, baseURL: address)
        }
        return LLMConfig(
            enabled: true,
            provider: coreProvider,
            model: model,
            systemPrompt: systemPrompt,
            requestTimeoutMs: 30_000,
            providerConfig: providerConfig,
            verbose: false
        )
    }

    // MARK: - Dictionary

    func addWord(_ word: String) -> String? {
        var changed = dictionary
        do {
            try changed.add(word)
            try UserDictionaryStore.save(changed)
            dictionary = changed
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeWord(_ term: String) {
        var changed = dictionary
        changed.remove(term)
        do {
            try UserDictionaryStore.save(changed)
            dictionary = changed
        } catch {
            dictionaryProblem = error.localizedDescription
        }
    }
}
