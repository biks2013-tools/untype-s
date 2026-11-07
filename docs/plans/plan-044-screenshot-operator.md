# Plan 044 — Screenshot operator

## Request
Add one more operator so that, besides the dictated text, a screenshot of the full window of the app the user is in is sent to the LLM. When the operator is on, the screenshot is also copied to the clipboard (for debugging), and the prompts say that a screenshot was sent.

## Decisions
- New operator `screenshot`, key **W** (Window), off by default, "Until changed" by default (Settings → Operators can make it "This turn"). Flag `--screenshot-default`, env `UNTYPE_SCREENSHOT_DEFAULT`, setting `screenshot`.
- What is captured: the front-most normal window of the app in front, captured by ScreenCaptureKit as that window alone (`SCContentFilter(desktopIndependentWindow:)`), so untype's overlay or pop-up never appears in it. Scaled so the longest side is at most 1568 px, PNG.
- When: push-to-talk at press time (or when W is switched on mid-turn); Push-to-Act at Run, after the pop-up closes. The turn waits for a capture still in progress before its LLM call.
- Sent with every LLM call of the section: refine, translate, the combined call and Ask, on the primary or alternative LLM. Providers: Gemini `inlineData`, Claude `image` block, Chat Completions (Azure OpenAI, DeepSeek) `image_url` data URL. Checked live: `deepseek-flash`, `gemini-3.8-flash` and Azure `gpt-5.4` all read it.
- Prompts: two new editable prompt files with an `{app}` placeholder, `016-screenshot-context-template.txt` (appended to the refine/translate input: reference only) and `017-ask-screenshot-template.txt` (put before an Ask request: the request may refer to what it shows).
- No fallback: with the operator on and no screenshot captured (permission missing, no window), the turn is not sent to the LLM; one warning.
- Clipboard: the PNG (plus TIFF) is put on the clipboard after the capture, after the ⌘C selection read restores the clipboard. With Clipboard (C) also on, the result text replaces it at the end of the turn.
- Ask with no speech answers about the screenshot.
- Permission: Screen Recording. Missing: untype asks once (system prompt) and logs how to grant it.

## Steps
1. `OperatorKey.screenshot`, `OperatorState.screenshot` (Codable, missing = off), settings sources, resolver flag/env, settings store, JSONL writer, status line.
2. `UntypeUISettings.screenshot` (+ patch, persisted, session argument, per-turn plumbing); chips, overlay row (width 248), dropdown row, Settings row, `W` hotkey letter.
3. `LLMImageAttachment`, `ImageInputRefining` on the three refiners; composite request `image`.
4. `WindowScreenshot`, `UntypeTurnContext` pending/stored screenshot; controller sends it with every call and adds the prompt notes; prompt files 016/017.
5. `WindowScreenshotCapture` (ScreenCaptureKit, clipboard); launcher capture at press / mid-turn W / Push-to-Act Run; Push-to-Act choice `screenshot` (key W, remembered).
6. Tests (unit + live), docs (FR-49).
