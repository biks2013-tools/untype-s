import Foundation

/// Fully commented `.env` template written to `~/.tool-agents/untype/.env` when
/// that file does not exist yet. Every variable is present, commented out, with
/// an empty value, so provisioning never changes the resolved configuration:
/// the no-fallback rule still applies and required values must be filled in by
/// the user. Existing files are never touched.
public enum UntypeEnvTemplate {
    public static let fileName = ".env"

    public static let content = """
    # untype configuration
    #
    # This file was created by untype because no ~/.tool-agents/untype/.env
    # existed yet. Every setting below is commented out and empty: untype does
    # NOT apply any value from this file until you remove the leading "#" and
    # fill in the value. Required settings that stay unset are reported as a
    # configuration error at session start; nothing is silently defaulted.
    #
    # Precedence, highest first: CLI flag > <cwd>/.env > this file > shell env.
    # Format: KEY=value (no quotes needed; "#" starts a comment).
    # Keep this file private: it holds API keys (permissions are set to 0600).

    # ---------------------------------------------------------------------------
    # Speech-to-text (required: the API key of the selected provider)
    # ---------------------------------------------------------------------------

    # Soniox API key. Required when UNTYPE_STT_PROVIDER is soniox (the default).
    # SONIOX_API_KEY=

    # Reminder date (YYYY-MM-DD) for renewing SONIOX_API_KEY. Optional.
    # SONIOX_API_KEY_EXPIRES_AT=

    # ElevenLabs API key. Required when UNTYPE_STT_PROVIDER is elevenlabs.
    # ELEVENLABS_API_KEY=

    # Reminder date (YYYY-MM-DD) for renewing ELEVENLABS_API_KEY. Optional.
    # ELEVENLABS_API_KEY_EXPIRES_AT=

    # Realtime transcription provider: soniox or elevenlabs. Default: soniox.
    # UNTYPE_STT_PROVIDER=

    # STT realtime model. Default: stt-rt-v4 (Soniox) or scribe_v2_realtime (ElevenLabs).
    # UNTYPE_MODEL=

    # STT WebSocket endpoint. Default: the selected provider's public endpoint.
    # UNTYPE_ENDPOINT=

    # Language hints, comma separated, or auto. Default: el,en (Soniox) or auto (ElevenLabs).
    # UNTYPE_LANGUAGES=

    # PCM sample rate in Hz. Default: 16000.
    # UNTYPE_SAMPLE_RATE=

    # Provider endpoint/VAD detection: on or off. Default: on.
    # UNTYPE_ENABLE_ENDPOINT_DETECTION=

    # Quick Close: submit the latest push-to-talk partial immediately on release
    # instead of waiting for provider finalization: on or off. Default: off.
    # UNTYPE_QUICK_CLOSE=

    # ---------------------------------------------------------------------------
    # LLM refinement / translation (optional feature; keys required only when on)
    # ---------------------------------------------------------------------------

    # Enable LLM refinement: on or off. Default: on. With refinement on, the
    # selected LLM provider's credentials below are required.
    # UNTYPE_REFINE=

    # LLM provider: azure-openai, openai, anthropic, google, azure-ai-inference,
    # ollama, litellm, or openai-compat. Default: azure-openai.
    # Implemented today: azure-openai and google.
    # UNTYPE_LLM_PROVIDER=

    # LLM model or deployment name. Default: gpt-5.4.
    # UNTYPE_LLM_MODEL=

    # Azure OpenAI (required when UNTYPE_LLM_PROVIDER is azure-openai and refinement is on).
    # AZURE_OPENAI_API_KEY=
    # AZURE_OPENAI_ENDPOINT=
    # AZURE_OPENAI_DEPLOYMENT=
    # Azure OpenAI API version. Default: 2024-10-21.
    # AZURE_OPENAI_API_VERSION=

    # Google Gemini (required when UNTYPE_LLM_PROVIDER is google and refinement is on).
    # GOOGLE_API_KEY=

    # Cap on LLM output tokens. Omitted from requests when unset.
    # UNTYPE_LLM_MAX_OUTPUT_TOKENS=

    # Reasoning effort for reasoning-capable models: none, minimal, low, medium,
    # or high. Omitted when unset. Do not set for models that reject it.
    # UNTYPE_LLM_REASONING_EFFORT=

    # Stream LLM response tokens to the overlay (azure-openai/google only): on or off. Default: off.
    # UNTYPE_LLM_STREAMING=

    # ---------------------------------------------------------------------------
    # Interaction, voice commands, and output
    # ---------------------------------------------------------------------------

    # Interaction mode: dictation, agent-protocol, or hybrid. Default: dictation.
    # UNTYPE_INTERACTION_MODE=

    # Transcript output mode: overwrite, append, or final-only. Default: overwrite.
    # UNTYPE_OUTPUT_MODE=

    # Spoken phrase that closes the current turn. Default: τέλος εντολής
    # UNTYPE_GUARD_PHRASE=

    # Spoken marker for state commands. Default: command
    # UNTYPE_COMMAND_PHRASE=

    # Spoken marker that submits the current section. Default: command send
    # UNTYPE_SECTION_END_PHRASE=

    # Spoken marker that cancels the current section. Default: command cancel
    # UNTYPE_SECTION_CANCEL_PHRASE=

    # Spoken marker that treats the next marker as literal dictation. Default: literal phrase
    # UNTYPE_LITERAL_NEXT_PHRASE=

    # Initial operator states for each session: on or off. Default: off.
    # UNTYPE_REFINE_DEFAULT=
    # UNTYPE_TRANSLATE_DEFAULT=
    # UNTYPE_CLIPBOARD_DEFAULT=
    # UNTYPE_INPUT_DEFAULT=

    # Translation policy: opposite, to-en, or to-el. Default: opposite.
    # UNTYPE_TRANSLATION_POLICY=

    # JSONL protocol output path. Required for hybrid interaction mode.
    # UNTYPE_PROTOCOL_OUTPUT=

    # ---------------------------------------------------------------------------
    # Diagnostics
    # ---------------------------------------------------------------------------

    # Emit diagnostic logs to stderr: on or off. Default: off.
    # UNTYPE_VERBOSE=

    # Append push-to-talk release timing records (JSONL): on or off. Default: off.
    # UNTYPE_RELEASE_LATENCY_LOG=

    # Latency log path. Default: ~/.tool-agents/untype/release-latency.jsonl
    # UNTYPE_RELEASE_LATENCY_LOG_PATH=

    # Clear the latency log once per application start: on or off. Default: off.
    # UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=

    """

    /// Names of every variable the template documents, in file order.
    public static var variableNames: [String] {
        content.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("# "), line.hasSuffix("=") else { return nil }
            let name = line.dropFirst(2).dropLast()
            guard !name.isEmpty, name.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "_" }) else { return nil }
            return String(name)
        }
    }
}
