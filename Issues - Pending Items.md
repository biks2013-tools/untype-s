# Issues - Pending Items

## Pending Items

### P0 - macOS UI modernization Phase 6 (visual verification) is the only remaining piece
Plan-016 (`docs/design/plan-016-macos-ui-modernization-proposal.md`) has been fully implemented for Phases 1–5. `swift build` and `swift test` (130/130 passing) confirm there is no regression. The only pending work is human-driven visual verification:
- **Phase 6 — Verification.** Extend `test_scripts/ui-mode-smoke.md` with the visual checks listed in plan-016 §Phase 6 and capture before/after screenshots (idle main, listening main, recording overlay, finalizing overlay, warning overlay, inspector expanded/collapsed, onboarding sheet, compact window). UI screenshots require human execution; the agent cannot drive the GUI.

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
- 2026-05-27: No new runtime dependencies added for configurable prompts. Implementation uses Swift/Foundation file IO and existing provider payload code.
- 2026-05-27: No new runtime dependencies added for composite refine-plus-translate prompts. Implementation reuses the existing Swift/Foundation HTTP and JSON code.

## Completed Items

### 2026-05-27 - Composite refine-plus-translate prompt added

Resolved the LLM latency issue where sections with both `refine` and `translate` active required one refinement request followed by a second translation request. The runtime now provisions and loads three composite prompt files under `~/.tool-agents/untype/prompts/`: a composite system prompt, a composite refinement template, and a composite translation template. CLI and UI runtimes wire a composite processor that reuses the selected Azure OpenAI or Google Gemini provider, asks for JSON with `refined_text` and `translated_text`, records the existing raw/refined/output/language protocol fields, and skips the old sequential path for combined sections. Composite failures remain fail-open and do not trigger a sequential fallback. Added plan/scan artifacts, configuration and function documentation, provider request/parser tests, prompt validation tests, and protocol routing/failure coverage; `swift test` passes (156/156).

### 2026-05-27 - Configurable prompt files added

Resolved the prompt-tuning gap where refinement, translation, and provider transcription context were hardcoded in source. Startup now provisions and reads user-editable prompt files from `~/.tool-agents/untype/prompts/`, covering LLM refinement, LLM translation system behavior, translation user-template construction, Soniox transcription context, ElevenLabs first-chunk previous text, and ElevenLabs realtime keyterms. Follow-up fix: prompt provisioning now happens immediately after STT provider resolution, before API-key validation, so an early missing-key configuration error no longer prevents the prompt folder from being created. The resolver validates required prompts and provider limits before sessions start, and prompt contents remain excluded from diagnostics/logs/state. Added project prompt templates, configuration documentation, technical research, plan/scan artifacts, and regression coverage; `swift test` passes (150/150).

### 2026-05-26 - Push-to-talk release latency logging added

Resolved the diagnostic gap where maintainers could see live release-stage UI messages but could not collect durable timing records for analysis. Added disabled-by-default release latency logging with `--release-latency-log`, `--no-release-latency-log`, `--release-latency-log-path`, `UNTYPE_RELEASE_LATENCY_LOG`, and `UNTYPE_RELEASE_LATENCY_LOG_PATH`. When enabled, release attempts append privacy-safe JSONL records to `~/.tool-agents/untype/release-latency.jsonl` or the configured path, capturing total release-to-focused-input timing from UI release detection, UI-to-runtime scheduling delay, provider finalization, protocol/operator processing, text-source selection, focused-input delivery result metadata, and no-text/failure outcomes without persisting transcript text, processed text, clipboard contents, prompts, provider payloads, secrets, or target application contents. Added configuration and analysis documentation plus regression coverage; `swift test` passes (141/141).

### 2026-05-26 - Quick Close push-to-talk release policy added

Resolved the release-latency issue where Soniox often produced accurate partial text but did not finalize before the runtime timeout, causing users to wait for fallback submission. Added a configurable `Quick Close` policy with `--quick-close`, `--no-quick-close`, and `UNTYPE_QUICK_CLOSE`, plus a non-secret native UI toggle under Push to Talk. When enabled and no final text is already pending, release submits the latest active-turn partial immediately through the existing protocol/refine/translate/clipboard/focused-input pipeline and suppresses late provider callbacks from the ending session. When disabled, the existing finalization wait and timeout fallback behavior remains unchanged.

### 2026-05-26 - macOS packaging script added

Resolved the first packaging automation gap by adding `scripts/package-macos-app.sh` and `packaging/macos/untype.entitlements`. The script builds release SwiftPM products, runs tests by default, creates `untype.app`, compiles a native double-click launcher for UI mode, writes app metadata, supports explicit unsigned local packaging, supports Developer ID signing, supports optional notarization/stapling, and produces zip archives under `.build/deploy/`. Verified help output, fail-fast required arguments, unsigned packaging, generated app contents, launcher Mach-O output, shell syntax, and `swift test` (130/130).

