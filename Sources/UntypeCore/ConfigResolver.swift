import Foundation

public struct ConfigResolver: Sendable {
    private let cwd: URL
    private let home: URL
    private let shell: [String: String]
    private let now: Date
    private let requireProtocolOutputForHybrid: Bool
    private let validateLLMProviderConfig: Bool

    private static let defaultSonioxModel = "stt-rt-v4"
    private static let defaultSonioxEndpoint = "wss://stt-rt.soniox.com/transcribe-websocket"
    private static let defaultSonioxLanguages = "el,en"
    private static let defaultElevenLabsModel = "scribe_v2_realtime"
    private static let defaultElevenLabsEndpoint = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
    private static let defaultElevenLabsLanguages = "auto"
    private static let defaultSampleRate = 16_000
    private static let elevenLabsSampleRates: Set<Int> = [8_000, 16_000, 22_050, 24_000, 44_100, 48_000]
    private static let defaultGuardPhrase = "τέλος εντολής"
    private static let defaultCommandPhrase = "command"
    private static let defaultSectionEndPhrase = "command send"
    private static let defaultSectionCancelPhrase = "command cancel"
    private static let defaultLiteralNextPhrase = "literal phrase"
    private static let defaultLLMModel = "gpt-5.4"
    private static let defaultLLMRequestTimeoutMs = 15_000
    private static let defaultAzureAPIVersion = "2024-10-21"

    public init(
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        requireProtocolOutputForHybrid: Bool = true,
        validateLLMProviderConfig: Bool = true
    ) {
        self.cwd = cwd
        self.home = home
        self.shell = shell
        self.now = now
        self.requireProtocolOutputForHybrid = requireProtocolOutputForHybrid
        self.validateLLMProviderConfig = validateLLMProviderConfig
    }

    public func resolve(argv: [String]) throws -> ResolvedConfig {
        let parsed = try ParsedArguments(argv: argv)
        try validateLegacyConfigFolderMigration()
        let chain = try EnvChain(cwd: cwd, home: home, shell: shell)

        let providerRaw = resolveString(
            flagValue: parsed.value(for: "--stt-provider"),
            chain: chain,
            envKey: "UNTYPE_STT_PROVIDER",
            defaultValue: "soniox"
        )
        guard let provider = STTProvider(rawValue: providerRaw) else {
            throw UntypeError.invalidConfiguration(
                "--stt-provider / UNTYPE_STT_PROVIDER must be one of: soniox, elevenlabs."
            )
        }
        let promptConfig = try resolvePromptConfig(provider: provider)

        let keyName: String
        let flagName: String
        let expiryFlagName: String
        let expiryEnvName: String
        switch provider {
        case .soniox:
            keyName = "SONIOX_API_KEY"
            flagName = "--api-key"
            expiryFlagName = "--api-key-expires-at"
            expiryEnvName = "SONIOX_API_KEY_EXPIRES_AT"
        case .elevenlabs:
            keyName = "ELEVENLABS_API_KEY"
            flagName = "--elevenlabs-api-key"
            expiryFlagName = "--elevenlabs-api-key-expires-at"
            expiryEnvName = "ELEVENLABS_API_KEY_EXPIRES_AT"
        }

        let key: EnvValue?
        if let flagValue = parsed.value(for: flagName), !flagValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key = EnvValue(value: flagValue.trimmingCharacters(in: .whitespacesAndNewlines), source: .flag)
        } else {
            key = chain.get(keyName)
        }

        guard let apiKey = key else {
            throw UntypeError.missingConfiguration(
                "\(keyName) is not set. Provide via \(flagName), <cwd>/.env, ~/.tool-agents/untype/.env, or shell environment."
            )
        }

        let apiKeyExpiresAt = try optionalIsoDate(
            parsed.value(for: expiryFlagName) ?? chain.get(expiryEnvName)?.value,
            flagName: expiryFlagName,
            envName: expiryEnvName
        )

        let defaultModel: String
        let defaultEndpoint: String
        let defaultLanguagesCsv: String
        switch provider {
        case .soniox:
            defaultModel = Self.defaultSonioxModel
            defaultEndpoint = Self.defaultSonioxEndpoint
            defaultLanguagesCsv = Self.defaultSonioxLanguages
        case .elevenlabs:
            defaultModel = Self.defaultElevenLabsModel
            defaultEndpoint = Self.defaultElevenLabsEndpoint
            defaultLanguagesCsv = Self.defaultElevenLabsLanguages
        }

