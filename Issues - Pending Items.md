# Issues - Pending Items

## Pending Items

### P0 - Swift implementation is not yet a drop-in replacement
The project now has a SwiftPM scaffold plus expanded CLI/config compatibility, transcript rendering, voice-agent protocol core primitives, native audio capture, mocked Soniox/ElevenLabs provider adapters, Azure OpenAI/Google LLM refiners, concrete clipboard/focused-input delivery, CLI runtime startup/shutdown wiring, and a native SwiftUI/AppKit UI mode with grouped transcript timeline, transient macOS permission status, warm push-to-talk session recycling, and operator-aware overlay. Live smoke verification, final visual review, and distribution decisions must still be completed before replacing the TypeScript command.

### P0 - `untype ui` parity is partially implemented but not final
The native UI now opens, starts/stops the shared Swift runtime, persists non-secret UI settings, shows credential status without secrets, shows transient Microphone and Accessibility trust status without persisting it, supports a clearable grouped transcript timeline, locks session-shaping controls while keeping protocol operator switches live during active sessions, supports Quartz event-tap push-to-talk monitoring with AppKit fallback, maintains a warm hotkey-owned session with silence gating and idle recycling, and displays a non-activating overlay with operator indicators. Remaining parity gaps: full live macOS Accessibility/Input Monitoring verification, final visual review, and signed/notarized app distribution planning.

### P1 - Distribution target is unresolved
The first milestone assumes a local Swift executable named `untype`. Signed/notarized app bundle and Homebrew-style distribution remain unresolved.

### P1 - Live provider and macOS permission tests are manual gaps
The source project has unit tests but no live provider or UI automation harness. The Swift replacement has documented smoke procedures for microphone, Soniox, ElevenLabs, focused input, and native UI mode; manual execution remains pending.

## Dependency Vetting Log
- 2026-05-23: No new runtime dependencies added. Initial SwiftPM scaffold uses only Apple/Swift standard libraries and platform frameworks.

## Completed Items

### 2026-05-24 - Push-to-talk release now falls back to latest partial when Soniox never finalizes
Resolved the live UI behavior where Soniox produced accurate `transcript.partial` text after release but never delivered a final transcript before the runtime timeout, leaving no monitor output, clipboard copy, or focused-input insertion. The runtime now keeps the latest visible partial transcript in memory for the active session and, after provider finalization times out with no final text, submits that partial through the normal protocol/refinement/clipboard/input pipeline with an explicit warning. If no partial exists, the no-text warning remains. Added regression coverage for release fallback submission. `swift test` passes.

Follow-up cleanup: late provider partial callbacks are now suppressed after release submission commits, preventing stale Soniox partial lines from appearing after `transcript.final` or around `transcript.processed`. Added regression coverage for late partial suppression after fallback submission. `swift test` passes.

Second follow-up cleanup: UI runtime diagnostics were split from protocol-controller diagnostics so runtime warnings such as the push-to-talk fallback message are not emitted twice into the transcript timeline. Protocol/operator diagnostics still remain visible through the UI event sink. `swift test` passes.

### 2026-05-24 - Soniox combined finalized frames now produce final transcript
Resolved the follow-up push-to-talk release failure shown by live UI diagnostics: Soniox returned transcript text after release, but the Swift parser treated a same-frame `finalized`/`endpoint` marker before reading the frame's `tokens`, so the text remained visible only as `transcript.partial` and the runtime timed out with no submitted text. The Soniox adapter now processes tokens first, then flushes on semantic finalization markers, preserving combined finalization payloads. Added regression coverage for a `type:"finalized"` frame that carries final tokens. `swift test` passes.

### 2026-05-24 - Push-to-talk release no-output diagnostics added
Resolved a reported UI issue where releasing the push-to-talk button could appear to do nothing when the provider did not return finalized transcript text before submission, or when refine/translate/clipboard delivery failed without verbose diagnostics. The runtime now emits privacy-safe release-stage diagnostics, warns when no finalized transcript arrives before the timeout, and UI sessions surface release/operator warnings in the transcript timeline. The protocol controller now exposes UI operator attempt/failure diagnostics for refine, translate, clipboard, and focused input while keeping failures fail-open. Added regression tests for no-final release warnings and non-verbose clipboard failure reporting. `swift test` passes.