### 2026-05-26 - macOS deployment guide documented

Resolved the deployment-planning documentation gap by adding `docs/design/deployment-guide.md`. The guide documents the current SwiftPM executable status, the manual `.app` bundle layout, required microphone metadata and hardened-runtime entitlement, Developer ID signing, notarization, stapling, Gatekeeper verification, and signed-app smoke testing required before public distribution.

### 2026-05-26 - Push-to-talk overlay theme aligned with main app

Resolved a visual inconsistency where the push-to-talk overlay could read as a separate floating surface from the main native UI. The overlay now follows the main app's appearance setting, renders compact operator indicators using the same amber chip/status-dot language as the Transcript operator controls, and renders its phase as a compact status pill while preserving the non-activating panel and wrap/grow layout behavior. `swift build` and `swift test` (130/130) pass.

### 2026-05-26 - Transcript operator labels collapse by center width

Resolved a responsive layout issue where the Transcript row operator chip labels could wrap when the app window still looked wide overall but the leading monitor sidebar and/or trailing inspector reduced the usable center column. `UntypeOperatorChip` now supports hiding its visible label while preserving accessibility text, and the Transcript action row measures its own central content width before deciding whether to show labels or leave only the status dot plus `R`/`T`/`C`/`I`. `swift build` and `swift test` (130/130) pass.

### 2026-05-26 - Native UI monitor sidebar collapse added
Resolved the restore-path question for collapsing the left Monitor sidebar. The full-size native UI now uses the titlebar brand mark/app-name area as a plain toggle: click it once to hide the leading sidebar, and click the same still-visible titlebar control again to restore it. The sidebar hidden/visible state is persisted as non-secret UI layout state in `~/.tool-agents/untype/ui-state.json`, alongside window dimensions, selected monitor tab, compact mode, and inspector visibility. `swift build` and `swift test` (130/130) pass.

### 2026-05-26 - Native UI titlebar controls repositioned
Resolved a visual layout issue where the full-size native UI's session/action controls were packed into the left titlebar area near the macOS traffic lights. The full-size window now renders those controls in a custom titlebar-height strip anchored to the top-right of the center monitor column, aligned with the traffic-light row and outside the left toolbar area. Existing actions and shortcuts are preserved. `swift build` and `swift test` (130/130) pass. Live screenshot verification remains part of the pending macOS UI visual review.

### 2026-05-26 - macOS UI modernization Phases 3, 4, and 5 implemented
Resolved the remaining design-bundle surfaces from plan-016. Phase 3 refactored `settingsPane` in `Sources/UntypeCore/NativeUntypeUILauncher.swift` to a SwiftUI `Form` with `.formStyle(.grouped)` and seven sections (Session, Provider, Protocol, Operators, Refinement (LLM), Push to talk, Permissions, Credentials). The Permissions section uses `UntypeStatusDot` plus a deep-link button (`x-apple.systempreferences:com.apple.preference.security?Privacy_*`) that opens System Settings when the tone is warn. Phase 4 added a Filter chip row above `eventsPane` backed by a new additive `UntypeUISettings.selectedEventsFilter` field (values: `all/warnings/provider/audio/hotkey/protocol`, default `all`) with full round-trip through `UntypeUISettings.merged`, `normalized`, the persisted `PersistedUISettings` struct, and `settingsFromConfiguration`. History entries now use a 56-pt time/status gutter and a `DisclosureGroup` for turns whose text exceeds 280 characters, with amber/warn accent borders for processed vs. issue records. Phase 5 introduced `UntypeOnboardingView` (presented as `.sheet` on `UntypeRootView` when microphone, accessibility, or credential status is not OK and not skipped in the last 24h; skip flag stored in `UserDefaults` under `untype.onboardingSkippedAt`) and `UntypeMiniView` (440×260 compact-mode layout matching `peripheral.jsx:UnMini`) plus an additive `UntypeUISettings.compactWindow: Bool` field. The AppDelegate now subscribes to `model.$settings` via Combine and resizes the `NSWindow` between mini and full sizes (keeping the title bar anchored at the top edge) without persisting the mini dimensions over the user's saved full-window size. Toolbar gains an inspector toggle (`⌘\`) and a compact-mode toggle (`⌥⌘M`). `swift build` and `swift test` (130/130) pass.

