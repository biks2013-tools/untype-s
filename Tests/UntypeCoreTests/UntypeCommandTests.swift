import Foundation
import Testing
@testable import UntypeCore

@Test func helpWritesToStdoutAndExitsZero() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    let command = UntypeCommand(stdout: stdout, stderr: stderr)

    let code = await command.run(["--help"])

    #expect(code == ExitCode.success.rawValue)
    #expect(stdout.text.contains("Usage: untype"))
    #expect(stdout.text.contains("untype ui"))
    #expect(stdout.text.contains("--quick-close"))
    #expect(stdout.text.contains("--release-latency-log"))
    #expect(stdout.text.contains("~/.tool-agents/untype/prompts/"))
    #expect(stderr.text.isEmpty)
}

@Test func versionWritesSemanticVersionAndExitsZero() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    let command = UntypeCommand(stdout: stdout, stderr: stderr)

    let code = await command.run(["--version"])

    #expect(code == ExitCode.success.rawValue)
    #expect(stdout.text == "\(UntypeCommand.version)\n")
    #expect(stderr.text.isEmpty)
}

@Test func uiCommandDispatchesNativeLauncher() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    var launched = false
    let command = UntypeCommand(
        stdout: stdout,
        stderr: stderr,
        uiLauncher: {
            launched = true
            return ExitCode.success.rawValue
        }
    )

    let code = await command.run(["ui"])

    #expect(code == ExitCode.success.rawValue)
    #expect(launched)
    #expect(stdout.text.isEmpty)
    #expect(stderr.text.isEmpty)
}

@Test func uiCommandMapsLauncherUntypeErrors() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    let command = UntypeCommand(
        stdout: stdout,
        stderr: stderr,
        uiLauncher: {
            throw UntypeError.invalidConfiguration("bad ui config")
        }
    )

    let code = await command.run(["ui"])

    #expect(code == ExitCode.configuration.rawValue)
    #expect(stderr.text.contains("invalid_configuration: bad ui config"))
}

@Test func missingDefaultProviderApiKeyExitsWithConfigurationError() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    let temp = TemporaryDirectory()
    let command = UntypeCommand(
        stdout: stdout,
        stderr: stderr,
        resolverFactory: {
            ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
        }
    )

    let code = await command.run([])

    #expect(code == ExitCode.configuration.rawValue)
    #expect(stdout.text.isEmpty)
    #expect(stderr.text.contains("missing_configuration"))
    #expect(stderr.text.contains("SONIOX_API_KEY"))
}

@Test func missingProviderApiKeyStillProvisionsPromptFilesAtStartup() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    let temp = TemporaryDirectory()
    let command = UntypeCommand(
        stdout: stdout,
        stderr: stderr,
        resolverFactory: {
            ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
        }
    )

    let code = await command.run([])

    let promptDirectory = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
        .appendingPathComponent("prompts")
    #expect(code == ExitCode.configuration.rawValue)
    #expect(FileManager.default.fileExists(atPath: promptDirectory.path))
    #expect(FileManager.default.fileExists(
        atPath: promptDirectory.appendingPathComponent("001-refinement-system.txt").path
    ))
    #expect(stderr.text.contains("SONIOX_API_KEY"))
}

@Test func localEnvBeatsShellEnvironment() throws {
    let temp = TemporaryDirectory()
    try "SONIOX_API_KEY=local-key\n".write(
        to: temp.url.appendingPathComponent(".env"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(
        cwd: temp.url,
        home: temp.url,
        shell: ["SONIOX_API_KEY": "shell-key"]
    )

    let config = try resolver.resolve(argv: ["--no-refine"])

    #expect(config.apiKey == "local-key")
    #expect(config.apiKeySource == .localEnv)
}

@Test func flagBeatsLocalEnv() throws {
    let temp = TemporaryDirectory()
    try "SONIOX_API_KEY=local-key\n".write(
        to: temp.url.appendingPathComponent(".env"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: ["--api-key", "flag-key", "--no-refine"])

    #expect(config.apiKey == "flag-key")
    #expect(config.apiKeySource == .flag)
}

@Test func releaseLatencyLoggingIsDisabledByDefaultWithDocumentedUserPath() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: ["--api-key", "test-key", "--no-refine"])

    #expect(config.releaseLatencyLogging.enabled == false)
    #expect(config.releaseLatencyLogging.path == temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
        .appendingPathComponent("release-latency.jsonl")
        .path)
}