### 2026-05-24 - Push-to-talk release now finalizes and submits fresh turns
Resolved a push-to-talk behavior issue where repeated press/release cycles could keep extending the previous provider partial buffer, and release could submit before the STT provider had returned final text. That left only `transcript.partial` entries in the monitor, with no processed/refined output, no clipboard copy, and no focused-input delivery. Runtime submission now waits briefly for provider final text when needed, submits the pending section before protocol shutdown, and UI push-to-talk release stops the current provider session and restarts a fresh warm session for the next press. New regression tests cover delayed provider final text during `submitPending()` and during `stop(submitPending: true)`. `swift test` passes.

### 2026-05-24 - Settings form aligned and glass-styled
Resolved a UI polish issue where the right-side settings form used default grouped panels and uneven control alignment. The settings pane now uses material-backed glass sections with fixed-width label/control rows for status values, pickers, text fields, steppers, toggles, and push-to-talk actions. Existing bindings, active-session disabled states, and runtime behavior are unchanged. Verified that a fresh UI instance still reaches `Session: listening`; `swift test` passes.

### 2026-05-24 - Native UI reaches listening state
Resolved a UI startup defect where `Session: listening` never appeared even though the CLI microphone/provider path worked. The executable had been entering the native AppKit run loop through the async command path, wrapping blocking `NSApplication.run()` in main-actor/main-queue scheduling that starved Swift UI startup tasks. The executable now launches `untype ui` directly on the initial main thread before the async command path, and UI runtime startup/callback work uses background tasks plus AppKit main-queue dispatch. Live UI automation verified the window reaches `Session: listening`, reports microphone and Soniox connection diagnostics, opens push-to-talk recording, displays transcript text, and returns to warm muted mode on release. `swift test` passes.

### 2026-05-24 - Push-to-talk muted audio status clarified
Resolved a UI diagnostic issue where a warm push-to-talk session could look like the app was not hearing speech even though the microphone path was receiving PCM and the closed audio gate was intentionally sending silence to the provider. The saved UI state had push-to-talk enabled, so the launch state is a warm session until `Control+\`` or the UI push-to-talk button opens the gate. The UI now labels closed-gate audio as `muted by push-to-talk <n>%`, and the smoke test/design docs distinguish that state from silent input or waiting capture.

### 2026-05-24 - UI microphone capture evidence added
Resolved a UI observability issue where `Start Listening` could be running without any visible evidence until the STT provider returned transcript text. The runtime now starts microphone capture before waiting for the realtime STT WebSocket to finish connecting, emits privacy-safe audio activity snapshots from microphone PCM chunks, and displays `Audio: waiting`, `silent`, `active`, or a push-to-talk muted state with a peak percentage in the header and System panel. Startup diagnostics also show the microphone and provider connection stages separately. Added runtime coverage for normal and gate-muted audio activity and updated the UI smoke procedure.

### 2026-05-24 - Stop Warm Session fixed during startup
Resolved a UI issue where `Stop Warm Session` could do nothing while the UI showed `Session: starting` and `Capture: warm`. The main session button now routes hotkey-owned sessions through the warm-session stop path, startup tasks are cancelled and reset to idle if no runtime has been assigned yet, and the runtime/provider stop paths honor stops issued during provider startup so a stopped warm session cannot race back into listening. Verified with `swift test`.

### 2026-05-24 - UI hotkey overlay visibility issue addressed
Resolved a reported issue where pressing the configured UI hotkey did not open the push-to-talk overlay. Strengthened the overlay `NSPanel` to status-bar window level, positioned it on the screen containing the pointer, added privacy-safe event-source diagnostics for Quartz/local/global/UI-button hotkey paths, removed invalid tap-disabled values from the Quartz event-tap mask, and added a `Press Hotkey` / `Release Hotkey` UI fallback that uses the same audio-gate and overlay path when macOS blocks keyboard hook delivery. Updated the UI smoke test with the fallback and diagnostic checks.

