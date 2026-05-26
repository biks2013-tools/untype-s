import Foundation

public struct UntypeCommand {
    public static let version = "0.1.0"

    private let stdout: TextOutput
    private let stderr: TextOutput
    private let stdoutIsTTY: Bool
    private let resolverFactory: () -> ConfigResolver
    private let runtimeFactory: (
        _ config: ResolvedConfig,
        _ stdout: TextOutput,
        _ stderr: TextOutput,
        _ stdoutIsTTY: Bool
    ) throws -> UntypeRuntimeSession
    private let waitForShutdown: () async -> String
    private let uiLauncher: () async throws -> Int32

    public init(
        stdout: TextOutput,
        stderr: TextOutput,
        stdoutIsTTY: Bool = false,
        resolverFactory: @escaping () -> ConfigResolver = { ConfigResolver() },
        runtimeFactory: @escaping (
            _ config: ResolvedConfig,
            _ stdout: TextOutput,
            _ stderr: TextOutput,
            _ stdoutIsTTY: Bool
        ) throws -> UntypeRuntimeSession = UntypeRuntimeFactory.make,
        waitForShutdown: @escaping () async -> String = SignalShutdownWaiter.waitForTerminationSignal,
        uiLauncher: @escaping () async throws -> Int32 = {
            try await NativeUntypeUILauncher.launch()
        }
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutIsTTY = stdoutIsTTY
        self.resolverFactory = resolverFactory
        self.runtimeFactory = runtimeFactory
        self.waitForShutdown = waitForShutdown
        self.uiLauncher = uiLauncher
    }

    public func run(_ argv: [String]) async -> Int32 {
        if argv.contains("--help") || argv.contains("-h") {
            stdout.write(Self.helpText)
            return ExitCode.success.rawValue
        }
        if argv.contains("--version") || argv.contains("-V") {
            stdout.write("\(Self.version)\n")
            return ExitCode.success.rawValue
        }
        if argv.first == "ui" {
            do {
                return try await uiLauncher()
            } catch let error as UntypeError {
                return fail(error)
            } catch {
                stderr.write("unknown: \(error.localizedDescription)\n")
                return ExitCode.unknown.rawValue
            }
        }

        do {
            let config = try resolverFactory().resolve(argv: argv)
            for warning in config.warnings {
                stderr.write("\(warning)\n")
            }
            let runtime = try runtimeFactory(config, stdout, stderr, stdoutIsTTY)
            try await runtime.start()
            let shutdownReason = await waitForShutdown()
            await runtime.stop(reason: shutdownReason, submitPending: true)
            if let failure = runtime.recordedFailure() {
                if let failure = failure as? UntypeError {
                    return fail(failure)
                }
                stderr.write("unknown: \(failure.localizedDescription)\n")
                return ExitCode.unknown.rawValue
            }
            return ExitCode.success.rawValue
        } catch let error as UntypeError {
            return fail(error)
        } catch {
            stderr.write("unknown: \(error.localizedDescription)\n")
            return ExitCode.unknown.rawValue
        }
    }

    private func fail(_ error: UntypeError) -> Int32 {
        stderr.write("\(error.diagnosticLine)\n")
        return error.exitCode.rawValue
    }