@Test func releaseLatencyLoggingCanBeEnabledByEnvAndPathOverriddenByFlag() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(
        cwd: temp.url,
        home: temp.url,
        shell: [
            "SONIOX_API_KEY": "test-key",
            "UNTYPE_RELEASE_LATENCY_LOG": "on",
            "UNTYPE_RELEASE_LATENCY_LOG_PATH": temp.url.appendingPathComponent("env.jsonl").path
        ]
    )
    let flagPath = temp.url.appendingPathComponent("flag.jsonl").path

    let config = try resolver.resolve(argv: [
        "--no-refine",
        "--release-latency-log-path", flagPath
    ])

    #expect(config.releaseLatencyLogging.enabled)
    #expect(config.releaseLatencyLogging.path == flagPath)
}

@Test func promptFilesAreProvisionedAndLoadedFromUserConfigFolder() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: ["--api-key", "test-key", "--no-refine"])

    let promptDirectory = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
        .appendingPathComponent("prompts")
    for file in UntypePromptDefaults.promptFiles {
        #expect(FileManager.default.fileExists(atPath: promptDirectory.appendingPathComponent(file.name).path))
    }
    #expect(config.prompts.refinementSystemPrompt == UntypePromptDefaults.refinementSystemPrompt)
    #expect(config.prompts.translationSystemPrompt == UntypePromptDefaults.translationSystemPrompt)
    #expect(config.prompts.translationUserPromptTemplate == UntypePromptDefaults.translationUserPromptTemplate)
    #expect(config.prompts.compositeSystemPrompt == UntypePromptDefaults.compositeSystemPrompt)
    #expect(config.prompts.compositeRefinementPromptTemplate == UntypePromptDefaults.compositeRefinementPromptTemplate)
    #expect(config.prompts.compositeTranslationPromptTemplate == UntypePromptDefaults.compositeTranslationPromptTemplate)
    #expect(config.prompts.sonioxTranscriptionContext == nil)
    #expect(config.prompts.elevenLabsPreviousText == nil)
    #expect(config.prompts.elevenLabsKeyterms.isEmpty)
}

@Test func customPromptFilesAreLoadedFromUserConfigFolder() throws {
    let temp = TemporaryDirectory()
    let promptDirectory = try makePromptDirectory(in: temp)
    try "Refine as terse technical prose.".write(
        to: promptDirectory.appendingPathComponent("001-refinement-system.txt"),
        atomically: true,
        encoding: .utf8
    )
    try "Translate with identifier preservation.".write(
        to: promptDirectory.appendingPathComponent("002-translation-system.txt"),
        atomically: true,
        encoding: .utf8
    )
    try "Target={target_language}\n{text}".write(
        to: promptDirectory.appendingPathComponent("003-translation-user-template.txt"),
        atomically: true,
        encoding: .utf8
    )
    try "This dictation is about Swift package maintenance.".write(
        to: promptDirectory.appendingPathComponent("004-soniox-transcription-context.txt"),
        atomically: true,
        encoding: .utf8
    )
    try "Do both steps and return JSON.".write(
        to: promptDirectory.appendingPathComponent("007-composite-refine-translate-system.txt"),
        atomically: true,
        encoding: .utf8
    )
    try "Clean {text}".write(
        to: promptDirectory.appendingPathComponent("008-composite-refinement-template.txt"),
        atomically: true,
        encoding: .utf8
    )
    try "Translate to {target_language}".write(
        to: promptDirectory.appendingPathComponent("009-composite-translation-template.txt"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: ["--api-key", "test-key", "--no-refine"])

    #expect(config.prompts.refinementSystemPrompt == "Refine as terse technical prose.")
    #expect(config.prompts.translationSystemPrompt == "Translate with identifier preservation.")
    #expect(config.prompts.translationUserPromptTemplate == "Target={target_language}\n{text}")
    #expect(config.prompts.compositeSystemPrompt == "Do both steps and return JSON.")
    #expect(config.prompts.compositeRefinementPromptTemplate == "Clean {text}")
    #expect(config.prompts.compositeTranslationPromptTemplate == "Translate to {target_language}")
    #expect(config.prompts.sonioxTranscriptionContext == "This dictation is about Swift package maintenance.")
}

@Test func emptyRequiredPromptFileRaisesConfigurationError() throws {
    let temp = TemporaryDirectory()
    let promptDirectory = try makePromptDirectory(in: temp)
    try "".write(
        to: promptDirectory.appendingPathComponent("001-refinement-system.txt"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: ["--api-key", "test-key", "--no-refine"])
    }
}

@Test func translationPromptTemplateMustContainRequiredPlaceholders() throws {
    let temp = TemporaryDirectory()
    let promptDirectory = try makePromptDirectory(in: temp)
    try "Translate now.".write(
        to: promptDirectory.appendingPathComponent("003-translation-user-template.txt"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: ["--api-key", "test-key", "--no-refine"])
    }
}

@Test func compositePromptTemplatesMustContainRequiredPlaceholders() throws {
    let temp = TemporaryDirectory()
    let promptDirectory = try makePromptDirectory(in: temp)
    try "Clean without source placeholder.".write(
        to: promptDirectory.appendingPathComponent("008-composite-refinement-template.txt"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: ["--api-key", "test-key", "--no-refine"])
    }

    let secondTemp = TemporaryDirectory()
    let secondPromptDirectory = try makePromptDirectory(in: secondTemp)
    try "Translate without target placeholder.".write(
        to: secondPromptDirectory.appendingPathComponent("009-composite-translation-template.txt"),
        atomically: true,
        encoding: .utf8
    )
    let secondResolver = ConfigResolver(cwd: secondTemp.url, home: secondTemp.url, shell: [:])

    #expect(throws: UntypeError.self) {
        _ = try secondResolver.resolve(argv: ["--api-key", "test-key", "--no-refine"])
    }
}

