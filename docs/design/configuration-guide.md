# Configuration Guide

## Configuration Priority
`untype` resolves configuration from the following sources, highest priority first:

1. CLI flags.
2. The current working directory `.env`.
3. `~/.tool-agents/untype/.env`.
4. Shell environment variables.

Required values must be provided explicitly. Missing required configuration raises a typed error; the application must not silently substitute a fallback for required settings.

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
| `003-translation-user-template.txt` | Yes | `Translate the following text to {target_language}. Return only the translated text.` plus `{text}` | Per-call translation template. Must contain `{target_language}` and `{text}` placeholders. |
| `004-soniox-transcription-context.txt` | No | Empty | Optional Soniox STT context. Non-empty content is sent as `context.text` in the Soniox startup config frame. |
| `005-elevenlabs-previous-text.txt` | No | Empty | Optional ElevenLabs first-chunk `previous_text` context. Must be 50 characters or fewer when ElevenLabs is selected. |
| `006-elevenlabs-keyterms.txt` | No | Empty | Optional ElevenLabs keyterm prompting. Use one keyterm per line, up to 50 terms, each 20 characters or fewer. |
| `007-composite-refine-translate-system.txt` | Yes | Built-in composite JSON prompt | System prompt used when `refine` and `translate` are both enabled for one section. The response must contain `refined_text` and `translated_text`. |
| `008-composite-refinement-template.txt` | Yes | Built-in composite refinement instruction | Refinement instruction inserted into the single composite LLM request. Must contain `{text}`. |
| `009-composite-translation-template.txt` | Yes | Built-in composite translation instruction | Translation instruction inserted into the single composite LLM request. Must contain `{target_language}`. `{text}` is also supported and resolves to the original section text. |

### Recommended Storage and Editing
Keep prompt files in `~/.tool-agents/untype/prompts/`. This folder is user-specific and outside the repository, so users can tune prompts without creating code changes. Do not store secrets in prompt files. Do not include private transcript examples unless you intentionally want them sent to the selected provider.

The repository also contains default prompt templates under `prompts/` for review and traceability. Runtime reads the user config folder, not the repository templates.

### Validation
- Required LLM prompt files must not be empty.
- `003-translation-user-template.txt` must include both `{target_language}` and `{text}`.
- `008-composite-refinement-template.txt` must include `{text}`.
- `009-composite-translation-template.txt` must include `{target_language}`.
- Soniox context must be 10,000 characters or fewer.
- ElevenLabs `previous_text` must be 50 characters or fewer.
- ElevenLabs keyterms must be one per line, no more than 50 entries, and no entry may exceed 20 characters.

Prompt contents are not written to verbose diagnostics, release latency logs, protocol JSONL events, transcript exports, or UI state.

## Push-to-talk Release Latency Logging

### Purpose
Release latency logging is an opt-in diagnostic feature for measuring the time between push-to-talk release detection and the point where focused-input delivery reports completion. It is intended for temporary analysis sessions when maintainers need to understand whether delay is coming from provider finalization, Quick Close/fallback selection, protocol processing, refinement/translation, clipboard delivery, focused-input delivery, or runtime scheduling.

The log is privacy-safe by design. It records timings, source/outcome labels, section counts, and focused-input result metadata. It must not record transcript text, processed/refined/translated text, clipboard contents, provider payloads, API keys, prompts, LLM responses, target application text, or target document contents.

### Variables and Flags

| Setting | CLI | Environment | Default | Purpose |
|---|---|---|---|---|
| Release latency logging enabled | `--release-latency-log` / `--no-release-latency-log` | `UNTYPE_RELEASE_LATENCY_LOG` | `false` | Enables or disables append-only JSONL timing records for push-to-talk release attempts. |
| Release latency log path | `--release-latency-log-path <path>` | `UNTYPE_RELEASE_LATENCY_LOG_PATH` | `~/.tool-agents/untype/release-latency.jsonl` | Selects the JSONL file used when latency logging is enabled. |
| Reset release latency log on startup | none | `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START` | `false` | Clears the configured JSONL latency log once per application process startup when release latency logging is enabled. |

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

Set `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=on` for runs where the configured latency log should start empty every time the application process launches. The reset applies to `UNTYPE_RELEASE_LATENCY_LOG_PATH` when a custom path is configured. The setting has no effect while `UNTYPE_RELEASE_LATENCY_LOG` is disabled.

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
