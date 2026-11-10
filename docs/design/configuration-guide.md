# Configuration Guide

## Configuration Priority
`untype` resolves configuration from the following sources, highest priority first:

1. CLI flags.
2. The current working directory `.env`.
3. `~/.tool-agents/untype/.env`.
4. Shell environment variables.

Required values must be provided explicitly. Missing required configuration raises a typed error; the application must not silently substitute a fallback for required settings.

## Default `.env` Template

### Purpose
On every configuration resolution (CLI start or a native-UI session start) `untype` checks for `~/.tool-agents/untype/.env`. If the file does not exist it creates the folder (`0700`) and writes a **fully commented** template (`0600`) listing every configuration variable the application understands, grouped by area (speech-to-text, LLM refinement/translation, interaction and voice commands, diagnostics), each as `# NAME=` preceded by a one-line description with the allowed values and the built-in default.

### Behavior
- Every line of the template is a comment or blank, so provisioning never changes a resolved value. The no-fallback rule is untouched: a required setting that stays commented out is still reported as a configuration error (for example the missing STT API key on first start).
- An existing `.env` is never modified, regardless of its content.
- The template text lives in `Sources/UntypeCore/EnvTemplate.swift` (`UntypeEnvTemplate.content`). A unit test asserts the template documents exactly the set of variables the resolver reads, so adding a variable to the resolver without adding it to the template fails the suite.
- Users enable a setting by deleting the leading `# ` and filling the value. Comments elsewhere in the file are preserved by the parser.

### Recommended Use
Point new users at this file instead of a separate example: after the first launch they open `~/.tool-agents/untype/.env`, uncomment `SONIOX_API_KEY=` (or `ELEVENLABS_API_KEY=` plus `UNTYPE_STT_PROVIDER=elevenlabs`) and, if they keep refinement on, the LLM provider block, then start a session again.

## Credentials Editor (native UI)

### Purpose
The native UI can write provider credentials into `~/.tool-agents/untype/.env` so a new user never has to edit the file by hand. The editor is reachable from the onboarding sheet (step 3 "Provider credentials" → **Set keys…**, and the footer button when credentials are the only missing item) and from the Settings window (General tab → Session group → **Edit keys…**).

### Variables it manages
`SONIOX_API_KEY`, `ELEVENLABS_API_KEY` (speech-to-text, at least one) and `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`, `AZURE_OPENAI_API_VERSION`, `GOOGLE_API_KEY`, `ANTHROPIC_FOUNDRY_API_KEY`, `ANTHROPIC_FOUNDRY_RESOURCE`, `ANTHROPIC_API_KEY` (LLM refinement/translation, optional). Secret fields are masked; a "Show" switch reveals them while editing. Every other variable stays file-only.

### Behavior
- Saving writes only the fields that changed, through `DotenvEditor` (`Sources/UntypeCore/DotenvEditor.swift`): an active `KEY=value` line is replaced in place (later duplicates of the same key are removed so a stale last-wins entry cannot shadow the new value), a commented `# KEY=` template line is activated in place so its description stays above it, and an unknown key is appended. Comments, ordering, and unrelated variables are preserved. An emptied field unsets the key by turning its line back into `# KEY=`.
- A missing file is created from the commented template (see "Default `.env` Template") with the parent folders at `0700` and the file at `0600`.
- Values containing `#`, leading/trailing spaces, or a leading quote are written quoted so the parser reads them back unchanged.
- The editor shows and edits the user-level file only; values coming from `<cwd>/.env` or the shell environment are not displayed, although the status line still reports them as the effective source when they win the precedence chain.
- Secret values never reach the event log or diagnostics; the saved event names only the affected keys.

## Hotkey Modes (native UI)

`ui-state.json` (`~/.tool-agents/untype/ui-state.json`) stores `hotkeyHoldToTalk` next to `hotkeyEnabled` and `hotkey`:

| Setting | Values | Default | Meaning |
|---|---|---|---|
| `hotkeyEnabled` | `true` / `false` | `false` | Whether the global hotkey is monitored at all (menu-bar dropdown → Hotkey switch, or Settings → Push-to-Talk → Enable push-to-talk). |
| `hotkeyHoldToTalk` | `true` / `false` | `true` | `true`: push-to-talk, hold the hotkey to record and release to submit. `false`: push-to-listen, press once to start recording and press again to stop and submit. Menu-bar dropdown segmented control, the main window's top-bar switch, and Settings → General → Push to talk → "Hold to talk". |
| `hotkey` | key chord, e.g. `Control+\`` | `Control+\`` | The hotkey itself. |

Both modes run the same pipeline after the recording ends: refinement, translation, clipboard, and focused-input delivery according to the operator toggles. Missing `hotkeyHoldToTalk` in an older state file loads the default (push-to-talk).

## Claude as the LLM Provider (`anthropic`, `azure-anthropic`)

### Purpose
Refinement and translation can run on Claude through the Anthropic Messages API, either directly (`anthropic`, `api.anthropic.com`) or on Microsoft (Azure) Foundry (`azure-anthropic`, `https://<resource>.services.ai.azure.com/anthropic`). Select it with `--llm-provider` / `UNTYPE_LLM_PROVIDER` or the Settings window (General → Refinement (LLM) → Provider); `--llm-model` / `UNTYPE_LLM_MODEL` is the model ID (direct) or the Foundry **deployment name** (e.g. `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`).