### 2026-05-24 - Native UI active-session editability aligned with source behavior
Resolved a UI parity gap where the Swift UI allowed provider/model/language/protocol/LLM/hotkey settings to change while a session was listening, warmed, or recording. Added a testable UI control-availability policy, disabled session-shaping controls during active sessions, kept refine/translate/clipboard/focused-input switches live, and changed the main session button labels to distinguish listening, warm, and recording stop actions. Added regression coverage for the editability policy.

### 2026-05-24 - Native UI startup now derives settings from the CLI config chain
Resolved a UI parity gap where `untype ui` initialized from hardcoded Swift defaults instead of the same configuration chain used by the CLI. Added a UI settings load path that converts persisted non-secret UI settings to CLI-equivalent arguments, applies persisted protocol settings, refreshes credential and transient macOS permission status without exposing secrets, and uses inspection-only LLM validation so missing LLM secrets are reported in the UI without blocking settings display. Added regression coverage for env-derived UI startup state and strict LLM fallback diagnostics.

### 2026-05-23 - Native UI permission status surfaced without persistence
Resolved a UI smoke-test gap where operators had to infer macOS permission state from later runtime failures. Added transient Microphone authorization and Accessibility trust status to the native UI System panel, refreshed it alongside credential status, and kept the values out of `~/.tool-agents/untype/ui-state.json`. Added injected Swift coverage for permission labels and persistence privacy, then updated the UI smoke procedure and verification report.

### 2026-05-23 - Native UI transcript timeline and overlay operator indicators added
Resolved a UI parity gap where the Swift UI displayed only the latest transcript string and the overlay did not expose the source-style protocol operator state. Added a testable Swift timeline reducer that separates live partials from committed turns, groups raw dictated text and processed output, supports session-error bubbles, and clears only visible UI history. Wired the native SwiftUI window to the grouped timeline with a Clear action and added compact `R`/`T`/`C`/`I` indicators to the push-to-talk overlay. Updated the UI smoke test to verify transcript grouping, clearing behavior, and overlay operator indicators.

### 2026-05-23 - CLI voice command responsiveness fixed
Resolved a CLI-mode issue where spoken protocol commands could appear not to work while the STT provider held `command status`, `command send`, or `command cancel` in partial output. The runtime now detects actionable protocol markers in partial transcripts and asks the active provider to commit, while keeping final transcripts as the only execution path for protocol actions. Repeated identical partial snapshots are deduplicated, and regression tests cover both actionable command partials and incomplete `command` partials.

### 2026-05-23 - Standard macOS UI shortcuts restored
Resolved a UI-mode issue where standard shortcuts such as `Command+W` and `Command+Q` did not work because the SwiftUI/AppKit process did not install an application menu. The UI launcher now creates a native AppKit menu with app, file, and edit commands so close, quit, hide, copy, paste, and select-all route through normal macOS menu handling.

### 2026-05-23 - Quartz push-to-talk event tap implemented
Added a primary `CGEvent` tap for Swift UI push-to-talk so the configured accelerator can be detected system-wide and suppressed before reaching the foreground app. The UI retains AppKit local/global monitors as a fallback, shows fallback status text when the tap cannot start, supports press-to-toggle behavior if release detection is blocked, and continues routing `R`/`T`/`C`/`I` operator toggles while recording. Hotkey normalization now accepts source-style aliases such as `Backquote`/`Grave` and dash-separated accelerators; automated tests cover canonical alias persistence and ambiguous modifier rejection.

### 2026-05-23 - Minimum macOS target resolved
Confirmed and documented macOS 14 as the minimum supported platform. `Package.swift` declares `.macOS(.v14)`, README lists macOS 14 or newer as a requirement, and project design now records the target alongside the AVFoundation permission API rationale.

### 2026-05-23 - Replacement verification report added
Created `docs/reference/verification-report-swift-drop-in-replacement.md` to record the current replacement verdict. The report states that automated verification passes but the Swift implementation is not yet approved as a full drop-in replacement until live macOS/provider smoke tests, final UI polish, and distribution planning are complete.

