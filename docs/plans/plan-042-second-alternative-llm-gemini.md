# Plan 042 — Second alternative LLM (Gemini 3.8 Flash) and Gemini thinking fix

## Request
Check whether Gemini 4 Flash exists and can be used through Google directly; then offer Gemini 3.8 Flash as a further choice for the alternative LLM.

## Findings (2026-11-07)
- Gemini API model list (`GET /v1beta/models`): no Gemini 4 Flash (`gemini-4-flash`, `-preview`, `-latest` → 404). Gemini 4 exists only as `gemini-4-argon`. Newest Flash: `gemini-3.8-flash`.
- untype's existing `google` provider (Gemini API + `GOOGLE_API_KEY`) works with both, no new provider needed.
- With a 400-token cap, `gemini-3.8-flash` spent 380 tokens thinking and returned half a sentence with `finishReason: MAX_TOKENS`; the one-shot parser delivered it.
- `thinkingBudget: 0` is rejected by Pro models; `thinkingLevel: "low"` is accepted by all listed models and gives 0 thinking tokens on Flash.

## Decisions (confirmed with the user)
- Gemini is added as a **second** alternative (DeepSeek stays the first): Push-to-Act offers Primary · Alternative · Alternative 2.
- `GOOGLE_API_KEY` copied from the shell into `~/.tool-agents/untype/.env` (backup `.env.bak.20261107-gemini`).

## Steps
1. `GoogleRefiner(thinking:)`: `thinkingLevel: low` for refine/translate/composite, default for Ask; skip `thought` parts; `MAX_TOKENS` → truncation error (one-shot and streaming).
2. Config: `ResolvedConfig.alternativeLLM2`; `ConfigResolver.resolveAlternativeLLM(slot:)` with `--alt2-llm-*` / `UNTYPE_ALT2_LLM_*`.
3. Settings: `alt2LlmProvider` / `alt2LlmModel` (persisted, patch, session arguments); Settings group "Alternative LLM 2".
4. Push-to-Act: `PushToActModel`, `PushToActChoice.model/availableModels/select`, L cycles; pop-up shows the third pill; `runSelectionHotkey(secondAlternative:)`.
5. Tests, docs (FR-46, FR-47, configuration guide, project design), build 37, set the user's slot 2 to `google` / `gemini-3.8-flash`.