### Variables
| Variable | Provider | Required | Meaning / how to obtain |
|---|---|---|---|
| `ANTHROPIC_FOUNDRY_API_KEY` | azure-anthropic | yes | The Foundry resource key (Foundry portal → Build → Models → deployment → Details → Key). On a resource that also hosts Azure OpenAI deployments it is the same key as `AZURE_OPENAI_API_KEY`; it is still set separately (no fallback between variables). Sent in the `x-api-key` header — verified 2026-10-24 that the Foundry Anthropic endpoint rejects `api-key` with 401 while accepting `x-api-key`. |
| `ANTHROPIC_FOUNDRY_RESOURCE` | azure-anthropic | one of these two | Resource name; the base URL becomes `https://<resource>.services.ai.azure.com/anthropic`. |
| `ANTHROPIC_FOUNDRY_BASE_URL` | azure-anthropic | one of these two | Full base URL instead of the resource name. Setting both is an error. |
| `ANTHROPIC_API_KEY` | anthropic | yes | Claude API key from the Claude Console. |

### Request behavior and defaults
- Current Claude models reject `temperature` and cannot disable thinking; latency is set with `output_config.effort`. Default effort is `low` (dictation cleanup is short); `UNTYPE_LLM_REASONING_EFFORT` maps `none`/`minimal` → `low` and passes `low`/`medium`/`high` through.
- `max_tokens` (required by the API) is `UNTYPE_LLM_MAX_OUTPUT_TOKENS` when set, else 4096.
- A `refusal` or `max_tokens` stop reason is treated as a failed refinement (the raw transcript is delivered instead of a fragment).
- Live check: `UNTYPE_LIVE_LLM_TEST=1 UNTYPE_LIVE_LLM_ARGS="--llm-provider azure-anthropic --llm-model claude-opus-5-5" swift test --filter liveLLM` (2026-10-24 on `claude-opus-5-5`: refine ≈2.0 s, translate ≈1.3 s, refine+translate ≈1.4 s).

## Alternative LLM (Alternative operator)

### Purpose

A second LLM, chosen separately from the primary one. While the **Alternative** operator is on (key **L**, `--alternative-default` / `UNTYPE_ALTERNATIVE_DEFAULT`, spoken `<command> alternative on`), every LLM call of a turn (refine, translate, the combined refine+translate call and Ask) goes to the alternative LLM instead of the primary one. The prompts, the output limits (`UNTYPE_LLM_MAX_OUTPUT_TOKENS`, `UNTYPE_ASK_MAX_OUTPUT_TOKENS`), the reasoning effort and streaming are the primary LLM's. With Selection on (Material role), selecting a text and tapping the hotkey has it refined or translated by the alternative model.

### Variables

| Setting | CLI | Env | Default | Meaning |
|---|---|---|---|---|
| Provider | `--alt-llm-provider` | `UNTYPE_ALT_LLM_PROVIDER` | none (no alternative LLM) | One of the `UNTYPE_LLM_PROVIDER` values; `azure-openai`, `google`, `anthropic`, `azure-anthropic` and `deepseek` are implemented. |
| Model | `--alt-llm-model` | `UNTYPE_ALT_LLM_MODEL` | none | The model; for `azure-openai`, the deployment name (`AZURE_OPENAI_DEPLOYMENT` belongs to the primary LLM and is not used). Required when a provider is set. |
| Operator default | `--alternative-default on\|off` | `UNTYPE_ALTERNATIVE_DEFAULT` | `off` | Initial operator state. |

In the app: Settings → Language Models → **Alternative** (Provider: None or a provider; Model), stored as `altLlmProvider` / `altLlmModel` in `~/.tool-agents/untype/ui-state.json` and passed to the session only when both are set.

**Alternative LLM 2** (build 37): a second alternative slot with the same rules, `--alt2-llm-provider` / `UNTYPE_ALT2_LLM_PROVIDER` and `--alt2-llm-model` / `UNTYPE_ALT2_LLM_MODEL` (default: none), Settings → General → **Alternative LLM 2**, stored as `alt2LlmProvider` / `alt2LlmModel`. Only the Push-to-Act pop-up uses it (Model: Primary · Alternative · Alternative 2; **L** cycles the configured ones). The Alternative operator in dictation always uses the first slot. Example: `deepseek` / `deepseek-flash` in the first slot and `google` / `gemini-3.8-flash` in the second. The operator row in Settings → Operators chooses "This turn" or "Until changed" (default "Until changed").

### Credentials

The provider's standard variables, the same ones the primary LLM uses (`AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_ENDPOINT`; `GOOGLE_API_KEY`; `ANTHROPIC_API_KEY`; `ANTHROPIC_FOUNDRY_API_KEY` + `ANTHROPIC_FOUNDRY_RESOURCE`/`_BASE_URL`; `DEEPSEEK_API_KEY`), set with **Set keys…** or in `~/.tool-agents/untype/.env`. A configured alternative provider whose keys are missing is a configuration error at session start, naming the missing variables.

### Google Gemini (`google` provider)