@Test func elevenLabsPromptConstraintsAreValidatedAtStartup() throws {
    let temp = TemporaryDirectory()
    let promptDirectory = try makePromptDirectory(in: temp)
    try "This previous text prompt is intentionally far longer than fifty chars.".write(
        to: promptDirectory.appendingPathComponent("005-elevenlabs-previous-text.txt"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: [
            "--stt-provider", "elevenlabs",
            "--elevenlabs-api-key", "xi-key",
            "--no-refine"
        ])
    }
}

@Test func userEnvBeatsShellEnvironment() throws {
    let temp = TemporaryDirectory()
    let userConfig = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
    try FileManager.default.createDirectory(at: userConfig, withIntermediateDirectories: true)
    try "SONIOX_API_KEY=user-key\n".write(
        to: userConfig.appendingPathComponent(".env"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(
        cwd: temp.url,
        home: temp.url,
        shell: ["SONIOX_API_KEY": "shell-key"]
    )

    let config = try resolver.resolve(argv: ["--no-refine"])

    #expect(config.apiKey == "user-key")
    #expect(config.apiKeySource == .userEnv)
}

@Test func localDotenvParsingEdgeCasesMatchSourceContract() throws {
    let temp = TemporaryDirectory()
    try """
    # comment-only line
    export SONIOX_API_KEY="quoted-local-key"
    UNTYPE_MODEL='quoted-model'
    UNTYPE_LANGUAGES=el,en # inline comment

    """.write(
        to: temp.url.appendingPathComponent(".env"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: ["--no-refine"])

    #expect(config.apiKey == "quoted-local-key")
    #expect(config.apiKeySource == .localEnv)
    #expect(config.model == "quoted-model")
    #expect(config.languages == ["el", "en"])
}

@Test func emptyAndWhitespaceOnlyDotenvValuesFallThroughToLowerPrioritySources() throws {
    let temp = TemporaryDirectory()
    try """
    SONIOX_API_KEY=    
    UNTYPE_MODEL=
    """.write(
        to: temp.url.appendingPathComponent(".env"),
        atomically: true,
        encoding: .utf8
    )
    let resolver = ConfigResolver(
        cwd: temp.url,
        home: temp.url,
        shell: [
            "SONIOX_API_KEY": "shell-key",
            "UNTYPE_MODEL": "shell-model"
        ]
    )

    let config = try resolver.resolve(argv: ["--no-refine"])

    #expect(config.apiKey == "shell-key")
    #expect(config.apiKeySource == .shellEnv)
    #expect(config.model == "shell-model")
}

@Test func legacyConfigFolderWithoutCurrentFolderRaisesMigrationHint() throws {
    let temp = TemporaryDirectory()
    let legacyConfig = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("mic-tool-ts")
    try FileManager.default.createDirectory(at: legacyConfig, withIntermediateDirectories: true)
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: ["SONIOX_API_KEY": "shell-key"])

    #expect(throws: UntypeError.missingConfiguration(
        "Config folder not found at ~/.tool-agents/untype/. Detected legacy folder at ~/.tool-agents/mic-tool-ts/. Migrate with: mv ~/.tool-agents/mic-tool-ts ~/.tool-agents/untype"
    )) {
        _ = try resolver.resolve(argv: ["--no-refine"])
    }
}

