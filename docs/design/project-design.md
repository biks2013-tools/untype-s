# untype-s Project Design

## Purpose
`untype-s` is the Swift-native replacement project for the TypeScript `untype` implementation at `/Users/giorgosmarinos/aiwork/coding-platform/untype`. The final product must expose the installed command `untype` and preserve the public CLI, configuration, transcription, voice-agent protocol, macOS integration, and UI behavior documented by the source project.

## Source Artifacts
- Refined request: `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-swift-drop-in-replacement.md`
- Investigation: `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/investigation-swift-drop-in-replacement.md`
- Source scan: `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-source-untype.md`
- Source study: `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/source-study-untype.md`
- Compatibility checklist: `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/compatibility-checklist-swift-drop-in-replacement.md`
- Verification report: `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/verification-report-swift-drop-in-replacement.md`
- Push-to-talk release diagnostics fix:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-push-to-talk-release-no-output.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-push-to-talk-release-no-output.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-002-push-to-talk-release-no-output.md`
- Quick Close push-to-talk release policy:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-quick-close.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-quick-close.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-022-quick-close.md`
- Push-to-talk release latency logging:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-push-to-talk-release-latency-logging.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-push-to-talk-release-latency-logging.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-023-push-to-talk-release-latency-logging.md`
- Release latency log reset on start:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-release-log-reset-on-start.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-release-log-reset-on-start.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-026-release-log-reset-on-start.md`
- Transcript/events export copy:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-transcript-events-export-copy.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-transcript-events-export-copy.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-006-transcript-events-export-copy.md`
- Turn-level transcript copy:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-turn-level-copy-buttons.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-turn-level-copy-buttons.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-030-turn-level-copy-buttons.md`
- Overlay wrapping correction:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-overlay-position-wrap-correction.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-overlay-position-wrap-correction.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-010-overlay-text-wrap-restoration.md`
- Overlay bottom indicator adjustment:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-overlay-bottom-indicators.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-overlay-position-wrap-correction.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-011-overlay-bottom-indicators.md`
- UI window state persistence:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-ui-window-state-persistence.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-ui-window-state-persistence.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-012-ui-window-state-persistence.md`
- UI session conversation history:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-ui-session-conversation-history-tab.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-ui-session-conversation-history-tab.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-013-ui-session-conversation-history-tab.md`
- Push-to-talk release transcript/history retention:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-fix-history-release-disappearing-transcript.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-fix-history-release-disappearing-transcript.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-014-fix-history-release-disappearing-transcript.md`
- Native UI modernization proposal:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-macos-ui-modernization-proposal.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/macos-ui-guidelines-modernization-research.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-016-macos-ui-modernization-proposal.md`
- Monitor sidebar collapse:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-018-monitor-sidebar-collapse.md`
- Bundled app focused-input delivery:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-bundled-app-focused-input-delivery.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-bundled-app-focused-input-delivery.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-029-bundled-app-focused-input-delivery.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-033-focused-input-target-restoration.md`
- Global push-to-talk hotkey regression:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-global-push-to-talk-hotkey-regression.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-global-push-to-talk-hotkey-regression.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-031-global-push-to-talk-hotkey-regression.md`
- Manual permission setup popup:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/refined-request-manual-permission-popup-option.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-manual-permission-popup-option.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/design/plan-032-manual-permission-popup-option.md`
- Research:
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/research/avfoundation-audio-capture.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/research/soniox-websocket-swift.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/research/elevenlabs-realtime-stt-swift.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/research/macos-ui-hotkey-overlay.md`
  - `/Users/giorgosmarinos/aiwork/coding-platform/untype-s/docs/research/swift-testing-distribution.md`

## Architecture
The project uses Swift Package Manager as the authoritative build structure. The executable product is named `untype`; the repository name `untype-s` is only the project folder name.

The minimum supported platform is macOS 14. `Package.swift` declares `.macOS(.v14)`, and the audio permission implementation intentionally uses the modern macOS 14 `AVAudioApplication` permission API path researched in `docs/research/avfoundation-audio-capture.md`.

Planned module boundaries:
- `untype`: thin executable entry point.
- `UntypeCore`: shared errors, exit codes, version, runtime events, and compatibility types.
- `UntypeConfig`: CLI schema, env-chain resolution, typed parsers, expiry warnings.
- `UntypeCLI`: command dispatch, stdout/stderr routing, renderer, process exit mapping, signal handling.
- `UntypeProtocol`: marker matching, state machine, JSONL writer, settings persistence.
- `UntypeProviders`: provider-neutral transcriber protocol plus Soniox and ElevenLabs adapters.
- `UntypeAudio`: audio-source protocol and native AVFoundation capture.
- `UntypeLLM`: Azure OpenAI and Google refiners plus accepted provider stubs.
- `UntypeMacOS`: focused input, permission diagnostics, hotkey/event tap, overlay support.
- `UntypeUI`: SwiftUI/AppKit UI replacement for `untype ui`.

Initial implementation may combine some modules while the skeleton stabilizes, but the public boundaries above are the target decomposition for autonomous implementation work.

## Design Decisions
- SwiftPM-first architecture follows the investigation recommendation in `docs/reference/investigation-swift-drop-in-replacement.md`.
- CLI/protocol/provider parity is the first implementation milestone, but the project is not considered a final drop-in replacement until `untype ui` parity is complete.
- Native AVFoundation capture replaces the source project's `sox` subprocess. `sox` must not be used as a hidden fallback.
- Soniox and ElevenLabs are implemented as direct WebSocket adapters over a mockable transport boundary.
- Azure OpenAI and Google LLM refiners are implemented for parity; the other six accepted LLM provider names remain explicit stubs until approved.
- UI parity uses SwiftUI for views and AppKit for lifecycle, non-activating overlay, and macOS event/permission details.
- Bundled app focused-input delivery runs the existing AX/paste/Unicode insertion implementation in the UI process so macOS TCC permissions apply to the app/`untype` UI identity; CLI runs continue using the sibling `untype-input-helper` subprocess. Bundled detection accepts both the `.app` bundle URL and executable paths inside `.app/Contents/MacOS`, and UI sessions now force in-process delivery even for unbundled `untype ui` launches so the native UI does not require separate Accessibility permission for `untype-input-helper`. Browser targets use paste-keycode before Unicode fallback to avoid fragile AX value insertion in browser text fields, and `ok=false` delivery results are surfaced as input-operator warnings instead of false `input.sent` success. Native UI sessions also track the most recent external foreground application and restore the captured target before focused-input delivery when `untype.app` has regained focus during finalization. This decision follows the bundled app integration points in `docs/reference/codebase-scan-bundled-app-focused-input-delivery.md` and the target-restoration plan in `docs/design/plan-033-focused-input-target-restoration.md`.
- Tests use `swift test`; live provider and macOS permission checks are documented manual smoke tests under `test_scripts/`.

## Configuration
The configuration precedence chain is:
1. CLI flag
2. `<cwd>/.env`
3. `~/.tool-agents/untype/.env`
4. Shell environment

Missing required values raise typed errors. The project must not invent fallback values for required settings.

The current Swift configuration resolver implements the source CLI/config surface for STT provider selection (`soniox`, `elevenlabs`), provider-specific model/endpoint/language defaults, language and sample-rate validation, endpoint detection, Quick Close push-to-talk release policy, push-to-talk release latency logging, output mode, protocol marker/operator defaults, hybrid protocol-output validation, LLM provider/model startup validation, API-key expiry warnings, source-compatible `.env` parsing behavior, and the legacy `~/.tool-agents/mic-tool-ts/` migration guard. This design follows the source contract documented in `docs/reference/source-study-untype.md`, the CLI/config phase in `docs/design/plan-001-swift-drop-in-replacement.md`, the Quick Close extension in `docs/reference/codebase-scan-quick-close.md`, and the release latency logging integration points in `docs/reference/codebase-scan-push-to-talk-release-latency-logging.md`.

Release latency logging is disabled by default and can be enabled with `--release-latency-log` or `UNTYPE_RELEASE_LATENCY_LOG=on`. When enabled, records append to `~/.tool-agents/untype/release-latency.jsonl` unless `--release-latency-log-path` / `UNTYPE_RELEASE_LATENCY_LOG_PATH` specifies another path. `UNTYPE_RELEASE_LATENCY_LOG_RESET_ON_START=on` clears the configured log once per application process startup before new records are written; the reset is guarded per process so UI warm-session restarts do not erase records mid-run. The full setting guide, log schema, privacy boundary, and manual analysis workflow are maintained in `docs/design/configuration-guide.md`.

Prompt configuration is loaded at startup from `~/.tool-agents/untype/prompts/`, as specified by `docs/reference/refined-request-configurable-prompts.md`, `docs/reference/codebase-scan-configurable-prompts.md`, `docs/research/stt-prompt-context-fields.md`, `docs/design/plan-024-configurable-prompts.md`, `docs/reference/refined-request-composite-refine-translate-prompt.md`, `docs/reference/codebase-scan-composite-refine-translate-prompt.md`, and `docs/design/plan-025-composite-refine-translate-prompt.md`. The resolver provisions missing prompt files with the current default content, then reads the user-editable files into `PromptConfig`. Required LLM prompt files cover refinement, translation system behavior, the translation user template, and the composite refine-plus-translate prompt set. The composite set contains one system prompt, one refinement prompt template, and one translation prompt template so a combined section can be served by one LLM call. Provider-specific STT files cover Soniox `context.text`, ElevenLabs first-chunk `previous_text`, and ElevenLabs realtime keyterms. Prompt contents are not logged or persisted in diagnostics, release-latency records, UI state, protocol JSONL events, or transcript exports.

## Rendering
The current Swift renderer implements the source output modes:
- `overwrite`: TTY-only carriage-return rendering for partials, wrapped-row cleanup, final-line commit, refined-output commit, and dispose cleanup.
- `append`: pipe-safe line-per-partial/final rendering with duplicate partial suppression.
- `final-only`: suppresses partials and emits committed finals only.

When `overwrite` is requested for a non-TTY destination, the renderer downgrades to `append` so piped output does not contain carriage returns. The renderer also filters `<end>` and `<fin>` marker tokens before output.

## Voice-Agent Protocol Runtime
The current Swift protocol runtime implements the source-compatible, provider-independent voice-agent primitives:
- marker normalization and matching for state commands, section submit/cancel markers, Greek guard aliases, slash-style markers, and literal-next behavior;
- operator state changes for `refine`, `translate`, `clipboard`, and `input`, including runtime toggles and status reports;
- section lifecycle handling with stable `sec_000001`-style identifiers, spoken cancellation, shutdown cancellation, and optional shutdown submission;
- JSONL event writing with source event names and monotonically increasing `seq` values;
- non-secret protocol settings persistence at `~/.tool-agents/untype/state.json` with mode `0600`, storing only operator booleans and translation policy.
- session/controller routing for partial/final transcript events across `dictation`, `agent-protocol`, and `hybrid` modes;
- source-compatible section processing order: raw section submission, optional refinement, optional translation, processed event/rendering, clipboard delivery, and focused-input delivery;
- fail-open protocol warnings for missing LLM operators and focused-input delivery failures.
- provider-neutral session orchestration that starts/stops mockable audio and realtime transcriber implementations, forwards PCM audio to STT, forwards STT partial/final events into the protocol controller, supports push-to-talk pending submission, persists non-secret protocol settings on shutdown, and emits typed session lifecycle events.
- opt-in push-to-talk release latency records that append one JSONL object per release attempt when explicitly enabled. Records capture release timestamp, total elapsed time from UI release detection, UI-to-runtime scheduling delay, provider finalization wait, text-source selection, protocol/operator timings, focused-input delivery timing/result metadata, and privacy-safe failure codes without transcript text, processed text, clipboard contents, prompts, secrets, provider payloads, or target application contents.

The runtime now includes a concrete AVFoundation audio source behind the existing `RuntimeAudioSource` boundary. It preflights macOS microphone permission with typed `microphone_permission` failures, installs an `AVAudioEngine` input tap, converts captured input to mono 16-bit PCM at the configured sample rate, and reports capture/conversion failures as typed `microphone_capture` errors. Runtime startup starts microphone capture before waiting for the realtime STT WebSocket to finish connecting, so the UI can show audio activity while provider startup is still in progress. Synthetic conversion tests cover the PCM16 converter; live permission/capture smoke testing remains pending. The smoke procedure is documented in `test_scripts/microphone-live-smoke.md`.

The CLI now builds a live `TranscriptionSessionRuntime` through `UntypeRuntimeFactory`: it loads persisted non-secret protocol settings, applies them only to defaults, creates the renderer and optional protocol JSONL writer, selects `AVFoundationAudioSource`, selects the configured Soniox or ElevenLabs transcriber, starts the session, waits asynchronously for `SIGINT` or `SIGTERM`, submits pending provider output on shutdown, persists the latest non-secret protocol settings, and maps recorded runtime failures back to typed exit codes. Agent-protocol mode writes JSONL protocol events to stdout when no `--protocol-output` is configured; hybrid mode continues to require a protocol output file.

## macOS Clipboard and Focused Input
The protocol controller now uses concrete macOS delivery implementations in the live runtime:
- `MacOSClipboardWriter` writes processed section output directly to `NSPasteboard.general` without passing text through process arguments.
- `FocusedInputDelivery` launches a sibling `untype-input-helper` executable with arguments limited to `send --method <method>` and writes processed text through the helper process stdin.
- UI sessions execute the same focused-input implementation in-process instead of spawning the helper, preserving stdin-style data flow while aligning Accessibility/Input Monitoring checks with the app or `untype ui` process identity.
- UI sessions prepare focused-input delivery by restoring the captured external foreground app when the `untype` window is frontmost, avoiding accidental delivery into the app's own SwiftUI controls.
- `untype-input-helper` is a Swift executable target that preserves the source helper contract: `diagnose`, `send --method auto|ax-value|unicode-events|paste-keycode`, one JSON result line on stdout, diagnostics on stderr, exit code `0` for success, and exit code `2` for expected delivery failures.
- The helper attempts Accessibility AX value insertion first for normal targets. For browser targets, where AX value insertion is commonly unreliable, it tries the clipboard-preserving Command-V paste path first and falls back to Unicode key events only for short text. This keeps the default path from simulating one key pair per character in browser/editor fields. Accessibility denial returns `accessibility_not_trusted` with an actionable message.
- Focused-input failures remain fail-open protocol warnings so transcription sessions continue when the target control is unavailable or permissions are missing.

Automated tests verify helper JSON parsing, expected failure handling, stdin-only text delivery, command parsing, and injected clipboard writing. The live focused-input permission and delivery smoke procedure is documented in `test_scripts/focused-input-smoke.md`; manual execution remains pending.

## LLM Refinement and Translation
The current Swift LLM layer preserves the source project's two implemented provider contracts without adding runtime dependencies:
- `AzureOpenAIRefiner` calls the Azure OpenAI Chat Completions REST endpoint with the configured endpoint, deployment, API version, `api-key` header, system prompt, user transcript, and `temperature=0.2`.
- `GoogleRefiner` calls Gemini `generateContent` with `systemInstruction`, a single user content part, the configured model, API key query parameter, and `temperature=0.2`.
- Both refiners use a mockable HTTP client boundary, trim successful text, map HTTP 401/403 to auth failures, map other non-2xx responses to server failures, map malformed JSON or missing output text to response-shape failures, and cancel in-flight requests on dispose.
- `LLMRefinerFactory` returns nil when LLM refinement is disabled, constructs concrete Azure OpenAI or Google refiners when enabled, and raises configuration errors for the six accepted-but-unimplemented provider names (`openai`, `anthropic`, `azure-ai-inference`, `ollama`, `litellm`, `openai-compat`).
- `UntypeRuntimeFactory` wires refinement, translation, and composite refine-plus-translate processor instances into the voice-agent protocol controller. The translator reuses the selected provider with the source-compatible translation system prompt. The composite processor reuses the selected provider with the composite system prompt and returns a parsed JSON result containing `refined_text` and `translated_text`.
- When a protocol section has both `refine` and `translate` active and the composite processor is configured, the controller makes one composite LLM request, records the raw text, refined text, source/target language metadata, and translated output, and skips the sequential refine-then-translate path. If the composite call fails or returns malformed JSON, the failure remains fail-open and the controller does not attempt a second sequential fallback.

Runtime LLM failures remain fail-open at the protocol controller boundary: refinement or translation errors do not terminate the transcription session, and verbose diagnostics include the failure kind. Startup LLM configuration failures remain fatal configuration errors with exit code `2`.

## Soniox Provider Adapter
The current Swift Soniox adapter implements the provider-facing WebSocket frame contract behind a mockable `RealtimeWebSocketClient` boundary:
- concrete live transport over `URLSessionWebSocketTask`, including an async receive loop that routes text frames into the adapter and maps receive failures to typed Soniox network errors;
- startup sends one JSON configuration frame with API key, model, `pcm_s16le`, sample rate, mono channel count, endpoint detection, and either language hints or language identification;
- audio chunks are sent as binary WebSocket frames only after the socket is connected;
- manual commit sends the source-compatible `{"type":"finalize"}` control frame and shutdown sends the empty finish sentinel before closing;
- incoming JSON result frames are parsed for tokens, marker tokens `<end>` and `<fin>` are filtered, finalized text is merged defensively to tolerate repeated prefixes, and endpoint/finalized/finished messages flush committed final text;
- Soniox server errors and transport failures are mapped to typed `soniox_auth`, `soniox_network`, or `soniox_protocol` errors.

The adapter is verified with mocked transport tests. Live Soniox smoke testing remains pending. The live smoke procedure is documented in `test_scripts/soniox-live-smoke.md`.

After push-to-talk release diagnostics exposed a live Soniox timeout, the direct Swift parser was corrected to process `tokens` before handling a same-frame `endpoint`, `finalized`, or `finished` marker. This preserves final tokens when the WebSocket server combines semantic finalization and token payloads in one JSON message, allowing the runtime to receive a final transcript instead of leaving only post-release partial lines.

## ElevenLabs Provider Adapter
The current Swift ElevenLabs adapter implements the provider-facing WebSocket frame contract behind the same mockable `RealtimeWebSocketClient` boundary:
- concrete live transport support over `URLSessionWebSocketTask` via a `URLRequest` that sets the source-compatible `xi-api-key` header;
- realtime URL construction with `model_id`, `audio_format=pcm_<sampleRate>`, `sample_rate`, VAD/manual `commit_strategy`, `include_timestamps=false`, and optional `language_code` when the configured language is not `auto`;
- audio chunks are sent as JSON text frames with `message_type=input_audio_chunk`, base64 PCM payloads, and the configured sample rate;
- manual commit sends an empty base64 audio payload with `commit=true`, and shutdown attempts a best-effort final commit before closing;
- incoming JSON events route non-empty partial transcripts to partial output and trimmed committed transcripts to final output for both timestamped and non-timestamped event names;
- ElevenLabs server errors and transport failures are mapped to typed `elevenlabs_auth`, `elevenlabs_network`, or `elevenlabs_protocol` errors.

The adapter is verified with mocked transport tests. Live ElevenLabs smoke testing remains pending. The live smoke procedure is documented in `test_scripts/elevenlabs-live-smoke.md`.

## Native UI Mode
`untype ui` now dispatches to a SwiftUI/AppKit launcher instead of returning a placeholder error. The UI is implemented inside the SwiftPM executable process and reuses the existing Swift runtime factory rather than spawning the CLI or parsing terminal output.

The current UI phase includes:
- a native monitoring window with credential status, provider/session settings, protocol operator switches, LLM settings, push-to-talk controls, transcript display, and bounded event log;
- a collapsible right-side settings pane built from aligned label/control rows inside material-backed glass sections, keeping status values, pickers, text fields, steppers, toggles, and push-to-talk actions visually consistent while allowing the monitor area to use the full window width; the hidden/visible state is restored across UI launches;
- initial UI state loading through the same config chain as the CLI, with persisted UI settings converted to CLI-equivalent arguments and an inspection-only LLM validation mode so missing LLM secrets can be reported in the UI without blocking configuration display;
- non-secret UI settings persistence at `~/.tool-agents/untype/ui-state.json` with mode `0600` under a `0700` config directory, including main window width/height, leading monitor-sidebar visibility, settings-pane visibility, and selected monitor tab while excluding transient credential status, permission status, transcript text, event-log content, and secrets;
- credential inspection that reports API-key name, configured/missing status, source tier, and expiry value without exposing API-key values;
- transient macOS permission inspection that reports Microphone authorization and Accessibility trust in the UI without persisting those host-specific status values;
- explicit permission setup actions in the top control cluster and Permissions inspector that open the existing onboarding/permission setup sheet on demand, bypassing the automatic 24-hour skip suppression while preserving the existing automatic onboarding behavior. This gives users a manual way to revisit Microphone, Accessibility, Input Monitoring, and provider setup guidance after the app is already running, following `docs/reference/codebase-scan-manual-permission-popup-option.md`;
- a UI-specific runtime factory path that routes transcript events through a typed `UITranscriptEvent` renderer and protocol/diagnostic text into the UI;
- microphone audio activity reporting that emits privacy-safe PCM peak/byte-count snapshots from the runtime and displays `Audio: waiting`, `silent`, `active`, or `muted by push-to-talk` in the UI before any STT transcript arrives;
- throttled runtime audio activity emission and UI event-log diagnostics that record `audio.input` lines from those snapshots, including whether the provider receives microphone audio or silence because the push-to-talk gate is closed. Repeated same-category audio activity is rate-limited before it reaches SwiftUI, while active/silent/muted category changes still surface immediately;
- a clearable grouped transcript timeline that keeps partial text separate from committed turns, groups raw dictated text and processed output in the same turn, and clears only visible UI history without stopping the session or persisting transcript text;
- explicit transcript and event export controls in the monitoring tabs. Transcript and Events each expose `Copy` and `Save` actions when content exists. Copy writes the current extracted plain text to the macOS pasteboard, while Save opens a user-chosen `NSSavePanel` destination and writes UTF-8 text atomically. Transcript export includes committed turns, bubble labels/statuses, and live partial text; event export preserves the retained event log lines in chronological order. Individual Transcript and History turn sections also expose compact explicit copy controls for raw dictated text and processed refine/translate output, each writing only that section's text to the pasteboard. This remains explicit user-triggered persistence only, matching the scope in `docs/reference/refined-request-transcript-events-export-copy.md`, `docs/reference/refined-request-turn-level-copy-buttons.md`, and the integration points in `docs/reference/codebase-scan-transcript-events-export-copy.md` and `docs/reference/codebase-scan-turn-level-copy-buttons.md`;
- a primary Quartz `CGEvent` tap for system-wide push-to-talk press/release handling and hotkey suppression, a Carbon `RegisterEventHotKey` global press/release registration as a redundant background-focus fallback, AppKit `NSEvent` monitors retained as the last fallback/local path, and visible status text when the tap cannot start;
- `R`/`T`/`C`/`I` operator toggles while recording, routed through the same runtime operator channel as UI switches;
- source-compatible active-session editing rules: provider, model, languages, sample rate, endpoint detection, protocol mode, translation policy, LLM, and push-to-talk settings are locked while a manual, warm, or recording session is active, while the four protocol operator switches remain editable and route to the active protocol controller;
- source-style push-to-talk sessions: enabling push-to-talk starts a hotkey-owned warm runtime with the audio gate closed, pressing the hotkey opens the gate and clears any stale live partial, releasing closes the gate, waits for provider final text, submits the current turn for refine/translate/clipboard/focused-input processing, stops that provider session, then starts a fresh warm runtime for the next press;
- provider-failure handling for warm push-to-talk sessions: if the provider/transcriber records a runtime failure while a hotkey-owned session is stopping, the UI records the error and skips automatic warm-session restart so fatal provider errors do not loop;
- startup-safe warm-session stopping: `Stop Warm Session` cancels a hotkey-owned session even while it is still in `starting`, resets the UI to idle when no runtime has been assigned yet, and prevents provider startup from racing back to `listening` after a concurrent stop;
- a Push to Talk press/release fallback button that uses the same hotkey-owned runtime and overlay path when macOS does not deliver keyboard hook events;
- UI mode enters AppKit directly on the executable's initial main thread instead of wrapping the blocking `NSApplication.run()` call in `MainActor.run`; UI session startup and callbacks use background tasks plus AppKit main-queue dispatch so the native event loop can advance runtime startup to `listening`;
- privacy-safe hotkey diagnostics that record whether a press/release came from the Quartz event tap, local monitor, global monitor, or UI button without logging transcript text or secrets;
- key-repeat guarded push-to-talk handling: the hotkey monitor ignores autorepeated key-down events for the configured push-to-talk key in both Quartz and AppKit paths, preventing a held key from repeatedly restarting sessions if release handling is delayed or fallback state changes. Normal `keyUp`/`flagsChanged` release handling remains the source of truth, with the explicit press-to-toggle fallback retained when the event tap cannot start.
- background-focus push-to-talk hardening: the hotkey monitor now starts Carbon global hotkey registration alongside the Quartz event tap, using the same shared press/release state to dedupe duplicate events. If the Quartz tap cannot start or stops receiving key events while another app has focus, Carbon pressed/released events can still open and close the push-to-talk session. This follows the integration points in `docs/reference/codebase-scan-global-push-to-talk-hotkey-regression.md`.
- release-time diagnostics for the push-to-talk output pipeline: UI-owned sessions now show when release requests provider final text, when submitted text enters protocol processing, when processing completes, and when no provider final text arrives before the finalization timeout. Operator attempts and failures for refine, translate, clipboard, and focused input are privacy-safe UI diagnostics, and release/operator warnings are surfaced in the transcript timeline so the monitor is not silent when output cannot be produced.
- finalization fallback for realtime providers that keep returning partial hypotheses after release: the runtime remembers the latest visible partial transcript in memory for the active session and, only after provider finalization times out without any final text, submits that latest partial through the normal protocol path with an explicit warning. After the release submission commits, late provider partial callbacks are suppressed for that ending provider session so stale partial lines do not appear around the processed output.
- configurable Quick Close for push-to-talk release: when enabled, the runtime submits the latest active-turn partial transcript immediately if no provider final text is already pending, then runs the same protocol/refine/translate/clipboard/focused-input pipeline and suppresses late provider callbacks from the ending session. When disabled, the existing finalization wait and timeout fallback behavior remains unchanged. The setting is exposed through `--quick-close` / `--no-quick-close`, `UNTYPE_QUICK_CLOSE`, and the native UI Push to Talk inspector as non-secret persisted UI state.
- opt-in release latency diagnostics for push-to-talk sessions: when `UNTYPE_RELEASE_LATENCY_LOG=on` or `--release-latency-log` is active, UI hotkey release attempts append structured JSONL timing records to the configured latency log file. The end marker for active-control appearance is focused-input delivery reporting success; the app does not inspect or log target control contents.
- a tabbed monitoring area that separates the transcript timeline, session history, and event log so each monitor view can use the full available vertical space while preserving the existing transcript controls and event auto-scroll behavior. The selected `Transcript`, `History`, or `Events` tab is restored across UI launches.
- a session-local `History` monitor tab derived from the same in-memory transcript timeline as the `Transcript` tab. It shows retained current-session conversations, the raw dictated text recorded for each turn, processed refine/translate output recorded by the application, and session warning records when present. The selected `History` tab value can be restored across UI launches, but the conversation history content itself remains in memory only and is not written to `ui-state.json`.
- push-to-talk warm-session restarts preserve committed timeline/history content. Starting a new provider runtime clears only stale live partial text, while explicit `Clear` remains the path that removes committed Transcript and History entries during the current UI session.
- a bottom-center non-activating `NSPanel` push-to-talk overlay (fixed 180×84 pt, transparent, status-bar window level, every Space) that carries no transcript text: an oscilloscope trace of the real microphone signal plus a row of `R`/`T`/`C`/`I` operator chips (solid amber when on, dim outline when off) reminding the user they can toggle them while holding the hotkey. PCM chunks reach the overlay through `RuntimeAudioGate.observeAudioSamples` (implemented by `HotkeySessionControl`, only while the gate is open) into `UntypeWaveformBuffer`, which averages them to 2,000 points/s and scrolls continuously between chunks; `UntypeWaveform` applies automatic gain (quiet speech swings to full height, silence stays a small ripple). While the release is processed a small travelling ripple is shown. A fresh panel is created on every appearance, because a long-lived hidden panel could be left pinned to one Space.
- menu-bar presentation (`UntypeMenuBarController`): untype is an accessory app (`LSUIElement`, no Dock icon or Cmd-Tab entry) with a waveform status item (mic badge while recording). Clicking it drops the main window (full or compact layout, same toolbar) under the icon — not movable, no window buttons, hidden when untype loses focus or the icon is clicked again. A toolbar button or the icon's right-click menu pops it out into an ordinary movable window (frame autosaved); clicking the icon, the toolbar button or the close button docks it back. Close/Cmd+W never quits; Quit is in the icon menu and Cmd+Q. The detached state is persisted (`untype.windowDetached`) and restored at launch; otherwise the window opens at launch only while setup (microphone, Accessibility, credentials) is incomplete. Because pressing the icon deactivates untype before the click action runs, a click within 0.4 s of such an auto-hide counts as "close".
- live focused-input typing (`LiveFocusedInputTyper`): while push-to-talk is held with Focused input on, the transcript (accumulated finals plus the current partial) is typed straight into the focused control of the app that was frontmost at press, with Unicode keyboard events diffed against what is already typed. On release, the final (refined/translated) text replaces the live text with the same keystrokes (delete the differing tail, type the rest); a remainder containing a line break is pasted instead, since a typed newline would press Return. Live keystrokes carry `untypeSyntheticKeyboardEventMarker` in `eventSourceUserData` and every hotkey monitor ignores them, so a synthetic key-up can never release push-to-talk. Turns without live text use the unchanged focused-input delivery; a live turn logs `focused_input.method=live-typed`.

The UI uses `ConfigResolver(requireProtocolOutputForHybrid: false)` only for UI-owned configuration display and sessions so hybrid protocol events can be rendered in the window without requiring a JSONL file path. CLI behavior is unchanged: `--interaction-mode hybrid` still requires `--protocol-output`. Runtime sessions still use strict provider validation; the inspection-only LLM validation path is limited to initial UI settings loading so it does not provide fallback credentials or silently run with missing secrets.

The UI process installs a native AppKit application menu instead of relying on default window behavior. The menu restores standard macOS shortcuts for UI mode, including `Command+Q` for Quit, `Command+W` for Close Window, and standard Edit menu actions for text controls.

The main session button now reflects the active capture state with source-style labels: `Start Listening`, `Stop Listening`, `Stop Warm Session`, and `Stop Recording`.

The full-size UI places session/action controls in a custom titlebar-height strip anchored to the top-right of the center monitor column instead of the left native toolbar area. This keeps the controls level with the macOS traffic lights while aligning them with the main working area between the sidebar and trailing inspector. The strip preserves the existing record/start/stop, refresh, appearance, inspector, and compact-mode actions and their keyboard shortcuts.

The titlebar brand mark/app-name area toggles the leading Monitor sidebar. Hiding the sidebar expands the monitor content pane into the freed space, and restoring uses the same always-visible titlebar brand mark. The hidden/visible state is stored as non-secret UI layout state in `ui-state.json`.

The Transcript action row measures the usable center monitor column width after the leading sidebar and trailing inspector take their space. When that central width falls below the labeled-chip threshold, the `Refine`, `Translate`, `Clipboard`, and `Input` operator chips hide their text labels and keep only the status dot plus `R`, `T`, `C`, or `I`, preventing the chip text from wrapping while preserving the same toggle actions and accessibility labels.

The push-to-talk overlay follows the same appearance choice as the main app (`system`, `light`, or `dark`) even though it is hosted in a separate non-activating `NSPanel`. Its compact `R`/`T`/`C`/`I` operator indicators use the main app's amber chip language with status dots, and its phase indicator uses a compact status-pill treatment with the same phase tone colors as the main window.

Live UI verification is documented in `test_scripts/ui-mode-smoke.md` and remains pending. Signed/notarized app distribution is still an open design gap.

Deployable macOS application packaging is documented in `docs/design/deployment-guide.md`. The current project remains a SwiftPM executable package, so the production deployment path is to bundle the release executable and helper into `untype.app`, add app metadata and microphone usage text, sign with Developer ID and hardened runtime, notarize the archive, staple the ticket, and verify Gatekeeper behavior before distributing.

The repository includes `scripts/package-macos-app.sh` for repeatable macOS packaging. The script builds SwiftPM release outputs, runs tests by default, creates `untype.app`, declares `untype` itself as `CFBundleExecutable`, opens UI mode for no-argument app-bundle launches, adds microphone metadata and `PkgInfo`, uses `packaging/macos/untype.entitlements`, includes `packaging/macos/AppIcon.icns` by default, removes removable extended attributes when possible, optionally signs with Developer ID, optionally notarizes/staples with `notarytool`, and writes clean `ditto --norsrc` distributable archives under `.build/deploy/`.

The packaged app intentionally does not use a separate `untype-launcher` executable. The process that LaunchServices starts is the same `untype` process that installs the Quartz push-to-talk event tap, keeping Accessibility/Input Monitoring identity aligned with the app bundle that users authorize in System Settings.

The default app icon source lives at `packaging/macos/AppIcon.svg`, with generated review and packaging artifacts at `packaging/macos/AppIcon.png`, `packaging/macos/AppIcon.iconset/`, and `packaging/macos/AppIcon.icns`. The selected mark is based on the user-provided orange `u` reference icon: a warm orange rounded-square tile with a centered white rounded lowercase `u`, adapted with macOS-style depth and highlights. Release packaging can still override the icon with `scripts/package-macos-app.sh --icon`.

### Proposed macOS UI Modernization
The proposed next UI direction is documented in `docs/design/plan-016-macos-ui-modernization-proposal.md` and is grounded in the current source review, Apple Human Interface Guidelines research in `docs/reference/macos-ui-guidelines-modernization-research.md`, and a Claude Design handoff bundle saved at `docs/reference/design-bundle-macos-modernization/`.

The proposal keeps the existing native SwiftUI/AppKit runtime model, privacy boundaries, settings persistence, active-session editability rules, transcript/history/events data model, export semantics, and non-activating push-to-talk overlay. It reorganizes the visual shell into a conventional macOS structure:
- a titlebar-height control strip for frequent actions and session control, with a primary record button and refresh/inspector affordances aligned to the center monitor column;
- leading source-list navigation for Transcript, History, and Events;
- a main content work area for the selected monitor surface, with a tinted-accent operator chip row (R/T/C/I) and a deterministic waveform readout;
- a trailing inspector-style settings pane (grouped `Form`) for credentials, system status, provider, protocol, LLM, and push-to-talk configuration;
- compact status pills for session, capture, audio, output, and permissions;
- a `.regularMaterial` dictation HUD overlay with phase indicator, four operator chips, and a wrap-stable transcript line.

#### Visual Direction (locked)
Per the design bundle and chat transcript (`docs/reference/design-bundle-macos-modernization/chats/chat1.md`):

- **Direction**: V1 Classic Sidebar from `main-windows.jsx:UnMainV1`. It is the closest variant to the existing `UntypeRootView` HStack and minimizes data-plumbing churn.
- **Accent**: warm amber (`Color.accentColor` resolved to the values in `shared.jsx:UN_THEMES.{light,dark}.accent`), used sparingly — primary record button, active operator chip, and brand mark only. Other surfaces rely on system materials.
- **Material**: native SwiftUI materials (`.regularMaterial`, `.thinMaterial`) — NOT a literal port of the bundle's blur/saturate stack. This aligns with the existing plan-016 guidance against custom glass-card stacking and keeps the app feeling natively macOS.
- **Overlay**: Card variant from `peripheral.jsx:OverlayCard`. Best fit for the wrap-grow text behavior already implemented in `UntypeOverlayLayout`.
- **Out of scope**: Menubar status item dropdown, V2/V3 main-window variants, manual light/dark switching (the design supports both because all colors derive from the system accent + materials).

Provenance for every UI module that lands under this plan must cite the corresponding design file in `docs/reference/design-bundle-macos-modernization/project/` to keep the chain auditable. The modernization is now in active implementation under plan-016; each phase of that plan tracks its own acceptance criteria.

## CLI Voice Command Responsiveness
The CLI and UI runtime now ask the active STT provider to commit as soon as a partial transcript contains an actionable protocol marker such as `command status`, `command send`, or `command cancel`. Finalized transcripts still remain the only place where protocol actions execute, but this partial-triggered commit avoids the live CLI appearing unresponsive when the provider keeps voice commands in partial output until VAD, endpoint detection, or shutdown. The runtime deduplicates repeated partial snapshots so a single visible command does not repeatedly commit the provider.

## Optional Configurable LLM Response Streaming (Design 034 — 2026-06-20)

Provenance chain (refined-request -> research -> scan -> plan -> design):
- Refined request: `docs/reference/refined-request-llm-streaming-toggle.md`
- Research: `docs/research/swift-urlsession-sse-azure-openai-streaming.md`, `docs/research/gemini-streaming-and-partial-json.md`
- Codebase scan: `docs/reference/codebase-scan-llm-streaming-toggle.md` (commit `e70d4fb…` == HEAD)
- Plan: `docs/design/plan-034-llm-streaming-toggle.md`
- Design: `docs/design/design-034-llm-streaming-toggle.md`

Adds an off-by-default, user-toggleable feature that streams LLM **response tokens** for the
`azure-openai` and `google` providers (Azure Chat Completions SSE `"stream": true`; Gemini
`:streamGenerateContent?alt=sse`), renders the refined/translated text progressively in the overlay
`finalizing` phase, and emits incremental progress to the agent-protocol JSONL output and verbose
diagnostics — while keeping the one-shot path, atomic focused-input delivery, and push-to-talk wiring
intact. The feature is implemented as NEW integration points wired into the existing surface, never a
parallel pipeline or a replacement of the one-shot `perform` path.

Key design decisions (full rationale in the design file):
- Single switch `LLMConfig.streamingEnabled: Bool` (default `false`), threaded from
  `ConfigResolver` (`--llm-streaming`/`--no-llm-streaming`, `UNTYPE_LLM_STREAMING`, UI toggle via
  `sessionArguments()`) and read by the refiners; the two `LLMRefinerFactory` clones forward it
  automatically. This is an optional-toggle default, NOT a no-fallback violation; the flag is
  silently inert for non-`azure-openai`/`google` providers (resolved open question #3).
- Additive `LLMHTTPClient.stream(_:timeoutMs:) -> AsyncThrowingStream<String, Error>` alongside the
  unchanged buffered `perform`, using `URLSession.bytes(for:)` + `.lines` with status validated
  before the body and a parallel `activeStreamTasks` registry feeding `cancelAll()` (since
  `bytes(for:)` does not expose the `URLSessionDataTask`) — preserving the push-to-talk new-session
  teardown that aborts in-flight streams.
- Streaming refine dispatched via a narrow `StreamingTextRefining` protocol + runtime `as?` cast,
  and an additive default-nil `onProgress` overload on `CompositeRefineTranslating.refineAndTranslate`,
  both yielding ACCUMULATED display text; the committed result is always the strict final parse of the
  complete response. Composite display uses a best-effort escape-aware `partialStringValue(forKey:in:)`
  extractor for `refined_text`/`translated_text` (DISPLAY ONLY; resolved open question #1).
  - **Update (2026-06-20, code review):** `TextRefining` was deliberately left UNCHANGED rather than
    gaining a `refine(_:onProgress:)` protocol requirement as Decision 2 / contract C3 originally
    specified. Adding a method to the widely-implemented `public TextRefining` protocol (e.g. test
    `MockRefiner`) is source-fragile and a default that routes streaming to the one-shot method gives
    a misleading streaming contract. Instead Unit B introduced `public protocol StreamingTextRefining`
    in `LLMRefiners.swift`; `AzureOpenAIRefiner`/`GoogleRefiner` conform to both, and the controller
    (`refine(_:using:onProgress:)`) + composite translator dispatch via `as? StreamingTextRefining`
    with one-shot fallback. Net behavior matches C3's intent. design-034 Decision 2 and C3 updated to
    reflect this as-implemented mechanism.
- New `ProtocolEvent.streamingProgress(sectionId:accumulatedText:)` emitted to the JSONL writer and
  verbose diagnostics, with the existing completion-time `sectionProcessed` left intact (resolved
  open question #4).
- Work partitioned into five file-disjoint units (A config, B transport+refiners, C
  controller+protocol event, D factory+overlay, E docs). The streaming refine surface
  (`StreamingTextRefining`), `CompositeRefineTranslating`'s `onProgress` overload, and the concrete
  refiner bodies all live in `LLMRefiners.swift` (Unit B); `TextRefining` in
  `VoiceAgentProtocolController.swift` (Unit C) is left unchanged and the controller consumes the
  streaming surface via an `as? StreamingTextRefining` cast — keeping the two files disjoint while
  honoring the single shared-contract definition.

Guardrails (non-regressable): focused-input insertion stays ATOMIC on completion (overlay updates are
display-only; `focused_input.ok=true` must hold); push-to-talk wiring is untouched;
`FocusedInputDelivery` is Out-of-Scope.

## Open Design Gaps
- Distribution target is local Swift executable first; app bundle/signing/notarization are required for final UI release planning but not resolved yet.
- UI parity is partially implemented; live macOS permission verification, final visual review, and distribution packaging remain before final drop-in replacement.