        let model = resolveString(
            flagValue: parsed.value(for: "--model"),
            chain: chain,
            envKey: "UNTYPE_MODEL",
            defaultValue: defaultModel
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty {
            throw UntypeError.invalidConfiguration("--model / UNTYPE_MODEL must not be empty.")
        }

        let endpoint = try parseWsUrl(
            resolveString(
                flagValue: parsed.value(for: "--endpoint"),
                chain: chain,
                envKey: "UNTYPE_ENDPOINT",
                defaultValue: defaultEndpoint
            ),
            flagName: "--endpoint",
            envName: "UNTYPE_ENDPOINT"
        )

        var languages: [String]
        if !parsed.values(for: "--language").isEmpty {
            languages = parsed.values(for: "--language")
        } else {
            languages = try parseCsvNonEmpty(
                chain.get("UNTYPE_LANGUAGES")?.value ?? defaultLanguagesCsv,
                flagName: "--language",
                envName: "UNTYPE_LANGUAGES"
            )
        }
        languages = try validateLanguages(languages)
        if provider == .elevenlabs && languages.count > 1 {
            throw UntypeError.invalidConfiguration(
                "--language may be 'auto' or a single language code when --stt-provider=elevenlabs."
            )
        }

        let sampleRate = try parsePositiveInt(
            resolveString(
                flagValue: parsed.value(for: "--sample-rate"),
                chain: chain,
                envKey: "UNTYPE_SAMPLE_RATE",
                defaultValue: String(Self.defaultSampleRate)
            ),
            flagName: "--sample-rate",
            envName: "UNTYPE_SAMPLE_RATE",
            min: 8_000,
            max: 48_000
        )
        if provider == .elevenlabs && !Self.elevenLabsSampleRates.contains(sampleRate) {
            let values = Self.elevenLabsSampleRates.sorted().map(String.init).joined(separator: ", ")
            throw UntypeError.invalidConfiguration(
                "--sample-rate / UNTYPE_SAMPLE_RATE must be one of \(values) when --stt-provider=elevenlabs. Got: \(sampleRate)."
            )
        }

        let quickClose: Bool
        if let flagValue = parsed.switchValue(for: "--quick-close") {
            quickClose = flagValue
        } else {
            quickClose = try parseBoolean(
                chain.get("UNTYPE_QUICK_CLOSE")?.value,
                flagName: "--quick-close",
                envName: "UNTYPE_QUICK_CLOSE"
            ) ?? false
        }

        let enableEndpointDetection: Bool
        if let flagValue = parsed.switchValue(for: "--endpoint-detection") {
            enableEndpointDetection = flagValue
        } else {
            enableEndpointDetection = try parseBoolean(
                chain.get("UNTYPE_ENABLE_ENDPOINT_DETECTION")?.value,
                flagName: "--endpoint-detection",
                envName: "UNTYPE_ENABLE_ENDPOINT_DETECTION"
            ) ?? true
        }

        let outputModeRaw = resolveString(
            flagValue: parsed.value(for: "--output-mode"),
            chain: chain,
            envKey: "UNTYPE_OUTPUT_MODE",
            defaultValue: OutputMode.overwrite.rawValue
        )
        guard let outputMode = OutputMode(rawValue: outputModeRaw) else {
            throw UntypeError.invalidConfiguration(
                "--output-mode / UNTYPE_OUTPUT_MODE must be one of: overwrite, append, final-only."
            )
        }

        let guardPhrase = try validateGuardPhrase(
            resolveString(
                flagValue: parsed.value(for: "--guard-phrase"),
                chain: chain,
                envKey: "UNTYPE_GUARD_PHRASE",
                defaultValue: Self.defaultGuardPhrase
            )
        )

        let interactionModeRaw = resolveString(
            flagValue: parsed.value(for: "--interaction-mode"),
            chain: chain,
            envKey: "UNTYPE_INTERACTION_MODE",
            defaultValue: InteractionMode.dictation.rawValue
        )
        guard let interactionMode = InteractionMode(rawValue: interactionModeRaw) else {
            throw UntypeError.invalidConfiguration(
                "--interaction-mode / UNTYPE_INTERACTION_MODE must be one of: dictation, agent-protocol, hybrid."
            )
        }

        let commandPhrase = try validateProtocolPhrase(
            resolveString(
                flagValue: parsed.value(for: "--command-phrase"),
                chain: chain,
                envKey: "UNTYPE_COMMAND_PHRASE",
                defaultValue: Self.defaultCommandPhrase
            ),
            flagName: "--command-phrase"
        )
        let sectionEndPhrase = try validateProtocolPhrase(
            resolveString(
                flagValue: parsed.value(for: "--section-end-phrase"),
                chain: chain,
                envKey: "UNTYPE_SECTION_END_PHRASE",
                defaultValue: Self.defaultSectionEndPhrase
            ),
            flagName: "--section-end-phrase"
        )
        let sectionCancelPhrase = try validateProtocolPhrase(
            resolveString(
                flagValue: parsed.value(for: "--section-cancel-phrase"),
                chain: chain,
                envKey: "UNTYPE_SECTION_CANCEL_PHRASE",
                defaultValue: Self.defaultSectionCancelPhrase
            ),
            flagName: "--section-cancel-phrase"
        )
        let literalNextPhrase = try validateProtocolPhrase(
            resolveString(
                flagValue: parsed.value(for: "--literal-next-phrase"),
                chain: chain,
                envKey: "UNTYPE_LITERAL_NEXT_PHRASE",
                defaultValue: Self.defaultLiteralNextPhrase
            ),
            flagName: "--literal-next-phrase"
        )
        let refineDefault = try parseBoolean(
            resolveString(
                flagValue: parsed.value(for: "--refine-default"),
                chain: chain,
                envKey: "UNTYPE_REFINE_DEFAULT",
                defaultValue: "off"
            ),
            flagName: "--refine-default",
            envName: "UNTYPE_REFINE_DEFAULT"
        ) ?? false
        let translateDefault = try parseBoolean(
            resolveString(
                flagValue: parsed.value(for: "--translate-default"),
                chain: chain,
                envKey: "UNTYPE_TRANSLATE_DEFAULT",
                defaultValue: "off"
            ),
            flagName: "--translate-default",
            envName: "UNTYPE_TRANSLATE_DEFAULT"
        ) ?? false
        let clipboardDefault = try parseBoolean(
            resolveString(
                flagValue: parsed.value(for: "--clipboard-default"),
                chain: chain,
                envKey: "UNTYPE_CLIPBOARD_DEFAULT",
                defaultValue: "off"
            ),
            flagName: "--clipboard-default",
            envName: "UNTYPE_CLIPBOARD_DEFAULT"
        ) ?? false
        let inputDefault = try parseBoolean(
            resolveString(
                flagValue: parsed.value(for: "--input-default"),
                chain: chain,
                envKey: "UNTYPE_INPUT_DEFAULT",
                defaultValue: "off"
            ),
            flagName: "--input-default",
            envName: "UNTYPE_INPUT_DEFAULT"
        ) ?? false

        let translationPolicyRaw = resolveString(
            flagValue: parsed.value(for: "--translation-policy"),
            chain: chain,
            envKey: "UNTYPE_TRANSLATION_POLICY",
            defaultValue: TranslationPolicy.opposite.rawValue
        )
        guard let translationPolicy = TranslationPolicy(rawValue: translationPolicyRaw) else {
            throw UntypeError.invalidConfiguration(
                "--translation-policy / UNTYPE_TRANSLATION_POLICY must be one of: opposite, to-en, to-el."
            )
        }
        let protocolOutputRaw = parsed.value(for: "--protocol-output") ?? chain.get("UNTYPE_PROTOCOL_OUTPUT")?.value
        let protocolOutput = protocolOutputRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        if requireProtocolOutputForHybrid && interactionMode == .hybrid && (protocolOutput?.isEmpty ?? true) {
            throw UntypeError.invalidConfiguration(
                "--protocol-output / UNTYPE_PROTOCOL_OUTPUT is required when --interaction-mode=hybrid."
            )
        }
        let protocolConfig = ProtocolRuntimeConfig(
            interactionMode: interactionMode,
            markers: MarkerConfig(
                commandPhrase: commandPhrase,
                sectionEndPhrase: sectionEndPhrase,
                sectionEndAliases: [guardPhrase],
                sectionCancelPhrase: sectionCancelPhrase,
                literalNextPhrase: literalNextPhrase
            ),
            initialOperators: OperatorState(
                refine: refineDefault,
                translate: translateDefault,
                clipboard: clipboardDefault,
                input: inputDefault
            ),
            translationPolicy: translationPolicy,
            protocolOutput: protocolOutput?.isEmpty == true ? nil : protocolOutput,
            settingSources: ProtocolSettingSources(
                refine: configuredSource(parsed.value(for: "--refine-default"), chain: chain, envKey: "UNTYPE_REFINE_DEFAULT"),
                translate: configuredSource(parsed.value(for: "--translate-default"), chain: chain, envKey: "UNTYPE_TRANSLATE_DEFAULT"),
                clipboard: configuredSource(parsed.value(for: "--clipboard-default"), chain: chain, envKey: "UNTYPE_CLIPBOARD_DEFAULT"),
                input: configuredSource(parsed.value(for: "--input-default"), chain: chain, envKey: "UNTYPE_INPUT_DEFAULT"),
                translationPolicy: configuredSource(parsed.value(for: "--translation-policy"), chain: chain, envKey: "UNTYPE_TRANSLATION_POLICY")
            )
        )

        let verbose = try parsed.switchValue(for: "--verbose") ?? parseBoolean(
            chain.get("UNTYPE_VERBOSE")?.value,
            flagName: "--verbose",
            envName: "UNTYPE_VERBOSE"
        ) ?? false

        let releaseLatencyLogEnabled = try parsed.switchValue(for: "--release-latency-log") ?? parseBoolean(
            chain.get("UNTYPE_RELEASE_LATENCY_LOG")?.value,
            flagName: "--release-latency-log",
            envName: "UNTYPE_RELEASE_LATENCY_LOG"
        ) ?? false
        let releaseLatencyLogPath = try resolvePath(
            parsed.value(for: "--release-latency-log-path") ?? chain.get("UNTYPE_RELEASE_LATENCY_LOG_PATH")?.value,
            defaultURL: Self.defaultReleaseLatencyLogURL(home: home),
            flagName: "--release-latency-log-path",
            envName: "UNTYPE_RELEASE_LATENCY_LOG_PATH"
        )
        let releaseLatencyLogResetOnStart = try parseBoolean(
            chain.get("UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START")?.value,
            flagName: "UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START",
            envName: "UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START"
        ) ?? false

        let refine = try parsed.refineOverride
            ?? parseBoolean(
                chain.get("UNTYPE_REFINE")?.value,
                flagName: "--refine",
                envName: "UNTYPE_REFINE"
            )
            ?? true

        let llmProviderRaw = resolveString(
            flagValue: parsed.value(for: "--llm-provider"),
            chain: chain,
            envKey: "UNTYPE_LLM_PROVIDER",
            defaultValue: LLMProvider.azureOpenAI.rawValue
        )
        guard let llmProvider = LLMProvider(rawValue: llmProviderRaw) else {
            let values = LLMProvider.allCases.map(\.rawValue).joined(separator: ", ")
            throw UntypeError.invalidConfiguration(
                "--llm-provider / UNTYPE_LLM_PROVIDER must be one of: \(values)."
            )
        }
        let llmModel = resolveString(
            flagValue: parsed.value(for: "--llm-model"),
            chain: chain,
            envKey: "UNTYPE_LLM_MODEL",
            defaultValue: Self.defaultLLMModel
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if llmModel.isEmpty {
            throw UntypeError.invalidConfiguration("--llm-model must not be empty.")
        }
        let providerConfig = try resolveLLMProviderConfig(
            enabled: refine,
            provider: llmProvider,
            model: llmModel,
            chain: chain,
            validateRequiredSettings: validateLLMProviderConfig
        )
        let llmMaxOutputTokens = try resolveLLMMaxOutputTokens(parsed: parsed, chain: chain)
        let llmReasoningEffort = try resolveLLMReasoningEffort(parsed: parsed, chain: chain)
        let llm = LLMConfig(
            enabled: refine,
            provider: llmProvider,
            model: llmModel,
            systemPrompt: promptConfig.refinementSystemPrompt,
            requestTimeoutMs: Self.defaultLLMRequestTimeoutMs,
            providerConfig: providerConfig,
            verbose: verbose,
            maxOutputTokens: llmMaxOutputTokens,
            reasoningEffort: llmReasoningEffort
        )

        return ResolvedConfig(
            sttProvider: provider,
            apiKey: apiKey.value,
            apiKeyEnvName: keyName,
            apiKeySource: apiKey.source,
            apiKeyExpiresAt: apiKeyExpiresAt,
            model: model,
            endpoint: endpoint,
            languages: languages,
            sampleRate: sampleRate,
            enableEndpointDetection: enableEndpointDetection,
            quickClose: quickClose,
            outputMode: outputMode,
            guardPhrase: guardPhrase,
            protocolConfig: protocolConfig,
            llm: llm,
            prompts: promptConfig,
            releaseLatencyLogging: ReleaseLatencyLoggingConfig(
                enabled: releaseLatencyLogEnabled,
                path: releaseLatencyLogPath,
                resetOnStart: releaseLatencyLogResetOnStart
            ),
            verbose: verbose,
            warnings: expiryWarnings(envName: keyName, isoDate: apiKeyExpiresAt)
        )
    }

    private func resolvePromptConfig(provider: STTProvider) throws -> PromptConfig {
        let directory = promptDirectory()
        try ensurePromptDirectory(directory)

        let fileManager = FileManager.default
        var values: [String: String] = [:]
        for file in UntypePromptDefaults.promptFiles {
            let url = directory.appendingPathComponent(file.name)
            if !fileManager.fileExists(atPath: url.path) {
                try writeDefaultPrompt(file.defaultContent, to: url)
            }
            values[file.name] = try readPromptFile(url, required: file.required)
        }

        let translationTemplate = try requiredPrompt(
            values["003-translation-user-template.txt"],
            name: "003-translation-user-template.txt",
            path: directory.appendingPathComponent("003-translation-user-template.txt")
        )
        guard translationTemplate.contains("{target_language}"), translationTemplate.contains("{text}") else {
            throw UntypeError.invalidConfiguration(
                "Prompt file \(displayPath(directory.appendingPathComponent("003-translation-user-template.txt"))) must contain {target_language} and {text} placeholders."
            )
        }
        let compositeRefinementTemplate = try requiredPrompt(
            values["008-composite-refinement-template.txt"],
            name: "008-composite-refinement-template.txt",
            path: directory.appendingPathComponent("008-composite-refinement-template.txt")
        )
        guard compositeRefinementTemplate.contains("{text}") else {
            throw UntypeError.invalidConfiguration(
                "Prompt file \(displayPath(directory.appendingPathComponent("008-composite-refinement-template.txt"))) must contain the {text} placeholder."
            )
        }
        let compositeTranslationTemplate = try requiredPrompt(
            values["009-composite-translation-template.txt"],
            name: "009-composite-translation-template.txt",
            path: directory.appendingPathComponent("009-composite-translation-template.txt")
        )
        guard compositeTranslationTemplate.contains("{target_language}") else {
            throw UntypeError.invalidConfiguration(
                "Prompt file \(displayPath(directory.appendingPathComponent("009-composite-translation-template.txt"))) must contain the {target_language} placeholder."
            )
        }

        let sonioxContext = optionalPrompt(values["004-soniox-transcription-context.txt"])
        let elevenLabsPreviousText = optionalPrompt(values["005-elevenlabs-previous-text.txt"])
        let elevenLabsKeyterms = parsePromptLines(values["006-elevenlabs-keyterms.txt"] ?? "")

        switch provider {
        case .soniox:
            if let sonioxContext, sonioxContext.count > 10_000 {
                throw UntypeError.invalidConfiguration(
                    "Prompt file \(displayPath(directory.appendingPathComponent("004-soniox-transcription-context.txt"))) must be 10000 characters or fewer for Soniox context."
                )
            }
        case .elevenlabs:
            if let elevenLabsPreviousText, elevenLabsPreviousText.count > 50 {
                throw UntypeError.invalidConfiguration(
                    "Prompt file \(displayPath(directory.appendingPathComponent("005-elevenlabs-previous-text.txt"))) must be 50 characters or fewer for ElevenLabs previous_text context."
                )
            }
            if elevenLabsKeyterms.count > 50 {
                throw UntypeError.invalidConfiguration(
                    "Prompt file \(displayPath(directory.appendingPathComponent("006-elevenlabs-keyterms.txt"))) must contain 50 or fewer ElevenLabs keyterms."
                )
            }
            if let invalidKeyterm = elevenLabsKeyterms.first(where: { $0.count > 20 }) {
                throw UntypeError.invalidConfiguration(
                    "ElevenLabs keyterm '\(invalidKeyterm)' in \(displayPath(directory.appendingPathComponent("006-elevenlabs-keyterms.txt"))) must be 20 characters or fewer."
                )
            }
        }

        return PromptConfig(
            refinementSystemPrompt: try requiredPrompt(
                values["001-refinement-system.txt"],
                name: "001-refinement-system.txt",
                path: directory.appendingPathComponent("001-refinement-system.txt")
            ),
            translationSystemPrompt: try requiredPrompt(
                values["002-translation-system.txt"],
                name: "002-translation-system.txt",
                path: directory.appendingPathComponent("002-translation-system.txt")
            ),
            translationUserPromptTemplate: translationTemplate,
            compositeSystemPrompt: try requiredPrompt(
                values["007-composite-refine-translate-system.txt"],
                name: "007-composite-refine-translate-system.txt",
                path: directory.appendingPathComponent("007-composite-refine-translate-system.txt")
            ),
            compositeRefinementPromptTemplate: compositeRefinementTemplate,
            compositeTranslationPromptTemplate: compositeTranslationTemplate,
            sonioxTranscriptionContext: sonioxContext,
            elevenLabsPreviousText: elevenLabsPreviousText,
            elevenLabsKeyterms: elevenLabsKeyterms
        )
    }

    private func promptDirectory() -> URL {
        home
            .appendingPathComponent(".tool-agents")
            .appendingPathComponent("untype")
            .appendingPathComponent("prompts")
    }

    private func ensurePromptDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        let configRoot = home.appendingPathComponent(".tool-agents")
        let appDirectory = configRoot.appendingPathComponent("untype")
        for url in [configRoot, appDirectory, directory] {
            do {
                if !fileManager.fileExists(atPath: url.path) {
                    try fileManager.createDirectory(
                        at: url,
                        withIntermediateDirectories: false,
                        attributes: [.posixPermissions: 0o700]
                    )
                }
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            } catch {
                throw UntypeError.invalidConfiguration(
                    "Unable to create prompt configuration folder at \(displayPath(url)): \(error.localizedDescription)"
                )
            }
        }
    }