### 2026-05-23 - Config parser edge coverage and legacy migration guard completed
Added source-compatible Swift coverage for `.env` comments, `export` prefixes, quoted values, inline comments, blank lines, and whitespace-only fallthrough to lower-priority sources. Added the source no-fallback migration guard that raises a typed `missing_configuration` hint when `~/.tool-agents/mic-tool-ts/` exists but `~/.tool-agents/untype/` does not, and documented the compatibility checklist update.

### 2026-05-23 - Push-to-talk warm session recycling implemented
Added source-style warm push-to-talk behavior to the Swift UI/runtime path. The runtime now accepts an audio gate and forwards same-length silence while the hotkey gate is closed, preserving a live provider session without sending captured speech while idle. The UI starts a hotkey-owned warm session when push-to-talk is enabled, opens the gate on press, closes it on release, submits pending text without stopping the session, and schedules a five-minute idle recycle of the warm session. Added regression coverage for closed-gate silence forwarding and updated the UI smoke procedure to verify warm capture state and release behavior.

### 2026-05-23 - Native UI shell and push-to-talk overlay implemented
Replaced the `untype ui` placeholder with a SwiftUI/AppKit monitoring UI. Added non-secret UI settings persistence at `~/.tool-agents/untype/ui-state.json`, credential status inspection without secret values, typed UI transcript/session/protocol/diagnostic event routing through the shared Swift runtime, manual start/stop controls, AppKit local/global push-to-talk monitoring, `R`/`T`/`C`/`I` operator hotkeys while recording, and a display-only non-activating overlay that clears text on hide. Added focused tests for UI command dispatch, launcher error mapping, UI session arguments, non-secret persistence, and credential status refresh. Documented live UI smoke verification in `test_scripts/ui-mode-smoke.md`; manual execution remains pending.

### 2026-05-23 - macOS clipboard and focused-input delivery implemented
Added concrete Swift macOS delivery for protocol clipboard and focused-input operators. Clipboard delivery writes to `NSPasteboard.general`; focused-input delivery launches the sibling `untype-input-helper` executable with control arguments only and streams processed text over stdin. The helper implements `diagnose` plus `send --method auto|ax-value|unicode-events|paste-keycode`, returns one JSON result line, maps expected failures to exit code `2`, attempts AX insertion, Unicode events, and clipboard-preserving Command-V fallback, and surfaces Accessibility denial as `accessibility_not_trusted`. Added focused tests for stdin-only delivery, helper result parsing, command validation, expected failure handling, and injected clipboard writing. Documented live focused-input smoke verification in `test_scripts/focused-input-smoke.md`; manual execution remains pending.

### 2026-05-23 - LLM refiners implemented and wired into runtime
Implemented direct REST Swift refiners for Azure OpenAI and Google Gemini behind a mockable HTTP client, including request construction, response trimming, auth/server/network/timeout/shape error mapping, dispose cancellation, disabled-refinement nil construction, and accepted stub failures for the six unimplemented provider names. Wired concrete refiner and translator instances into `UntypeRuntimeFactory` so protocol refine/translate operators use the configured LLM provider when enabled.

### 2026-05-23 - CLI/config compatibility expanded
Implemented the documented Swift config surface for STT provider selection, provider-specific defaults, language/sample-rate validation, endpoint detection, output mode, protocol defaults, LLM startup validation, and API-key expiry warnings. Added focused Swift tests for config precedence, provider defaults, invalid values, protocol output requirements, LLM validation, expiry warnings, and unknown flags.

### 2026-05-23 - Transcript renderer core implemented
Implemented the Swift transcript renderer for `overwrite`, `append`, and `final-only` modes, including non-TTY overwrite downgrade, duplicate partial suppression, wrapped-row cleanup, marker-token filtering, refined output rendering, and dispose cleanup. Added renderer tests for the source-compatible byte sequences and mode behavior.

### 2026-05-23 - Voice-agent protocol core implemented
Implemented Swift marker matching, protocol operator state, section lifecycle, shutdown drain behavior, source-named JSONL events with monotonic sequence numbers, and non-secret protocol settings persistence. Added focused tests for marker normalization, command stripping, Greek guard aliases across final segments, stable section IDs, JSONL output, and persisted protocol settings.

