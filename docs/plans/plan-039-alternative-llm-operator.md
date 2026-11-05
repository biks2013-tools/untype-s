# Plan 039 — Alternative LLM operator

Date: 2026-11-05

## Request

Add one more flag: use the alternative LLM. With it on, the refine and translate operators, or the Ask operator, work exactly as they already do for dictation, but they call a second, separately chosen LLM. The flag is switched with a hotkey letter like the other operators.

(An earlier version of the request framed this as removing watermarks from text produced by another model. That framing was not adopted. The feature is a general second-model choice with the same meaning-preserving prompts.)

## Design

- **Operator.** `OperatorKey.alternative`:
  - hotkey + **L**; chips in the main window, compact view and overlay (overlay width 200 → 224);
  - a dropdown row ("Use the alternative LLM");
  - a Settings operator row with "This turn" / "Until changed" (default "Until changed");
  - spoken `command alternative on|off`;
  - `--alternative-default` / `UNTYPE_ALTERNATIVE_DEFAULT`;
  - persisted in `state.json`, and present in the JSONL operator map and the status line.
- **Configuration.** `--alt-llm-provider` / `UNTYPE_ALT_LLM_PROVIDER` and `--alt-llm-model` / `UNTYPE_ALT_LLM_MODEL`.
  - When neither is set, there is no alternative LLM. When only one is set, or the provider is unknown, it is a configuration error.
  - Credentials come from the provider's standard variables. When they are missing, the error names them.
  - For `azure-openai`, the model is the deployment name.
  - Prompts, limits, timeouts, reasoning effort and streaming are copied from the primary `LLMConfig`.
- **UI settings.** `alternative`, `altLlmProvider` and `altLlmModel`, which are optional in `ui-state.json`.
  - `sessionArguments()` passes `--alt-llm-*` only when both values are set.
  - Settings → General has an **Alternative LLM** group (Provider: None / provider; Model) with a status caption.
  - Changing the group restarts the warm session.
- **Runtime.**
  - `UntypeRuntimeFactory.makeAlternativeLLMClients` builds `ProtocolLLMClients` (refiner, translator, composite, asker) with the same prompts, for both the CLI and the UI runtime.
  - In `VoiceAgentProtocolController.processSection`, local client variables are chosen per section.
  - When the alternative LLM is missing and the operator is on, no LLM call is made. One warning is shown, and the per-operator "not configured" warnings are suppressed. The primary LLM is never used as a fallback.

- **DeepSeek provider** (added at the user's request to call DeepSeek directly rather than through Azure).
  - `LLMProvider.deepseek` and `ProviderConfig.openAICompatible(apiKey:baseURL:)`.
  - `AzureOpenAIRefiner` gains an OpenAI-compatible route: `{base}/chat/completions` with a bearer key, `model` and `max_tokens`, and no `reasoning_effort`.
  - `DEEPSEEK_API_KEY` is required. `DEEPSEEK_API_BASE` is optional and defaults to `https://api.deepseek.com`.
  - Both are added to the `.env` template, and the key is added to the Set keys… editor.

## Verification

- `AlternativeLLMTests`:
  - routing for refine, Ask and translate;
  - the primary LLM is used when the operator is off;
  - no fallback when the alternative LLM is not configured;
  - config resolution: deployment, prompts, the operator default and the error cases;
  - UI session arguments and the store round trip.
- Live (`liveAlternativeLLMRefinesAndTranslatesASection`): primary Opus 5.5 (Foundry), alternative gpt-5.1 (Azure OpenAI). A refine+translate section was translated to Greek in 1.9 s.
- Signed build: configure Settings → Alternative LLM, turn on L with Refine or Translate, run a push-to-talk turn and a selection turn, and check `focused_input.ok=true`.