    private func writeDefaultPrompt(_ content: String, to url: URL) throws {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw UntypeError.invalidConfiguration(
                "Unable to create default prompt file \(displayPath(url)): \(error.localizedDescription)"
            )
        }
    }

    private func readPromptFile(_ url: URL, required: Bool) throws -> String {
        let value: String
        do {
            value = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw UntypeError.invalidConfiguration(
                "Unable to read prompt file \(displayPath(url)): \(error.localizedDescription)"
            )
        }
        if required && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw UntypeError.invalidConfiguration(
                "Prompt file \(displayPath(url)) must not be empty."
            )
        }
        return value
    }

    private func requiredPrompt(_ value: String?, name: String, path: URL) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UntypeError.invalidConfiguration("Prompt file \(displayPath(path)) must not be empty.")
        }
        return value
    }

    private func optionalPrompt(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : value
    }

    private func parsePromptLines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func displayPath(_ url: URL) -> String {
        let homePath = home.path
        if url.path == homePath {
            return "~"
        }
        if url.path.hasPrefix(homePath + "/") {
            return "~/" + String(url.path.dropFirst(homePath.count + 1))
        }
        return url.path
    }

    private func resolveString(
        flagValue: String?,
        chain: EnvChain,
        envKey: String,
        defaultValue: String
    ) -> String {
        if let flagValue {
            return flagValue
        }
        return chain.get(envKey)?.value ?? defaultValue
    }

    private static let allowedLLMReasoningEfforts = ["none", "minimal", "low", "medium", "high"]

    private func resolveLLMMaxOutputTokens(parsed: ParsedArguments, chain: EnvChain) throws -> Int? {
        let raw = resolveString(
            flagValue: parsed.value(for: "--llm-max-output-tokens"),
            chain: chain,
            envKey: "UNTYPE_LLM_MAX_OUTPUT_TOKENS",
            defaultValue: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return nil
        }
        guard let value = Int(raw), value > 0 else {
            throw UntypeError.invalidConfiguration(
                "--llm-max-output-tokens / UNTYPE_LLM_MAX_OUTPUT_TOKENS must be a positive integer. Got: '\(raw)'."
            )
        }
        return value
    }

    private func resolveLLMReasoningEffort(parsed: ParsedArguments, chain: EnvChain) throws -> String? {
        let raw = resolveString(
            flagValue: parsed.value(for: "--llm-reasoning-effort"),
            chain: chain,
            envKey: "UNTYPE_LLM_REASONING_EFFORT",
            defaultValue: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else {
            return nil
        }
        guard Self.allowedLLMReasoningEfforts.contains(raw) else {
            throw UntypeError.invalidConfiguration(
                "--llm-reasoning-effort / UNTYPE_LLM_REASONING_EFFORT must be one of: \(Self.allowedLLMReasoningEfforts.joined(separator: ", ")). Got: '\(raw)'."
            )
        }
        return raw
    }

    private static func defaultReleaseLatencyLogURL(home: URL) -> URL {
        home
            .appendingPathComponent(".tool-agents")
            .appendingPathComponent("untype")
            .appendingPathComponent("release-latency.jsonl")
    }

    private func resolvePath(
        _ raw: String?,
        defaultURL: URL,
        flagName: String,
        envName: String
    ) throws -> String {
        guard let raw else {
            return defaultURL.path
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw UntypeError.invalidConfiguration("\(flagName) / \(envName) must not be empty.")
        }
        if value == "~" {
            return home.path
        }
        if value.hasPrefix("~/") {
            return home.appendingPathComponent(String(value.dropFirst(2))).path
        }
        return URL(fileURLWithPath: value).path
    }

    private func validateLegacyConfigFolderMigration() throws {
        let configRoot = home.appendingPathComponent(".tool-agents")
        let currentConfigDirectory = configRoot.appendingPathComponent("untype")
        let legacyConfigDirectory = configRoot.appendingPathComponent("mic-tool-ts")
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: currentConfigDirectory.path),
           fileManager.fileExists(atPath: legacyConfigDirectory.path) {
            throw UntypeError.missingConfiguration(
                "Config folder not found at ~/.tool-agents/untype/. Detected legacy folder at ~/.tool-agents/mic-tool-ts/. Migrate with: mv ~/.tool-agents/mic-tool-ts ~/.tool-agents/untype"
            )
        }
    }

    private func parseBoolean(_ raw: String?, flagName: String, envName: String) throws -> Bool? {
        guard let raw else {
            return nil
        }
        switch raw.lowercased() {
        case "true", "yes", "on", "1":
            return true
        case "false", "no", "off", "0":
            return false
        default:
            throw UntypeError.invalidConfiguration(
                "\(flagName) / \(envName) must be one of: true, false, yes, no, on, off, 1, 0. Got: '\(raw)'."
            )
        }
    }

    private func parsePositiveInt(
        _ raw: String,
        flagName: String,
        envName: String,
        min: Int,
        max: Int
    ) throws -> Int {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(value), String(parsed) == value, parsed > 0 else {
            throw UntypeError.invalidConfiguration(
                "\(flagName) / \(envName) must be a positive integer. Got: '\(raw)'."
            )
        }
        if parsed < min {
            throw UntypeError.invalidConfiguration("\(flagName) / \(envName) must be >= \(min). Got: \(parsed).")
        }
        if parsed > max {
            throw UntypeError.invalidConfiguration("\(flagName) / \(envName) must be <= \(max). Got: \(parsed).")
        }
        return parsed
    }

    private func parseCsvNonEmpty(_ raw: String, flagName: String, envName: String) throws -> [String] {
        let values = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if values.isEmpty {
            throw UntypeError.invalidConfiguration("\(flagName) / \(envName) must contain at least one non-empty value.")
        }
        return values
    }

    private func parseWsUrl(_ raw: String, flagName: String, envName: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidScheme = value.lowercased().hasPrefix("wss://") || value.lowercased().hasPrefix("ws://")
        let urlRemainder = value.drop(while: { $0 != "/" })
        if !hasValidScheme || value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || urlRemainder.count <= 2 {
            throw UntypeError.invalidConfiguration(
                "\(flagName) / \(envName) must be a wss:// or ws:// URL. Got: '\(raw)'."
            )
        }
        return value
    }

    private func optionalIsoDate(_ raw: String?, flagName: String, envName: String) throws -> String? {
        guard let raw else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard value.count == 10, let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw UntypeError.invalidConfiguration(
                "\(flagName) / \(envName) must be YYYY-MM-DD. Got: '\(raw)'."
            )
        }
        return value
    }

    private func validateLanguages(_ rawValues: [String]) throws -> [String] {
        var values: [String] = []
        for raw in rawValues {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value == "auto" {
                values.append(value)
                continue
            }
            let range = NSRange(location: 0, length: value.utf16.count)
            let regex = try NSRegularExpression(pattern: #"^[a-z]{2,3}(-[A-Z]{2})?$"#)
            if regex.firstMatch(in: value, range: range) == nil {
                throw UntypeError.invalidConfiguration(
                    "--language must be 'auto' or an ISO 639-1/2 code (e.g. 'en', 'es', 'pt-BR'). Got: '\(raw)'."
                )
            }
            values.append(value)
        }
        if values.contains("auto") && values.count > 1 {
            throw UntypeError.invalidConfiguration("--language 'auto' cannot be combined with other language hints.")
        }
        return values
    }

    private func validateGuardPhrase(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            throw UntypeError.invalidConfiguration("--guard-phrase must not be empty.")
        }
        let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            throw UntypeError.invalidConfiguration(
                "--guard-phrase must contain at least one letter or digit after normalization. Got: '\(raw)'."
            )
        }
        return value
    }

    private func validateProtocolPhrase(_ raw: String, flagName: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            throw UntypeError.invalidConfiguration("\(flagName) must not be empty.")
        }
        return value
    }

    private func configuredSource(_ flagValue: String?, chain: EnvChain, envKey: String) -> ProtocolSettingSource {
        flagValue != nil || chain.get(envKey) != nil ? .configured : .default
    }

    private func resolveLLMProviderConfig(
        enabled: Bool,
        provider: LLMProvider,
        model: String,
        chain: EnvChain,
        validateRequiredSettings: Bool
    ) throws -> ProviderConfig {
        switch provider {
        case .azureOpenAI:
            let deployment = chain.get("AZURE_OPENAI_DEPLOYMENT")?.value ?? model
            let apiVersion = chain.get("AZURE_OPENAI_API_VERSION")?.value ?? Self.defaultAzureAPIVersion
            guard enabled, validateRequiredSettings else {
                return .azureOpenAI(apiKey: "", endpoint: "", deployment: deployment, apiVersion: apiVersion)
            }
            let apiKey = chain.get("AZURE_OPENAI_API_KEY")?.value
            let endpoint = chain.get("AZURE_OPENAI_ENDPOINT")?.value
            var missing: [String] = []
            if apiKey == nil {
                missing.append("AZURE_OPENAI_API_KEY")
            }
            if endpoint == nil {
                missing.append("AZURE_OPENAI_ENDPOINT")
            }
            if !missing.isEmpty {
                throw UntypeError.invalidConfiguration(
                    "Azure OpenAI is enabled (--refine on, --llm-provider=azure-openai) but the following env vars are not set in any of: CLI flag, ./.env, ~/.tool-agents/untype/.env, shell env - \(missing.joined(separator: ", ")). Set them or run with --no-refine to disable LLM refinement."
                )
            }
            return .azureOpenAI(apiKey: apiKey!, endpoint: endpoint!, deployment: deployment, apiVersion: apiVersion)
        case .google:
            guard enabled, validateRequiredSettings else {
                return .google(apiKey: "")
            }
            guard let apiKey = chain.get("GOOGLE_API_KEY")?.value else {
                throw UntypeError.invalidConfiguration(
                    "Google Gemini is enabled (--refine on, --llm-provider=google) but GOOGLE_API_KEY is not set in any of: CLI flag, ./.env, ~/.tool-agents/untype/.env, shell env. Set it or run with --no-refine to disable LLM refinement."
                )
            }
            return .google(apiKey: apiKey)
        case .openAI, .anthropic, .azureAIInference, .ollama, .litellm, .openAICompat:
            return .unimplemented(provider: provider)
        }
    }

    private func expiryWarnings(envName: String, isoDate: String?) -> [String] {
        guard let isoDate else {
            return []
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let expiry = formatter.date(from: isoDate) else {
            return []
        }
        let days = Calendar(identifier: .gregorian)
            .dateComponents([.day], from: Calendar(identifier: .gregorian).startOfDay(for: now), to: expiry)
            .day ?? 0
        if days < 0 {
            return ["[untype] WARNING: \(envName) expired \(abs(days)) day\(abs(days) == 1 ? "" : "s") ago (\(isoDate)). Renew the credential."]
        }
        if days <= 14 {
            return ["[untype] WARNING: \(envName) expires in \(days) day\(days == 1 ? "" : "s") (\(isoDate)). Plan a renewal."]
        }
        return []
    }
}