@Test func legacyConfigFolderDoesNotBlockWhenCurrentFolderExists() throws {
    let temp = TemporaryDirectory()
    let configRoot = temp.url.appendingPathComponent(".tool-agents")
    try FileManager.default.createDirectory(
        at: configRoot.appendingPathComponent("mic-tool-ts"),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: configRoot.appendingPathComponent("untype"),
        withIntermediateDirectories: true
    )
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: ["SONIOX_API_KEY": "shell-key"])

    let config = try resolver.resolve(argv: ["--no-refine"])

    #expect(config.apiKey == "shell-key")
}

@Test func resolvesDocumentedProviderDefaultsWithRefineDisabled() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: ["--api-key", "flag-key", "--no-refine"])

    #expect(config.sttProvider == .soniox)
    #expect(config.model == "stt-rt-v4")
    #expect(config.endpoint == "wss://stt-rt.soniox.com/transcribe-websocket")
    #expect(config.languages == ["el", "en"])
    #expect(config.sampleRate == 16_000)
    #expect(config.enableEndpointDetection)
    #expect(config.quickClose == false)
    #expect(config.outputMode == .overwrite)
    #expect(config.protocolConfig.interactionMode == .dictation)
    #expect(config.protocolConfig.translationPolicy == .opposite)
    #expect(config.llm.enabled == false)
}

@Test func elevenLabsProviderRequiresItsOwnApiKeyOnly() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: ["SONIOX_API_KEY": "soniox-key"])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: ["--stt-provider", "elevenlabs", "--no-refine"])
    }
}

@Test func elevenLabsProviderUsesProviderSpecificDefaults() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    let config = try resolver.resolve(argv: [
        "--stt-provider", "elevenlabs",
        "--elevenlabs-api-key", "xi-key",
        "--no-refine"
    ])

    #expect(config.sttProvider == .elevenlabs)
    #expect(config.apiKey == "xi-key")
    #expect(config.apiKeyEnvName == "ELEVENLABS_API_KEY")
    #expect(config.model == "scribe_v2_realtime")
    #expect(config.endpoint == "wss://api.elevenlabs.io/v1/speech-to-text/realtime")
    #expect(config.languages == ["auto"])
}

@Test func validatesLanguageAutoCannotBeCombined() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: [
            "--api-key", "flag-key",
            "--language", "auto",
            "--language", "en",
            "--no-refine"
        ])
    }
}

@Test func hybridModeRequiresProtocolOutput() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: [
            "--api-key", "flag-key",
            "--interaction-mode", "hybrid",
            "--no-refine"
        ])
    }
}

@Test func endpointDetectionFlagOverridesEnvironment() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(
        cwd: temp.url,
        home: temp.url,
        shell: [
            "SONIOX_API_KEY": "shell-key",
            "UNTYPE_ENABLE_ENDPOINT_DETECTION": "true"
        ]
    )

    let config = try resolver.resolve(argv: ["--no-endpoint-detection", "--no-refine"])

    #expect(config.enableEndpointDetection == false)
}

@Test func quickCloseFlagOverridesEnvironment() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(
        cwd: temp.url,
        home: temp.url,
        shell: [
            "SONIOX_API_KEY": "shell-key",
            "UNTYPE_QUICK_CLOSE": "true"
        ]
    )

    let config = try resolver.resolve(argv: ["--no-quick-close", "--no-refine"])

    #expect(config.quickClose == false)
}

@Test func quickCloseCanBeEnabledFromEnvironment() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(
        cwd: temp.url,
        home: temp.url,
        shell: [
            "SONIOX_API_KEY": "shell-key",
            "UNTYPE_QUICK_CLOSE": "on"
        ]
    )

    let config = try resolver.resolve(argv: ["--no-refine"])

    #expect(config.quickClose)
}

@Test func defaultLlmStartupValidationIsFatalWhenRefineEnabled() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: ["SONIOX_API_KEY": "shell-key"])

    #expect(throws: UntypeError.self) {
        _ = try resolver.resolve(argv: [])
    }
}