### 2026-05-26 - macOS UI modernization Phases 1 + 2 implemented
Resolved the visual scaffolding gap captured in plan-016. Added a new `Sources/UntypeCore/UntypeDesignSystem.swift` with the design system primitives drawn from `docs/reference/design-bundle-macos-modernization/project/src/shared.jsx` — `UntypeDesignTokens`, `UntypeStatusTone`, `UntypeBrandMark`, `UntypeStatusDot`, `UntypeStatusPill`, `UntypeOperatorChip`, `UntypeRecordButton`, `UntypeWaveformView`, `UntypeKbd`, `UntypeSectionHeader`, `UntypeStatusToneMap`. Refactored `UntypeRootView` in `Sources/UntypeCore/NativeUntypeUILauncher.swift` to a `NavigationSplitView` with a leading sidebar (Transcript/History/Events source list + Status card with mic / accessibility / API key / hotkey rows), a top toolbar (brand mark, status pill cluster, primary `UntypeRecordButton`, refresh icon button, inspector toggle bound to `Cmd+\`), a content pane that switches on `selectedMonitorTab`, and the existing inspector pane (kept intact, Phase 3 will polish it). The transcript pane gained an operator-chip row (R/T/C/I via `UntypeOperatorChip`) and a waveform + dB readout, and `timelineTurnView` was restyled to the design's time-gutter / RAW prefix / amber-border refined-text layout. The push-to-talk overlay (`UntypeOverlayView`) was redesigned to the design's Card variant — phase-tinted status dot, operator chips with amber-fill highlight, accent ring on recording — while keeping the non-activating `NSPanel`, `ignoresMouseEvents = true`, `level = .statusBar`, and the wrap-stable `UntypeOverlayLayout` math untouched. The main window now uses a transparent titlebar with `fullSizeContentView` so the toolbar/sidebar layout reads as a modern macOS utility. `swift build` and `swift test` (130 tests) both pass.

### 2026-05-25 - High CPU and focused-input lag reduced
Resolved a performance issue where active UI sessions could update SwiftUI audio status on every microphone buffer even though the visible audio event log was throttled. Runtime audio activity emission is now throttled with immediate category-change updates, and muted-gate detection no longer compares full audio `Data` buffers. Focused-input auto delivery now tries AX insertion first, then the faster clipboard-preserving paste path, leaving per-character Unicode events as the compatibility fallback for short text only. This addresses the observed CPU usage and browser/editor lag while preserving existing focused-input privacy guarantees. Added regression coverage for audio activity throttling and category-change emission. `swift test` passes.

### 2026-05-25 - Push-to-talk release transcript/history retention fixed
Resolved a UI regression where releasing the talk button could briefly record raw and refined/translated output, then lose it from both Transcript and History when the app automatically started the next warm push-to-talk runtime. The root cause was `startSession(...)` replacing the whole `UntypeUITimelineState` on every runtime start. Runtime starts now clear only stale live partial text, while committed raw and processed turns remain retained until explicit Clear or app termination. Added regression coverage that partial cleanup preserves committed Transcript and History content. `swift test` passes.

### 2026-05-25 - Native UI session conversation history tab added
Resolved a UI observability gap where the current session's conversation history could only be inferred from the Transcript and Events tabs. The native UI now includes a `History` monitor tab derived from the existing in-memory grouped transcript timeline. It shows each retained conversation turn, what the user dictated, recorded refine/translate processed output, and session warning records when present. The selected `History` tab can be restored as non-secret layout state, but conversation-history content remains memory-only and is cleared with the transcript timeline. `swift test` passes.

### 2026-05-25 - Native UI window state persistence added
Resolved the UI preference gap where `untype ui` always opened with the default window size, settings pane visibility, and selected monitor tab. The existing non-secret `ui-state.json` persistence now stores main window width/height, settings-pane hidden/visible state, and selected monitor tab. AppKit restores the saved content size on launch and records resize changes through the window delegate; SwiftUI binds settings visibility and monitor tab selection directly to persisted model state. Tests verify the new layout fields are saved/restored while credential status, permission status, secrets, transcript text, and event-log content remain excluded. `swift test` passes.

### 2026-05-25 - Push-to-talk overlay bottom indicators aligned
Resolved the overlay placement adjustment for protocol and recording indicators. The `R`/`T`/`C`/`I` operator indicators now render in a bottom-left row with their bottom side 5 px above the overlay bottom, and the phase/recording indicator renders at the bottom right on the same vertical row. The transcript region now reserves the bottom indicator row so wrapped transcription text remains above it. `swift test` passes.

Follow-up adjustment: the phase/recording indicator was shifted 20 px left from the overlay right edge while remaining on the same bottom row as the operator indicators. `swift test` passes.

### 2026-05-25 - Push-to-talk overlay wrapping restored
Resolved an overlay regression where the previous fixed-size correction prevented long transcribed text from wrapping and instead constrained the visible transcript to a single tail-truncated line. The overlay layout again measures transcript text against the available overlay text width, the SwiftUI transcript label renders multiline text, and visible panel growth uses the stored bottom-left anchor so additional wrapped lines add space upward without moving the bottom edge. Added regression coverage for wrapped growth, anchored upward expansion, and preserving an expanded visible height when later text is shorter. `swift test` passes.

### 2026-05-25 - Push-to-talk overlay text-driven resizing removed
Resolved the follow-up request to completely remove overlay window resizing based on transcribed text length or growth. The overlay layout no longer measures transcript text height, no longer exposes variable-height frame updates, and the visible overlay update path now leaves the `NSPanel` frame unchanged while transcription text changes. The overlay still opens at its fixed configured size in its bottom-center position and retains the phase label plus operator indicators. `swift test` passes.

Follow-up correction: the fixed-size panel was no longer explicitly reframed, but the hosted SwiftUI overlay content could still grow from transcript text and make the overlay appear to move while transcribing. The hosting view and SwiftUI body are now constrained to the fixed panel size and clipped, transcript text is single-line tail-truncated inside the fixed panel, and repeated visible updates no longer re-order the window. `swift test` passes.

### 2026-05-25 - Push-to-talk overlay downward sliding corrected
Resolved a corrective follow-up where the overlay could appear to slide downward during live transcription updates. The visible update path now applies one stored-anchor frame policy: updates that still fit the current height leave the panel frame unchanged, wrapped text growth reuses the bottom-left anchor captured when the overlay first appeared, and any detected AppKit frame drift is restored to that stored anchor instead of becoming the next position. This preserves the requested behavior: long transcript text wraps inside the stable-width overlay and additional wrapped lines expand the panel upward. `swift test` passes.

### 2026-05-25 - Push-to-talk overlay wraps and grows upward
Resolved an overlay readability gap where long live transcript text could be constrained by a fixed-height panel and fixed line limit. The overlay now wraps long text within a stable panel width, removes the fixed three-line cap, computes the required panel height from the text layout, and anchors the bottom edge so additional wrapped lines grow upward while phase and operator indicators remain visible. `swift test` passes.

Follow-up correction: the overlay frame is no longer reapplied on every text update. If updated speech still fits within the current wrapped line count, the panel is left in place; when the measured height changes, the resize preserves the current bottom-left origin so the new space is added upward rather than shifting the window downward.

Second follow-up correction: the live resize path now stores the overlay's bottom-left anchor when the panel first appears and reuses that same anchor for all visible growth. The panel only increases height while visible; it no longer shrinks or derives its next anchor from a potentially drifted AppKit frame during speech updates.

### 2026-05-25 - Native UI transcript and event export added
Resolved a UI workflow gap where transcript timeline content and event-log diagnostics could be selected manually but not extracted through explicit whole-content actions. The Transcript and Events tabs now expose `Copy` and `Save` controls when content exists. Transcript export includes committed turns, labels, statuses, and live partial text; event export includes the retained bounded event log in chronological order. Copy writes to the macOS pasteboard, Save writes UTF-8 text to a user-selected file, and both actions leave the active session state unchanged. `swift test` passes.

### 2026-05-25 - Warm push-to-talk restart skipped after provider failure
Resolved a UI failure loop where a hotkey-owned push-to-talk session could immediately restart after a transcriber/provider error and hit the same provider failure again. The UI now records the runtime failure, adds a warning that warm restart was skipped, clears the pending warm restart flag, and requires an intentional retry after the provider/account issue is fixed. This specifically prevents repeated loops for fatal provider responses such as Soniox `organization_balance_exhausted`.

### 2026-05-25 - Native UI audio diagnostics and compact monitor controls added
Resolved a UI diagnostics gap where listening could appear active without making it clear whether microphone audio was arriving or whether the STT provider was receiving silence because the push-to-talk gate was closed. The native UI now logs throttled `audio.input` events from existing runtime audio activity snapshots, including raw microphone byte counts, active/silent/muted status, and whether the provider receives microphone audio or silence. Added a collapsible/expandable right settings sidebar to give the monitor more space and reduced push-to-talk overlay transcript text to compact event-style typography. `swift test` passes.

### 2026-05-24 - Push-to-talk overlay flashing loop fixed
Resolved a follow-up issue where the push-to-talk overlay could flash repeatedly while holding the physical hotkey. The attempted physical key-state reconciliation could falsely synthesize release while the key was still held; macOS key-repeat then delivered additional key-down events that restarted push-to-talk, causing repeated early `ui-hotkey-release` cycles and `no text was submitted` warnings. The reconciliation poll was removed, and both Quartz and AppKit hotkey paths now ignore autorepeated key-down events for the configured push-to-talk key. Normal `keyUp`/`flagsChanged` release handling and the explicit press-to-toggle fallback remain.

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
