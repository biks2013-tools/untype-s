public enum STTProvider: String, Sendable, Equatable {
    case soniox
    case elevenlabs
}

public enum OutputMode: String, Sendable, Equatable, CaseIterable {
    case overwrite
    case append
    case finalOnly = "final-only"
}

public enum InteractionMode: String, Sendable, Equatable, CaseIterable {
    case dictation
    case agentProtocol = "agent-protocol"
    case hybrid
}

public enum TranslationPolicy: String, Sendable, Equatable, CaseIterable {
    case opposite
    case toEnglish = "to-en"
    case toGreek = "to-el"
}

public enum LLMProvider: String, Sendable, Equatable, CaseIterable {
    case azureOpenAI = "azure-openai"
    case openAI = "openai"
    case anthropic
    case google
    case azureAIInference = "azure-ai-inference"
    case ollama
    case litellm
    case openAICompat = "openai-compat"
}

public enum ProviderConfig: Equatable, Sendable {
    case azureOpenAI(apiKey: String, endpoint: String, deployment: String, apiVersion: String)
    case google(apiKey: String)
    case unimplemented(provider: LLMProvider)
}

public struct LLMConfig: Equatable, Sendable {
    public let enabled: Bool
    public let provider: LLMProvider
    public let model: String
    public let systemPrompt: String
    public let requestTimeoutMs: Int
    public let providerConfig: ProviderConfig
    public let verbose: Bool
}

public struct MarkerConfig: Equatable, Sendable {
    public let commandPhrase: String
    public let sectionEndPhrase: String
    public let sectionEndAliases: [String]
    public let sectionCancelPhrase: String
    public let literalNextPhrase: String

    public init(
        commandPhrase: String,
        sectionEndPhrase: String,
        sectionEndAliases: [String],
        sectionCancelPhrase: String,
        literalNextPhrase: String
    ) {
        self.commandPhrase = commandPhrase
        self.sectionEndPhrase = sectionEndPhrase
        self.sectionEndAliases = sectionEndAliases
        self.sectionCancelPhrase = sectionCancelPhrase
        self.literalNextPhrase = literalNextPhrase
    }
}

public struct OperatorState: Equatable, Sendable {
    public let refine: Bool
    public let translate: Bool
    public let clipboard: Bool
    public let input: Bool

    public init(refine: Bool, translate: Bool, clipboard: Bool, input: Bool) {
        self.refine = refine
        self.translate = translate
        self.clipboard = clipboard
        self.input = input
    }
}

public enum ProtocolSettingSource: String, Sendable, Equatable {
    case configured
    case `default`
}

public struct ProtocolSettingSources: Equatable, Sendable {
    public let refine: ProtocolSettingSource
    public let translate: ProtocolSettingSource
    public let clipboard: ProtocolSettingSource
    public let input: ProtocolSettingSource
    public let translationPolicy: ProtocolSettingSource

    public init(
        refine: ProtocolSettingSource,
        translate: ProtocolSettingSource,
        clipboard: ProtocolSettingSource,
        input: ProtocolSettingSource,
        translationPolicy: ProtocolSettingSource
    ) {
        self.refine = refine
        self.translate = translate
        self.clipboard = clipboard
        self.input = input
        self.translationPolicy = translationPolicy
    }
}

public struct ProtocolRuntimeConfig: Equatable, Sendable {
    public let interactionMode: InteractionMode
    public let markers: MarkerConfig
    public let initialOperators: OperatorState
    public let translationPolicy: TranslationPolicy
    public let protocolOutput: String?
    public let settingSources: ProtocolSettingSources

    public init(
        interactionMode: InteractionMode,
        markers: MarkerConfig,
        initialOperators: OperatorState,
        translationPolicy: TranslationPolicy,
        protocolOutput: String?,
        settingSources: ProtocolSettingSources
    ) {
        self.interactionMode = interactionMode
        self.markers = markers
        self.initialOperators = initialOperators
        self.translationPolicy = translationPolicy
        self.protocolOutput = protocolOutput
        self.settingSources = settingSources
    }
}

public struct ResolvedConfig: Equatable, Sendable {
    public let sttProvider: STTProvider
    public let apiKey: String
    public let apiKeyEnvName: String
    public let apiKeySource: EnvSource
    public let apiKeyExpiresAt: String?
    public let model: String
    public let endpoint: String
    public let languages: [String]
    public let sampleRate: Int
    public let enableEndpointDetection: Bool
    public let quickClose: Bool
    public let outputMode: OutputMode
    public let guardPhrase: String
    public let protocolConfig: ProtocolRuntimeConfig
    public let llm: LLMConfig
    public let prompts: PromptConfig
    public let releaseLatencyLogging: ReleaseLatencyLoggingConfig
    public let verbose: Bool
    public let warnings: [String]
}