### 2026-05-23 - Voice-agent protocol controller implemented
Implemented the Swift protocol controller for source-compatible partial/final transcript routing across `dictation`, `agent-protocol`, and `hybrid` modes; status rendering; JSONL session events; raw/refine/translate/render/clipboard/input section processing order; fail-open missing-LLM and input warnings; operator toggles; and latest settings snapshots. Added focused controller tests for JSONL-only agent mode, visible status rendering, processing order, warnings, and snapshot updates.

### 2026-05-23 - Provider-neutral session runtime implemented
Implemented mockable Swift session orchestration for audio/transcriber start-stop, PCM forwarding, STT partial/final forwarding into the protocol controller, push-to-talk pending submission, shutdown protocol settings persistence, typed ready/state/diagnostic events, and recorded async failures. Added focused runtime tests for start/stop routing, pending submission, and audio-push failure shutdown.

### 2026-05-23 - Soniox WebSocket frame adapter partially implemented
Implemented the Swift Soniox transcriber behind a mockable WebSocket client boundary, including startup config JSON, binary audio forwarding, finalize/finish frames, result-token parsing, marker filtering, repeated-final-prefix merge behavior, endpoint/finalized/finished final commits, and typed Soniox auth/network/protocol error mapping. Added mocked transport tests for the frame contract and result handling. Live Soniox smoke testing remains pending.

### 2026-05-23 - Soniox URLSession receive loop implemented
Added a concrete `URLSessionWebSocketTask` transport for the Soniox transcriber, including async receive-loop routing for text/data frames, close handling, and receive-failure mapping to `soniox_network`. Added Soniox tests for live-transport handler routing and endpoint validation. Documented the live Soniox smoke procedure in `test_scripts/soniox-live-smoke.md`; manual execution remains pending.

### 2026-05-23 - AVFoundation audio source implemented
Added an AVFoundation-backed runtime audio source with microphone permission preflight, `AVAudioEngine` input tap startup/stop, mono PCM16 conversion at the configured sample rate, and typed `microphone_permission` / `microphone_capture` failures. Added synthetic converter tests and documented the live microphone smoke procedure in `test_scripts/microphone-live-smoke.md`; live permission/capture verification remains pending.

### 2026-05-23 - ElevenLabs WebSocket frame adapter partially implemented
Implemented the Swift ElevenLabs transcriber behind the shared mockable WebSocket client boundary, including realtime URL/query construction, `xi-api-key` request headers, base64 JSON audio chunk forwarding, manual/VAD commit selection, commit frames, partial/final transcript routing, timestamped committed transcript handling, endpoint validation, and typed ElevenLabs auth/network/protocol error mapping. Added mocked transport tests for the frame contract and result handling. Documented the live ElevenLabs smoke procedure in `test_scripts/elevenlabs-live-smoke.md`; manual execution remains pending.

### 2026-05-23 - CLI runtime factory and signal shutdown implemented
Implemented the async CLI runtime path: configuration resolution now builds a live `TranscriptionSessionRuntime`, loads and applies persisted non-secret protocol settings, selects AVFoundation audio plus Soniox or ElevenLabs STT, creates renderer/protocol JSONL outputs, waits for `SIGINT` or `SIGTERM`, submits pending output during shutdown, persists latest settings, and maps recorded runtime failures back to typed exit codes. Added command tests for runtime start/wait/stop and recorded-failure exit mapping. Live microphone/provider smoke verification remains pending.

### 2026-05-23 - Request refined and source study initialized
Created refined request, investigation, technical research files, source scan, source study, compatibility checklist, project design, functional requirements, and implementation plan for the Swift replacement.

### 2026-05-23 - Soniox direct WebSocket research completed
Received `docs/research/soniox-websocket-swift.md`, confirming the Swift adapter should use one initial JSON config frame, binary PCM frames, JSON finalize control, and source-compatible marker filtering/final-prefix merge behavior.