Google's Gemini API (Google AI Studio), not Vertex AI: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` with the API key.

- `GOOGLE_API_KEY` (required): create it at https://aistudio.google.com/apikey and store it with **Set keys…** or in `~/.tool-agents/untype/.env` (a key exported only in `~/.zshrc` is not visible to the app started from Finder).
- Model: the Gemini model ID, e.g. `gemini-3.8-flash` (the newest Flash on 2026-11-07). `GET https://generativelanguage.googleapis.com/v1beta/models` (header `x-goog-api-key`) lists the models available to the key. Gemini 4 Flash was not yet published on 2026-11-07 (`gemini-4-flash`, `gemini-4-flash-preview` → 404); when it is, only the model name changes.
- Thinking: refine, translate and the combined call send `generationConfig.thinkingConfig.thinkingLevel: "low"` (Flash models then answer without thinking; thinking tokens count against `maxOutputTokens`, so a 400-token cap cut answers in half). `thinkingBudget: 0` is not used because Pro models reject it. Ask keeps the model's default thinking. A response with `finishReason: MAX_TOKENS` is an error ("output was truncated"), never half a sentence.

### DeepSeek (`deepseek` provider)

DeepSeek's own API, not a deployment on Azure: OpenAI-compatible Chat Completions at `{DEEPSEEK_API_BASE}/chat/completions` with `Authorization: Bearer $DEEPSEEK_API_KEY`.

- `DEEPSEEK_API_KEY` (required): create it at https://platform.deepseek.com/api_keys and store it with **Set keys…** or in `~/.tool-agents/untype/.env`. A key exported only in `~/.zshrc` is not visible to the app when it is started from Finder or at login.
- `DEEPSEEK_API_BASE` (optional): defaults to `https://api.deepseek.com`.
- Model: the DeepSeek model name, e.g. `deepseek-flash` (DeepSeek V4.1 Flash, thinking on by default) or `deepseek-v4-pro`. `GET {base}/models` lists the models available to the key.
- The request carries `model` and `max_tokens` (from `UNTYPE_LLM_MAX_OUTPUT_TOKENS`). `UNTYPE_LLM_REASONING_EFFORT` is not sent, because DeepSeek has no such parameter.
- It can be the primary provider as well (`UNTYPE_LLM_PROVIDER=deepseek`).

### No fallback

- Provider without a model, model without a provider, or an unknown provider: configuration error.
- Alternative operator on but no alternative LLM configured: the turn makes **no** LLM call (the primary LLM is never used in its place), the dictated text is delivered unchanged, and one warning says so.

## Push-to-Act (Selection Hotkey)