struct ParsedArguments: Sendable {
    private let values: [String: [String]]
    private let switches: [String: Bool]
    let refineOverride: Bool?

    init(argv: [String]) throws {
        var values: [String: [String]] = [:]
        var switches: [String: Bool] = [:]
        var refineOverride: Bool?
        var index = 0
        while index < argv.count {
            let original = argv[index]
            let split = Self.splitEquals(original)
            let arg = split.flag
            switch arg {
            case "--no-refine":
                refineOverride = false
                index += 1
            case "--refine":
                refineOverride = true
                index += 1
            case "-v", "--verbose":
                switches["--verbose"] = true
                index += 1
            case "--endpoint-detection":
                switches["--endpoint-detection"] = true
                index += 1
            case "--no-endpoint-detection":
                switches["--endpoint-detection"] = false
                index += 1
            case "--quick-close":
                switches["--quick-close"] = true
                index += 1
            case "--no-quick-close":
                switches["--quick-close"] = false
                index += 1
            case "--release-latency-log":
                switches["--release-latency-log"] = true
                index += 1
            case "--no-release-latency-log":
                switches["--release-latency-log"] = false
                index += 1
            case "--api-key", "--api-key-expires-at", "--elevenlabs-api-key", "--elevenlabs-api-key-expires-at",
                "--stt-provider", "--model", "--endpoint", "--language", "--sample-rate", "--output-mode",
                "--guard-phrase", "--interaction-mode", "--command-phrase", "--section-end-phrase",
                "--section-cancel-phrase", "--literal-next-phrase", "--refine-default", "--translate-default",
                "--translation-policy", "--clipboard-default", "--input-default", "--protocol-output",
                "--llm-provider", "--llm-model", "--llm-max-output-tokens", "--llm-reasoning-effort",
                "--release-latency-log-path":
                let value: String
                if let inline = split.value {
                    value = inline
                } else {
                    guard index + 1 < argv.count else {
                        throw UntypeError.invalidConfiguration("\(arg) requires a value.")
                    }
                    value = argv[index + 1]
                    index += 1
                }
                values[arg, default: []].append(value)
                index += 1
            default:
                if arg.hasPrefix("--") {
                    throw UntypeError.invalidConfiguration("Unknown option: \(arg).")
                }
                if arg.hasPrefix("-") {
                    throw UntypeError.invalidConfiguration("Unknown option: \(arg).")
                }
                throw UntypeError.invalidConfiguration("Unknown argument: \(arg).")
            }
        }

        self.values = values
        self.switches = switches
        self.refineOverride = refineOverride
    }

    func value(for flag: String) -> String? {
        values[flag]?.last
    }

    func values(for flag: String) -> [String] {
        values[flag] ?? []
    }

    func switchValue(for flag: String) -> Bool? {
        switches[flag]
    }

    private static func splitEquals(_ arg: String) -> (flag: String, value: String?) {
        guard arg.hasPrefix("--"), let equals = arg.firstIndex(of: "=") else {
            return (arg, nil)
        }
        return (String(arg[..<equals]), String(arg[arg.index(after: equals)...]))
    }
}