@Test func azureLlmConfigResolvesWhenRequiredEnvironmentExists() throws {
    let temp = TemporaryDirectory()
    let resolver = ConfigResolver(
        cwd: temp.url,
        home: temp.url,
        shell: [
            "SONIOX_API_KEY": "shell-key",
            "AZURE_OPENAI_API_KEY": "azure-key",
            "AZURE_OPENAI_ENDPOINT": "https://example.openai.azure.com",
            "AZURE_OPENAI_DEPLOYMENT": "deployment-name"
        ]
    )

    let config = try resolver.resolve(argv: ["--llm-model", "gpt-test"])

    #expect(config.llm.enabled)
    #expect(config.llm.provider == .azureOpenAI)
    #expect(config.llm.model == "gpt-test")
    #expect(config.llm.providerConfig == .azureOpenAI(
        apiKey: "azure-key",
        endpoint: "https://example.openai.azure.com",
        deployment: "deployment-name",
        apiVersion: "2024-10-21"
    ))
}

@Test func expiryWarningIsEmittedForSoonCredential() throws {
    let temp = TemporaryDirectory()
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    let now = formatter.date(from: "2026-05-23")!
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:], now: now)

    let config = try resolver.resolve(argv: [
        "--api-key", "flag-key",
        "--api-key-expires-at", "2026-05-30",
        "--no-refine"
    ])

    #expect(config.apiKeyExpiresAt == "2026-05-30")
    #expect(config.warnings.contains("[untype] WARNING: SONIOX_API_KEY expires in 7 days (2026-05-30). Plan a renewal."))
}

@Test func unknownFlagExitsWithConfigurationError() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    let temp = TemporaryDirectory()
    let command = UntypeCommand(
        stdout: stdout,
        stderr: stderr,
        resolverFactory: {
            ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
        }
    )

    let code = await command.run(["--does-not-exist"])

    #expect(code == ExitCode.configuration.rawValue)
    #expect(stdout.text.isEmpty)
    #expect(stderr.text.contains("invalid_configuration"))
    #expect(stderr.text.contains("Unknown option: --does-not-exist"))
}

@Test func commandStartsRuntimeWaitsThenStopsWithPendingSubmit() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    let temp = TemporaryDirectory()
    let fakeRuntime = FakeCommandRuntime()
    let command = UntypeCommand(
        stdout: stdout,
        stderr: stderr,
        resolverFactory: {
            ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
        },
        runtimeFactory: { config, _, _, stdoutIsTTY in
            #expect(config.sttProvider == .soniox)
            #expect(stdoutIsTTY == false)
            return fakeRuntime
        },
        waitForShutdown: {
            "test-shutdown"
        }
    )

    let code = await command.run(["--api-key", "flag-key", "--no-refine"])

    #expect(code == ExitCode.success.rawValue)
    #expect(fakeRuntime.started)
    #expect(fakeRuntime.stopReason == "test-shutdown")
    #expect(fakeRuntime.stopSubmitPending == true)
}

@Test func commandReturnsRecordedRuntimeFailureAfterShutdown() async {
    let stdout = MemoryOutput()
    let stderr = MemoryOutput()
    let temp = TemporaryDirectory()
    let fakeRuntime = FakeCommandRuntime()
    fakeRuntime.failure = UntypeError.sonioxNetwork("lost")
    let command = UntypeCommand(
        stdout: stdout,
        stderr: stderr,
        resolverFactory: {
            ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
        },
        runtimeFactory: { _, _, _, _ in fakeRuntime },
        waitForShutdown: {
            "test-shutdown"
        }
    )

    let code = await command.run(["--api-key", "flag-key", "--no-refine"])

    #expect(code == ExitCode.providerNetwork.rawValue)
    #expect(stderr.text.contains("soniox_network: lost"))
}

private final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-s-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func makePromptDirectory(in temp: TemporaryDirectory) throws -> URL {
    let promptDirectory = temp.url
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent("untype")
        .appendingPathComponent("prompts")
    try FileManager.default.createDirectory(at: promptDirectory, withIntermediateDirectories: true)
    return promptDirectory
}

private final class FakeCommandRuntime: UntypeRuntimeSession, @unchecked Sendable {
    var started = false
    var stopReason: String?
    var stopSubmitPending: Bool?
    var failure: Error?

    func start() async throws {
        started = true
    }

    func submitPending() async throws {}

    func stop(reason: String, submitPending: Bool) async {
        stopReason = reason
        stopSubmitPending = submitPending
    }

    func recordedFailure() -> Error? {
        failure
    }

    func toggleOperator(_ key: OperatorKey) async throws {}
}