**Push-to-Act** processes text you have already selected, instead of dictated text. It is set in Settings → Push-to-Act and stored in `~/.tool-agents/untype/ui-state.json` as `selectionHotkeyEnabled` (default **on**) and `selectionHotkey` (default **`Control+Option+``**); the stored names stay as before. It has no CLI flag or environment variable.

- Select text in any app and press the hotkey. untype reads the selection: Accessibility first, then a synthetic ⌘C (the pasteboard is restored).
- **Nothing selected:** the whole text of the active field is used instead. untype selects it (you see it highlighted), the pop-up says "Nothing selected · whole field", and the result replaces the field's text. Esc puts your cursor back. This needs a field that exposes its text through Accessibility (TextEdit, Notes, Mail, most native and browser text fields); in apps where untype has to fall back to ⌘C (some Electron apps) a selection is still required.
- **Terminals (cmux, Ghostty, Terminal…) with nothing selected:** untype uses the prompt of a terminal coding agent such as Claude Code: the text after `❯` between the two horizontal lines at the bottom. The pop-up says "Nothing selected · terminal prompt". On Run, untype deletes the prompt with one Backspace per character, so **the cursor must be at the end of the prompt** (where it is after typing). It then checks the screen: if the prompt is empty the result is typed; if not, nothing is typed, a warning explains why, and the result is on the clipboard.
- A pop-up opens over the app. It shows the selected text and lets you change:
  - **Model**: Primary (the main LLM), Alternative and Alternative 2 (the alternative LLMs, shown only when configured); `L` cycles them.
  - **Operators**: Refine `R`, Translate `T`, Ask `A`, Follow-up `F`, Screenshot `W`, Clipboard `C`.
  - **Translation**: `1` Greek ↔ English (opposite), `2` → English, `3` → Greek.
- **Remembered choices** (build 38): Push-to-Act has its own choices, separate from the push-to-talk / push-to-listen operators. Every Run saves the pop-up's model, operators and translation direction as `pushToAct` in `ui-state.json`, and the next pop-up opens with them; Esc saves nothing. Changing them never changes the push-to-talk operators, and vice versa. Before the first run the pop-up starts from the push-to-talk operators. A remembered model that is no longer configured opens as Primary.
- Picking a translation direction (click or `1`–`3`) also turns **Translate** on: choosing a language means "translate to it". The direction is highlighted only while Translate is on.
- Click or press the letters/digits to change them; **Enter** runs, **Esc** cancels (so does clicking elsewhere or pressing the push-to-talk hotkey). Enter does nothing while none of R/T/A is on.
- What the run does:
  - **Refine** and/or **Translate**: the result is the refined and/or translated text.
  - **Ask**: the selection is sent as the selected text with no spoken request, so the model responds to it. Follow-up adds the conversation.
  - **Clipboard**, if on, also copies the result.
- The result **replaces the selection**, whatever the Focused input and Selection role settings are. When the app exposes the selection through Accessibility (TextEdit, Notes, most native fields), untype writes the result straight into that selection (`focused_input.method: "ax-selection"`), wherever the focus is by then; otherwise it uses the usual focused-input delivery (`ax-value`, `paste-keycode`, …).
- No microphone, no recording, no STT.
- Nothing happens, with a message in the overlay and Events, when nothing is selected or untype itself is in front; it is ignored while a push-to-talk turn is recording or being delivered, or a manual session is running.
- The hotkey uses the same format as the push-to-talk hotkey (`Control`, `Option`, `Command`, `Shift`, `CommandOrControl` + one key). It must differ from the push-to-talk hotkey, in any modifier order, unless it is disabled.
- It needs the push-to-talk listener on (Push to talk → Enabled), because it is detected by the same event tap.
- Each run writes a record to `release-latency.jsonl` with `trigger: "push-to-act"` (`"selection-hotkey"` up to build 33). Check `focused_input.ok` there.

## Settings Window

The Settings window (⌘, from the menu-bar dropdown or the main window) is organised like macOS System Settings: a sidebar of panes on the left, a grouped form on the right.

| Pane | What it holds |
|---|---|
| **General** | Theme; dictation overlay (Keep overlay visible, position reset); current session status. |
| **Push-to-Talk** | Enable, hotkey, hold-to-talk or press-to-start/stop, Quick Close, listener status and a test button. |
| **Push-to-Act** | Enable and hotkey. |
| **Speech** | Speech-recognition provider, model, languages, sample rate, endpoint detection; protocol mode and voice commands. |
| **Operators** | Each operator with its key, state and how long a change lasts; "Selected text is"; translate direction. |
| **Language Models** | Primary, Alternative and Alternative 2 (Push-to-Act) provider and model. |
| **Prompts** | The editable prompt files. |
| **Permissions & Keys** | macOS permission status and setup guide; API key status and **Edit Keys…**. |

Settings that shape the session are locked while a session is active; the pane header says so.

## Keep Overlay Visible

**Keep overlay visible** (Settings → General → Dictation overlay, `overlayAlwaysVisible` in `~/.tool-agents/untype/ui-state.json`, default **off**; no CLI flag or environment variable, like the theme) keeps the push-to-talk overlay at the bottom of the screen when you are not dictating. Idle, it shows a flat dim line and the operator chips, which you can click to switch an operator (hover for its name and state). Off: the overlay appears only while dictating or processing. An older `ui-state.json` without the key loads with it off.

**Overlay position** (build 45): drag the small grip in the overlay's top-left corner to move it anywhere; untype remembers the place as `overlayPosition` (`{"x":…, "y":…}`, the bottom-left corner in screen points) in `ui-state.json` and shows the overlay there from then on. Double-click the grip to put it back at the bottom centre (the key is removed). Without the key, or when the saved place is on a display that is no longer connected, the overlay appears at the bottom centre of the screen under the mouse.

## Voice Commands On/Off

**Voice commands** (Settings → Speech → Protocol, `voiceCommands` in `~/.tool-agents/untype/ui-state.json`; CLI `--voice-commands` / `--no-voice-commands`; env `UNTYPE_VOICE_COMMANDS`, values `true/false/yes/no/on/off/1/0`; default **on**) decides whether untype listens for spoken commands.

- **On:** the spoken markers work as configured: the command phrase (`command translate on`, `command status` …), section end (`command send` and the guard phrase `τέλος εντολής`), section cancel (`command cancel`) and `literal phrase`.
- **Off:** none of them is recognised. Everything you say is dictated text, including the words "command send". Turns are delivered on hotkey release (push-to-talk) or on the second press (push-to-listen); operators are changed with the hotkey letters, the dropdown or Settings.
- Use Off when you dictate text that naturally contains the command words, or to rule out accidental operator changes.
- The setting applies from the next session: changing it restarts the warm push-to-talk session. It cannot be changed while a manual session is running. Priority: CLI flag > `UNTYPE_VOICE_COMMANDS` (shell, then `.env` files) > UI setting > default `true`. The native UI passes the UI setting as the CLI flag, so in the app the Settings toggle decides.

## Operator Persistence: "This turn" or "Until changed"

Every operator (Refine, Translate, Ask, Follow-up, Selection, Clipboard, Focused input) has a **Lasts** choice in Settings → Operators:

- **Until changed**: the operator stays as you set it until you switch it again.
- **This turn**: the operator is switched off again when a push-to-talk turn has been delivered, so you switch it on for each use. Switch it on in the dropdown before pressing, or with hotkey + its letter while holding.

Defaults: Ask, Follow-up and Selection are "This turn"; the others are "Until changed". The dropdown marks "This turn" operators with **1×**. The choice is stored as `perTurnOperators` in `~/.tool-agents/untype/ui-state.json`. An older file without it loads the defaults. Unknown operator names are rejected with a configuration error.

## Follow-up Operator (Ask continues the conversation)

With **Follow-up** on (key **F**, `--followup-default` / `UNTYPE_FOLLOWUP_DEFAULT`, spoken `<command> followup on`), an Ask request is sent together with the conversation so far: the earlier requests and answers, rendered through `015-ask-conversation-template.txt` (`{history}`). This lets you refine, correct, shorten or extend the previous answer. With Follow-up off, each Ask starts a new conversation. The dropdown's **New conversation** entry also clears it.

- The conversation keeps the last 20 exchanges, in memory only. It is lost when untype quits and is never written to disk.
- Follow-up applies to Ask only. It has no effect on plain dictation, refine or translate.

## Selection Operator (include the selected text)

With **Selection** on (key **S**, `--selection-default` / `UNTYPE_SELECTION_DEFAULT`), the text selected in the app in front at press time is included in the request.

- **Reading the selection.** untype reads it through Accessibility (`AXSelectedText`), so the Accessibility permission is required. Where the app does not expose it (terminals, some Electron apps), untype sends a ⌘C, reads the clipboard and restores the previous clipboard contents right away. Some editors copy the whole current line when nothing is selected. Live typing waits until the selection has been read.
- **Selected text is** (Settings → Operators, `selectionRole` in `ui-state.json`, default `material`):
  - **Material.** The selection is what refine/translate process; what you dictate, if anything, follows it. The result replaces the selection. A press with no speech still processes the selection, e.g. select a paragraph with Translate + Selection on and tap the hotkey.
  - **Context.** Reference only: `013-selection-context-template.txt` (`{selection}`) is appended to the refine/translate input. Only what you dictate is processed, and the result is inserted after the selection: untype presses Right arrow to move the cursor to the end of the selection first.
- **With Ask.** The selection is put before the request through `014-ask-selection-template.txt` (`{selection}`), e.g. select text and say "make this more formal". In the Material role the answer replaces the selection; in the Context role it goes after it. A press with no speech answers about the selection.
- The selected text is held in memory for the turn only. The event log records only its length.

## Screenshot Operator (send the app's window)

With **Screenshot** on (key **W**, `--screenshot-default` / `UNTYPE_SCREENSHOT_DEFAULT`, setting `screenshot` in `ui-state.json`, default **off**), a screenshot of the window of the app you are in goes to the LLM together with what you dictate.

- **What is captured.** The front window of the app in front, and only that window (untype's overlay or pop-up never appears in it). It is scaled so its longest side is at most 1568 px and sent as PNG.
- **When.** Push-to-talk: when you press the hotkey, or when you switch W on while holding it. Push-to-Act: when you press Run (the pop-up's **Screenshot** choice, key **W**, remembered like the others).
- **Clipboard.** The screenshot is also copied to the clipboard (PNG and TIFF), so you can paste it to see exactly what was sent. With **Clipboard** (C) also on, the result text replaces it at the end of the turn.
- **Prompts.** Refine, translate and the combined call get `016-screenshot-context-template.txt` appended to their input; Ask gets `017-ask-screenshot-template.txt` before the request. `{app}` is the app's name. A press with Ask on and no speech answers about the screenshot.
- **Models.** The image goes to whichever LLM the turn uses (primary or alternative). It works with Gemini, Claude, Azure OpenAI vision deployments and `deepseek-flash`. A model that cannot read images answers with an HTTP error, logged as an operator failure.
- **Permission.** Screen Recording: System Settings → Privacy & Security → Screen & System Audio Recording → untype. The first use asks for it; after granting, quit and reopen untype.
- **No fallback.** With the operator on and no screenshot captured (permission missing, no window), the turn is not sent to the LLM and Events shows why.
- The screenshot is held in memory for the turn only. The event log records its size, never the image.

## Ask Operator (request to the model)

### Purpose
With **Ask** on, what you dictate is not text to clean up but a request to the LLM, for example "write a short reply thanking them and proposing Tuesday" or "explain what a mutex is in two sentences". The model's answer replaces the dictated text and goes to the usual outputs (focused input, clipboard, transcript).

### How to switch it
- Menu-bar dropdown → **Ask the model** (key **A**), the main window and overlay chips (**A**), Settings → Operators.
- While holding the hotkey: hotkey + **A** toggles it for the current turn.
- Spoken: `<command phrase> ask on` / `<command phrase> ask off` (agent/hybrid protocol).
- Initial state: `--ask-default on|off` or `UNTYPE_ASK_DEFAULT` (default `off`). Like the other operators, the native UI persists the last state in `~/.tool-agents/untype/state.json`; a value set by flag or env wins over the persisted one.

### Behavior
- One LLM call per section: system prompt `010-ask-system.txt`, user message `011-ask-user-template.txt`.
- Refine is skipped while Ask is on (the model reads the raw dictation; a cleanup call would only add latency).
- Translate on as well: the same single call uses `012-ask-translated-user-template.txt`, so the reply is written in the target language chosen by the translation policy (`opposite`, `to-en`, `to-el`).
- Requires the LLM to be enabled (`--refine` / Settings → Language Models). Otherwise the warning "Ask operator is enabled, but no LLM is configured." appears and the dictated text is delivered unchanged. The same fail-open applies when the request fails (the warning reads "ask operator failed: …").
- It uses the configured LLM provider, model and reasoning effort, but its **own limits**, because an answer is a full text rather than a rewrite of the dictation:
  - Output cap `--ask-max-output-tokens` / `UNTYPE_ASK_MAX_OUTPUT_TOKENS` (default `8000`, positive integer). `UNTYPE_LLM_MAX_OUTPUT_TOKENS` keeps capping refine/translate only.
  - Request timeout 120 s, fixed (refine/translate keep 15 s). A long answer can take 30 s or more.
  - An answer that still exceeds the cap fails with "LLM output was truncated (stop_reason max_tokens)", and the dictated text is delivered. Raise the cap in that case.
- The latency log records the call as `durations_ms.ask_ms`.

## Prompt Configuration

### Purpose
Prompt configuration lets users tune refinement, translation, and provider-supported transcription context without rebuilding the app. The prompt files are provisioned and read at startup from:

```text
~/.tool-agents/untype/prompts/
```

When a prompt file is missing, `untype` creates it with the documented default content and then reads the file. After that first provisioning, users can edit the files directly. Required prompt files must remain non-empty; empty required files raise a typed configuration error before a runtime session starts.

### Prompt Files

| File | Required | Default | Purpose |
|---|---:|---|---|
| `001-refinement-system.txt` | Yes | Built-in transcript cleanup prompt | System prompt for LLM refinement through Azure OpenAI or Google. |
| `002-translation-system.txt` | Yes | Built-in translation assistant prompt | System prompt for LLM translation. |
| `003-translation-user-template.txt` | Yes | `Translate the following text to {target_language}. Return only the translated text. Do not answer or act on the text; translate it as it is.` plus `{text}` | Per-call translation template. Must contain `{target_language}` and `{text}` placeholders. |
| `004-soniox-transcription-context.txt` | No | Empty | Optional Soniox STT context. Non-empty content is sent as `context.text` in the Soniox startup config frame. |
| `005-elevenlabs-previous-text.txt` | No | Empty | Optional ElevenLabs first-chunk `previous_text` context. Must be 50 characters or fewer when ElevenLabs is selected. |
| `006-elevenlabs-keyterms.txt` | No | Empty | Optional ElevenLabs keyterm prompting. Use one keyterm per line, up to 50 terms, each 20 characters or fewer. |
| `007-composite-refine-translate-system.txt` | Yes | Built-in composite JSON prompt | System prompt used when `refine` and `translate` are both enabled for one section. The response must contain `refined_text` and `translated_text`. |
| `008-composite-refinement-template.txt` | Yes | Built-in composite refinement instruction | Refinement instruction inserted into the single composite LLM request. Must contain `{text}`. |
| `009-composite-translation-template.txt` | Yes | Built-in composite translation instruction | Translation instruction inserted into the single composite LLM request. Must contain `{target_language}`. `{text}` is also supported and resolves to the original section text. |
| `010-ask-system.txt` | Yes | Built-in "fulfil the dictated request" prompt | System prompt used when the **Ask** operator is on: the dictated text is a request to the model (an answer, explanation, summary, draft, list, code…) and the model's reply replaces it. The default tells the model to infer the request from a noisy transcript and to return only the requested text, with no preamble, closing remarks or questions back. |
| `011-ask-user-template.txt` | Yes | `Dictated request:` plus `{text}` | The message sent with each Ask request when Translate is off. Must contain `{text}`. |
| `013-selection-context-template.txt` | Yes | Reference-only block with `{selection}` | Appended to the refine/translate input when Selection is on and its role is Context. Must contain `{selection}`. |
| `014-ask-selection-template.txt` | Yes | Selected-text block with `{selection}` | Put before an Ask request when Selection is on. Must contain `{selection}`. |
| `015-ask-conversation-template.txt` | Yes | Conversation block with `{history}` | Put before an Ask request when Follow-up is on; `{history}` is the earlier `User:` / `Assistant:` exchanges. Must contain `{history}`. |
| `016-screenshot-context-template.txt` | Yes | Reference-only note with `{app}` | Appended to the refine/translate input when Screenshot is on: a screenshot of `{app}`'s window is attached, to be used only as reference. Must contain `{app}`. |
| `017-ask-screenshot-template.txt` | Yes | Screenshot note with `{app}` | Put before an Ask request when Screenshot is on: the request may refer to what the screenshot shows. Must contain `{app}`. |
| `012-ask-translated-user-template.txt` | Yes | `Dictated request:` plus `{text}` and "Write your reply in {target_language}…" | The message sent with each Ask request when Translate is also on: the reply is written in the translation target language (per the translation policy), in the same single call. Must contain `{target_language}` and `{text}`. |

### Recommended Storage and Editing
Keep prompt files in `~/.tool-agents/untype/prompts/`. This folder is user-specific and outside the repository, so users can tune prompts without creating code changes. Do not store secrets in prompt files. Do not include private transcript examples unless you intentionally want them sent to the selected provider.

The native UI edits these files in **Settings → Prompts** (⌘, from the menu-bar dropdown or the main window): one editor per file with Save (⌘S), Revert and Reset to Default (puts the built-in text in the editor; Save applies it). A save is validated with the same rules session start applies (required files non-empty, required placeholders present, provider length limits), so an invalid prompt cannot be written from the editor.

Prompts are **hot-reloaded**: untype polls the fifteen files once a second. When one changes — saved from Settings or from any external editor — the Events log shows `prompts.reloaded: <files>` and an idle warm push-to-talk session is restarted at once, so the next turn uses the new prompt. A turn in progress is never interrupted (the warm session restarts after release and reads the files then); a running manual session uses the new prompts from its next start. The editor refreshes on external changes unless it holds unsaved edits.

The repository also contains default prompt templates under `prompts/` for review and traceability. Runtime reads the user config folder, not the repository templates.

### Validation
- Required LLM prompt files must not be empty.
- `003-translation-user-template.txt` must include both `{target_language}` and `{text}`.
- `008-composite-refinement-template.txt` must include `{text}`.
- `009-composite-translation-template.txt` must include `{target_language}`.
- `011-ask-user-template.txt` must include `{text}`.
- `012-ask-translated-user-template.txt` must include both `{target_language}` and `{text}`.
- `013-selection-context-template.txt` and `014-ask-selection-template.txt` must include `{selection}`; `015-ask-conversation-template.txt` must include `{history}`.
- Soniox context must be 10,000 characters or fewer.
- ElevenLabs `previous_text` must be 50 characters or fewer.
- ElevenLabs keyterms must be one per line, no more than 50 entries, and no entry may exceed 20 characters.

Prompt contents are not written to verbose diagnostics, release latency logs, protocol JSONL events, transcript exports, or UI state.

## Event Log (`events.log`)

The native UI appends its session and diagnostic events to `~/.tool-agents/untype/events.log` (mode `0600`), one ISO-8601 timestamped line per event. At 1 MB the file rotates to `events.log.1`. Only `session.*`, `diagnostic.*`, `prompts.*` and `ready:` lines are written; transcripts and protocol events never are. Use it to trace a failure after untype was quit or relaunched. For example, after a provider disconnect it shows `push-to-talk session ended unexpectedly`, then `re-warming push-to-talk in N s` and `session.state: listening`. The path is fixed and needs no configuration. Delete the files at any time.

## Push-to-talk Release Latency Logging

### Purpose
Release latency logging is an opt-in diagnostic feature for measuring the time between push-to-talk release detection and the point where focused-input delivery reports completion. It is intended for temporary analysis sessions when maintainers need to understand whether delay is coming from provider finalization, Quick Close/fallback selection, protocol processing, refinement/translation, clipboard delivery, focused-input delivery, or runtime scheduling.

The log is privacy-safe by design. It records timings, source/outcome labels, section counts, and focused-input result metadata. It must not record transcript text, processed/refined/translated text, clipboard contents, provider payloads, API keys, prompts, LLM responses, target application text, or target document contents.

### Variables and Flags

| Setting | CLI | Environment | Default | Purpose |
|---|---|---|---|---|
| Release latency logging enabled | `--release-latency-log` / `--no-release-latency-log` | `UNTYPE_RELEASE_LATENCY_LOG` | `false` | Enables or disables append-only JSONL timing records for push-to-talk release attempts. |
| Release latency log path | `--release-latency-log-path <path>` | `UNTYPE_RELEASE_LATENCY_LOG_PATH` | `~/.tool-agents/untype/release-latency.jsonl` | Selects the JSONL file used when latency logging is enabled. |
| Reset release latency log on startup | none | `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START` | `false` | Clears the configured JSONL latency log once per application process startup when release latency logging is enabled. The previous non-empty log is kept as `<path>.previous`. |

Boolean values accepted in `.env` or shell variables are `true`, `false`, `yes`, `no`, `on`, `off`, `1`, and `0`.

### Recommended Storage
For routine diagnostic use, place the enable flag in `~/.tool-agents/untype/.env` only while collecting data:

```env
UNTYPE_RELEASE_LATENCY_LOG=on
UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=off
```

Use `UNTYPE_RELEASE_LATENCY_LOG_PATH` only when a specific analysis run should be isolated:

```env
UNTYPE_RELEASE_LATENCY_LOG=on
UNTYPE_RELEASE_LATENCY_LOG_PATH=/tmp/untype-release-latency.jsonl
UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=on
```

The default path lives under the existing user config directory. The logger creates `~/.tool-agents/untype` with `0700` permissions and the JSONL file with `0600` permissions.

Set `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=on` for runs where the configured latency log should start empty every time the application process launches. The reset applies to `UNTYPE_RELEASE_LATENCY_LOG_PATH` when a custom path is configured. The previous run's records are copied to `<path>.previous` first, replacing the older copy, so a relaunch never erases the record of the failure that prompted it. The setting has no effect while `UNTYPE_RELEASE_LATENCY_LOG` is disabled.

### Disabling
Remove the variable, set it to `off`, or pass `--no-release-latency-log`:

```env
UNTYPE_RELEASE_LATENCY_LOG=off
```

When disabled, push-to-talk release activity does not create or append the latency log file.

### Log Format
Each line is one JSON object. The current schema includes:

- `schema_version`: record schema version.
- `turn_id`: random identifier for one release attempt.
- `release_timestamp`: ISO-8601 timestamp for release detection.
- `trigger`: release trigger, usually `ui-hotkey-release`.
- `stt_provider`: provider label such as `soniox` or `elevenlabs`.
- `quick_close`: whether Quick Close was enabled.
- `text_source`: `provider_final_text`, `provider_final_already_available`, `quick_close_partial`, `timeout_fallback_partial`, `no_submitted_text`, or `unknown`.
- `outcome`: `delivered_to_focused_input`, `focused_input_failed`, `processed_without_focused_input`, `no_text`, `ignored_release`, or `failed`.
- `total_ms`: elapsed time from release detection to the recorded outcome.
- `durations_ms`: stage timings, including UI-to-runtime scheduling, provider commit request, provider final wait, protocol submission, operator processing, refine, translate, clipboard, and focused-input delivery when those stages occur.
- `sections_processed`: number of protocol sections processed for the release.
- `focused_input`: privacy-safe delivery metadata such as `attempted`, `ok`, `method`, `code`, `accessibility_trusted`, `focused_element_available`, `target_role`, and `target_subrole`.
- `error_code` / `error_message`: privacy-safe top-level failure details for no-text, ignored-release, or runtime failure outcomes.

The end marker for "text appeared in the active input control" is focused-input delivery reporting success. The app does not read or log target application contents to prove visible text presence, because doing so would violate the privacy boundary.

### Analysis Procedure
1. Enable `UNTYPE_RELEASE_LATENCY_LOG=on`.
2. Start UI mode with `.build/debug/untype ui`.
3. Enable push-to-talk and focused input, focus a disposable editor field, press the hotkey, speak, and release.
4. Disable logging after the run.
5. Archive the JSONL file with the date and scenario name, or set `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=on` before the next isolated run.
6. Compare `total_ms` and `durations_ms`:
   - High `runtime_scheduling_ms` points to UI/runtime scheduling delay before the release request reached the runtime.
   - High `provider_final_wait_ms` points to provider finalization or endpoint/VAD behavior.
   - `text_source=quick_close_partial` with low total time confirms Quick Close avoided provider-final wait.
   - High `refine_ms` or `translate_ms` points to LLM latency.
   - High `focused_input_ms` or `focused_input.ok=false` points to Accessibility, target-control, helper, or paste/AX delivery issues.
   - `outcome=processed_without_focused_input` means the input operator was disabled or no focused-input attempt occurred.
   - `outcome=no_text` means the release produced no submitted transcript text.

### Clearing or Archiving
The logger appends during normal operation and does not rotate files. To make each application launch start with an empty configured log, set:

```env
UNTYPE_RELEASE_LATENCY_LOG=on
UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=on
```

Archive or remove the file manually when a diagnostic run must be preserved or deleted outside the startup reset flow:

```sh
mv ~/.tool-agents/untype/release-latency.jsonl ~/Desktop/release-latency-$(date +%Y%m%d-%H%M%S).jsonl
```

or:

```sh
rm ~/.tool-agents/untype/release-latency.jsonl
```

Do not leave latency logging enabled during routine use unless a diagnostic run is in progress.

## LLM Response Streaming

### Purpose

Optionally streams LLM response tokens for the refine, translate, and composite refine+translate calls instead of issuing one blocking request and waiting for the full result. When enabled, the overlay `finalizing` phase updates progressively as tokens arrive and incremental progress is also emitted to the agent-protocol JSONL output (`streaming.progress` events) and the verbose diagnostics stream. This is a perceived-latency improvement only: the focused-input insertion stays atomic and happens exactly once on completion, using the strictly-parsed final text. Streaming is implemented for the `azure-openai` (Chat Completions SSE) and `google` (Gemini `streamGenerateContent` SSE) providers; for any other provider the flag is silently inert.

### Variables and Flags

| Purpose | CLI flag | Env var | Default | Description |
| --- | --- | --- | --- | --- |
| LLM response streaming enabled | `--llm-streaming` / `--no-llm-streaming` | `UNTYPE_LLM_STREAMING` | `false` | Enables or disables streaming of LLM response tokens for refine/translate/composite. Off by default (one-shot behavior). The UI settings toggle maps to this flag via `UntypeUISettings.sessionArguments()`. |

Precedence follows the standard four-tier chain (see Configuration Priority): CLI flag > `UNTYPE_LLM_STREAMING` env var > config/UI setting > built-in default (`false`). Accepted env values: `true/false/yes/no/on/off/1/0`.

### Behavior Notes

- **Default off.** With no flag, env, or UI toggle set, behavior is identical to today's one-shot path.
- **Provider support.** Only `azure-openai` and `google` stream. With the flag on and any other active provider, streaming has no effect and raises no error (silently inert) — this is not a no-fallback-rule violation because both the flag and the provider are present and valid; no missing-required-config value is substituted.
- **Composite path.** The overlay shows a best-effort live extraction of `refined_text`/`translated_text` from the in-progress JSON for display only; the committed result is always parsed from the complete response by the existing strict parser.
- **No expiry.** This is a boolean feature toggle with no secret or expiring value, so no expiration-tracking parameter is needed.

### Recommended Storage

Set it alongside the other LLM settings in `~/.tool-agents/untype/.env` when you want streaming on by default:

```sh
UNTYPE_LLM_STREAMING=on
```

Leave it unset (or `off`) for the default one-shot behavior.