    public static let helpText = """
    Usage: untype [options]
           untype ui

    Stream microphone audio to a realtime STT provider and print transcripts to stdout.

    Commands:
      ui                                      Open the native macOS monitoring UI.

    Options:
      -h, --help                              Show this help message and exit.
      -V, --version                           Print the untype version and exit.
      --api-key <value>                       Soniox API key. Env: SONIOX_API_KEY.
      --api-key-expires-at <YYYY-MM-DD>       Reminder date for SONIOX_API_KEY renewal. Env: SONIOX_API_KEY_EXPIRES_AT.
      --stt-provider <soniox|elevenlabs>      Realtime transcription provider. Env: UNTYPE_STT_PROVIDER.
      --elevenlabs-api-key <value>            ElevenLabs API key. Env: ELEVENLABS_API_KEY.
      --elevenlabs-api-key-expires-at <date>  Reminder date for ELEVENLABS_API_KEY renewal. Env: ELEVENLABS_API_KEY_EXPIRES_AT.
      --model <name>                          STT provider realtime model. Env: UNTYPE_MODEL.
      --endpoint <wss-url>                    STT provider WebSocket endpoint. Env: UNTYPE_ENDPOINT.
      --language <code>                       Language hint or 'auto'. Env: UNTYPE_LANGUAGES.
      --sample-rate <hz>                      PCM sample rate. Env: UNTYPE_SAMPLE_RATE.
      --quick-close                           Submit latest push-to-talk partial immediately on release. Env: UNTYPE_QUICK_CLOSE.
      --no-quick-close                        Disable Quick Close and wait for provider finalization.
      --release-latency-log                   Append push-to-talk release timing JSONL records. Env: UNTYPE_RELEASE_LATENCY_LOG.
      --no-release-latency-log                Disable push-to-talk release timing logging.
      --release-latency-log-path <path>       JSONL latency log path. Env: UNTYPE_RELEASE_LATENCY_LOG_PATH.
      --endpoint-detection                    Enable provider endpoint/VAD detection. Env: UNTYPE_ENABLE_ENDPOINT_DETECTION.
      --no-endpoint-detection                 Disable provider endpoint/VAD detection.
      --output-mode <mode>                    overwrite, append, or final-only. Env: UNTYPE_OUTPUT_MODE.
      --guard-phrase <phrase>                 Phrase that closes the current turn. Env: UNTYPE_GUARD_PHRASE.
      --interaction-mode <mode>               dictation, agent-protocol, or hybrid. Env: UNTYPE_INTERACTION_MODE.
      --command-phrase <phrase>               Spoken marker for state commands. Env: UNTYPE_COMMAND_PHRASE.
      --section-end-phrase <phrase>           Spoken marker that submits the current section. Env: UNTYPE_SECTION_END_PHRASE.
      --section-cancel-phrase <phrase>        Spoken marker that cancels the current section. Env: UNTYPE_SECTION_CANCEL_PHRASE.
      --literal-next-phrase <phrase>          Treat the next marker as literal dictation. Env: UNTYPE_LITERAL_NEXT_PHRASE.
      --refine-default <on|off>               Initial protocol refine operator state. Env: UNTYPE_REFINE_DEFAULT.
      --translate-default <on|off>            Initial protocol translate operator state. Env: UNTYPE_TRANSLATE_DEFAULT.
      --translation-policy <policy>           opposite, to-en, or to-el. Env: UNTYPE_TRANSLATION_POLICY.
      --clipboard-default <on|off>            Initial protocol clipboard operator state. Env: UNTYPE_CLIPBOARD_DEFAULT.
      --input-default <on|off>                Initial protocol focused-input operator state. Env: UNTYPE_INPUT_DEFAULT.
      --protocol-output <path>                JSONL path required for hybrid mode. Env: UNTYPE_PROTOCOL_OUTPUT.
      --refine, --no-refine                   Enable or disable LLM refinement. Env: UNTYPE_REFINE.
      --llm-provider <name>                   azure-openai, openai, anthropic, google, azure-ai-inference, ollama, litellm, or openai-compat. Env: UNTYPE_LLM_PROVIDER.
      --llm-model <name>                      LLM model/deployment name. Env: UNTYPE_LLM_MODEL.
      -v, --verbose                           Emit diagnostic logs to stderr. Env: UNTYPE_VERBOSE.

    Configuration sources, highest priority first:
      1. CLI flag
      2. <cwd>/.env
      3. ~/.tool-agents/untype/.env
      4. shell environment

    Prompt files are provisioned and read at startup from:
      ~/.tool-agents/untype/prompts/

    Examples:
      $ untype --api-key sk_... --language el --language en
      $ SONIOX_API_KEY=sk_... untype --output-mode append
      $ untype --stt-provider elevenlabs --elevenlabs-api-key xi_...
      $ untype --no-refine
      $ untype ui

    """
}
