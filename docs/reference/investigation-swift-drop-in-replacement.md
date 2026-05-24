# Investigation: Swift Drop-In Replacement for untype

## Executive Summary
The recommended implementation approach is a SwiftPM-first, multi-target native Swift replacement that preserves the `untype` command contract while separating the pure behavior model from macOS integration and provider adapters. The replacement should be developed in phases, but the project should not be declared a drop-in replacement until both the CLI/protocol path and `untype ui` parity are complete. The strongest path is: SwiftPM package with an executable named `untype`; project-owned CLI/config compatibility layer; native AVFoundation/CoreAudio microphone capture; direct WebSocket provider adapters over Foundation `URLSessionWebSocketTask`; REST-based Azure OpenAI and Google refiners with the six existing LLM provider stubs preserved; and a SwiftUI/AppKit UI for the monitoring window, menu/controls, push-to-talk hotkey, and non-activating overlay. Confidence is medium-high for the CLI/provider/protocol path and medium for native UI/hotkey parity because macOS permission and system-wide key-release behavior need deeper technical validation.

## Context
- **What was investigated**: implementation approaches for replacing the TypeScript/Node/Electron `untype` project at `~/aiwork/coding-platform/untype` with a Swift implementation under `~/aiwork/coding-platform/untype-s`.
- **Why**: the refined request requires a Swift drop-in replacement that preserves public command behavior, configuration, realtime STT providers, rendering, voice-agent protocol, macOS integrations, UI mode, tests, and autonomous work-package handoffs.
- **Refined request**: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-swift-drop-in-replacement.md`
- **Target report path**: `~/aiwork/coding-platform/untype-s/docs/reference/investigation-swift-drop-in-replacement.md`
- **Source-of-truth project**: `~/aiwork/coding-platform/untype`

Key source findings:
- The source package exposes `untype` as the installed binary, version `0.1.0`, and uses scripts for build, test, and audit in `package.json`.
- The CLI command supports default dictation mode plus `untype ui`, and the source README documents the direct OS command `untype` as the supported user invocation.
- The configuration contract is strict: CLI flag > current working directory `.env` > `~/.tool-agents/untype/.env` > shell environment, with missing required settings raising typed errors rather than hidden fallback values.
- The active source STT providers are Soniox and ElevenLabs. Soniox is implemented through `@soniox/node`; ElevenLabs is implemented directly over a WebSocket.
- The source LLM strategy fully implements `azure-openai` and `google`, while accepting six additional standard provider names as explicit not-yet-implemented stubs.
- The source UI is not cosmetic only. It owns monitoring/configuration, credential status without secret exposure, typed session events, push-to-talk warm sessions, system-wide hotkey behavior, runtime protocol toggles, and a display-only overlay.
- Existing source tests cover config, rendering, provider adapters, LLM factories/refiners, protocol state, UI settings, hotkeys, and UI bridge behavior.

Key constraints driving the recommendation:
- Drop-in replacement means behavior parity, not just a Swift transcription loop.
- `untype ui` is part of the public command surface.
- macOS is the primary target, and native macOS permission handling is part of the contract.
- The active project instructions prohibit undocumented fallback config values.
- Runtime/build dependencies must be vetted before adoption.
- Implementation must be decomposed into autonomous, handoff-friendly work packages.

## Options Identified

### Option 1: SwiftPM Native Multi-Target Replacement With Release-Gated UI Parity
- **Description**: Use Swift Package Manager as the source-of-truth build structure. Create an executable product named `untype` and split behavior into library targets such as `UntypeCore`, `UntypeCLI`, `UntypeConfig`, `UntypeAudio`, `UntypeProviders`, `UntypeProtocol`, `UntypeLLM`, `UntypeMacOS`, and `UntypeUI`. Implement CLI/protocol/provider parity first, scaffold the UI entry early, then complete SwiftUI/AppKit UI parity before the replacement is considered drop-in.
- **Strengths**: Aligns with the refined request's SwiftPM expectation; supports `swift build` and `swift test`; isolates pure behavior from macOS integration; keeps the command identity stable; avoids Node/Electron runtime dependency; enables focused work packages and test ownership.
- **Weaknesses**: More engineering work than a wrapper or partial CLI port; native macOS UI/hotkey behavior requires careful permission testing; SwiftPM does not by itself solve signed/notarized `.app` distribution if that becomes required.
- **Effort/Complexity**: High.
- **Risk**: Medium.
- **Best suited when**: the goal is an actual Swift-native drop-in replacement with long-term maintainability and a clean path to native macOS integration.

### Option 2: SwiftPM CLI/Core Replacement With TypeScript/Electron UI Retained Temporarily
- **Description**: Port the CLI, config, providers, renderer, protocol, and LLM path to Swift, but continue launching the existing Electron UI for `untype ui` until a later native UI project replaces it.
- **Strengths**: Fastest path to replace the core transcription and protocol pipeline; reduces immediate risk around SwiftUI/AppKit parity; keeps the existing UI available during migration.
- **Weaknesses**: Not a true Swift drop-in replacement; keeps Node/Electron packaging, dependency, and IPC surface alive; complicates config/state ownership between Swift and TypeScript; violates the request's intent if presented as final.
- **Effort/Complexity**: Medium.
- **Risk**: Medium-high as a final approach, low-medium as a temporary migration bridge.
- **Best suited when**: the user explicitly approves a transitional bridge and accepts that the result is not yet the final replacement.

### Option 3: Native macOS App Bundle First, CLI as Thin Launcher
- **Description**: Build a native SwiftUI/AppKit macOS app as the primary product, with the `untype` command acting mostly as a launcher/control shim for the app and UI-owned session runtime.
- **Strengths**: Strongest fit for native UI, app permissions, menu bar, overlay windows, signing, and future distribution; microphone and Accessibility/Input Monitoring prompts are more predictable for an app bundle than for an unbundled CLI.
- **Weaknesses**: Weaker fit for pipe-safe CLI parity, stdout/stderr semantics, shell exit-code contract, and CI-style CLI testing; risks making the CLI feel like a secondary compatibility layer; may require Xcode/app-bundle packaging earlier than necessary.
- **Effort/Complexity**: High.
- **Risk**: Medium-high for CLI parity.
- **Best suited when**: product distribution and polished macOS app behavior are more important than command-line parity in the first milestone.

### Option 4: SwiftPM Monolith With Third-Party CLI/WebSocket Abstractions
- **Description**: Build a smaller SwiftPM executable using external packages for most structure, for example Swift Argument Parser for CLI parsing and WebSocketKit/SwiftNIO for provider WebSockets, with less internal target separation.
- **Strengths**: Faster initial coding; ArgumentParser is a maintained, type-safe Swift command-line framework; SwiftNIO/WebSocketKit provide lower-level networking control if Foundation WebSockets prove insufficient.
- **Weaknesses**: More dependency vetting; generated help/error behavior can drift from the TypeScript CLI contract; monolithic structure makes autonomous work-package decomposition harder; networking dependencies are unnecessary unless Foundation `URLSessionWebSocketTask` proves inadequate.
- **Effort/Complexity**: Medium.
- **Risk**: Medium.
- **Best suited when**: speed of initial prototype matters more than minimizing dependencies and preserving exact compatibility boundaries.

## Focus Decision Analysis

### SwiftPM Structure for CLI and Native macOS Support
Recommended structure:
- `Package.swift`
- `Sources/untype/main.swift`: thin executable entry that dispatches `untype` CLI mode vs `untype ui`.
- `Sources/UntypeCore`: shared types, errors, event models, exit codes.
- `Sources/UntypeConfig`: env-chain loader, parsers, config schema, help/version contract.
- `Sources/UntypeCLI`: command dispatch, stdout/stderr rendering, signal handling, process exit mapping.
- `Sources/UntypeAudio`: audio source protocol and test fakes.
- `Sources/UntypeMacOS`: AVFoundation microphone capture, focused input, permission diagnostics, hotkey/event tap integration.
- `Sources/UntypeProviders`: Soniox and ElevenLabs adapters behind a provider-neutral transcriber protocol.
- `Sources/UntypeProtocol`: marker matching, state machine, JSONL writer, settings persistence.
- `Sources/UntypeLLM`: Azure OpenAI, Google, and provider stubs.
- `Sources/UntypeUI`: SwiftUI/AppKit UI application module callable by `untype ui`.
- `Tests/*Tests`: unit and integration tests grouped by module.

SwiftPM is the right source-of-truth structure because it is Swift's built-in package/build/test tool and supports command-line packages, dependencies, and tests through `swift build` and `swift test` [R1, R16]. A separate Xcode project or packaging script may still be needed later if signed/notarized `.app` distribution is required, but that should be a packaging phase rather than the core implementation structure.

### CLI Parity and Compatibility Strategy
Recommended strategy:
- Treat the source README, `docs/design/configuration-guide.md`, `docs/design/project-functions.md`, source tests, and `src/config.ts` as the compatibility contract.
- Build a project-owned CLI/config schema table that defines every flag, env alias, default, required condition, validation rule, help text, and exit code.
- Prefer a small custom parser/dispatcher for `untype`, `untype --help`, `untype --version`, and `untype ui` unless a later technical spike proves Swift Argument Parser can reproduce the required stream/exit behavior without compatibility compromises.
- Generate help text from the same schema table used by tests so adding a flag cannot silently skip documentation.
- Build snapshot/smoke compatibility tests that compare the Swift command against source-project expectations for help, version, missing config, invalid config, pipe-safe output, JSONL mode, and signal shutdown behavior.

Swift Argument Parser remains a viable fallback because it is an official Swift package for type-safe command-line tools with generated help and validation support [R2, R3]. The reason not to make it the default recommendation is not quality; it is that this project has a strict inherited CLI contract, and a project-owned parser gives full control over stdout/stderr separation, Commander-like help wording, env alias documentation, sentinel help/version behavior, and deterministic exit-code mapping.

### Native Audio Capture Strategy on macOS
Recommended strategy:
- Replace `sox` with native AVFoundation/AVFAudio capture in Swift.
- Use `AVAudioEngine` input node taps to capture audio buffers and `AVAudioConverter` or explicit PCM conversion to produce mono `pcm_s16le` at the configured sample rate.
- Check/request microphone authorization explicitly before starting capture and map denial/unavailable states to the existing typed error classes.
- Keep the audio source behind an `AudioSource` protocol with fake and fixture-backed sources for tests.
- Do not keep `sox` as a silent fallback. If a temporary `sox` backend is needed for validation, it should be an explicit development-only backend or documented migration bridge, not part of the production default.

Apple documents `AVAudioEngine` as the audio graph API, `installTap` as the mechanism to record/observe an audio node's output, and macOS microphone authorization as requiring explicit user permission for capture devices [R4, R5, R12]. Native capture removes the external `sox` prerequisite and gives the Swift replacement direct control over sample rate conversion, permission diagnostics, lifecycle, and test seams.

Main uncertainty: unbundled command-line tools and bundled app binaries may surface different macOS microphone permission identities. This must be researched and smoke-tested before implementation locks the packaging strategy.

### WebSocket/Provider Implementation Strategy for Soniox and ElevenLabs
Recommended strategy:
- Implement both providers directly over WebSocket rather than relying on unavailable or language-specific SDKs.
- Use `URLSessionWebSocketTask` first because it is native Foundation, supports WebSocket tasks, and avoids extra network dependencies [R6].
- Define a provider-neutral `RealtimeTranscriber` protocol with events for partials, finals, warnings, commit/finalize, graceful stop, and typed errors.
- Keep Soniox and ElevenLabs adapters completely separate below that protocol because their frame formats and finality semantics differ.
- Add a mock WebSocket transport protocol so unit tests can inject provider frames without live network calls.
- Escalate to SwiftNIO/WebSocketKit only if Foundation WebSockets cannot satisfy binary audio frame streaming, close semantics, ping/keepalive, or backpressure needs in provider tests.

Soniox documents a realtime WebSocket API for live transcription and translation over a persistent WebSocket connection [R7]. ElevenLabs documents a realtime speech-to-text WebSocket API with `input_audio_chunk` messages, partial/committed transcript events, and manual or VAD commit strategies [R8]. Those public protocols make direct Swift adapters feasible and preferable to wrapping the TypeScript SDK.

Provider-specific implementation notes:
- **Soniox**: reproduce source behavior around `pcm_s16le`, sample rate, `language_hints` vs language identification, endpoint detection, `<end>`/`<fin>` filtering, repeated finalized prefix merging, manual finalization/commit, finish timeout, auth/network/protocol error mapping.
- **ElevenLabs**: reproduce source behavior around `model_id`, `audio_format=pcm_<sampleRate>`, `sample_rate`, `commit_strategy=vad|manual`, `language_code`, base64 audio chunks, empty commit chunk, `partial_transcript`, `committed_transcript`, and close/error mapping.

### LLM Provider Strategy
Recommended strategy:
- Preserve the source LLM provider surface exactly in the first Swift replacement.
- Fully implement `azure-openai` and `google` because the TypeScript source already implements those providers.
- Preserve the six accepted-but-not-implemented stubs: `openai`, `anthropic`, `azure-ai-inference`, `ollama`, `litellm`, and `openai-compat`.
- Use REST calls through `URLSession` rather than provider SDKs for the first implementation to avoid unnecessary dependencies and keep configuration/error mapping explicit.
- Keep startup validation fatal for required LLM configuration and runtime refinement fail-open, matching the source contract.

Azure OpenAI and Google Gemini both expose HTTP APIs suitable for direct REST integration [R17, R18]. OpenAI and Anthropic also expose HTTP APIs if the project later decides to turn stubs into full providers [R19, R20]. The recommended first pass is parity, not expansion: implementing all eight providers would increase scope and test burden while changing the source project's intentionally stubbed behavior.

### UI Parity Approach for `untype ui`
Recommended strategy:
- Use a phased UI implementation internally, but treat full UI parity as a release gate for the final drop-in claim.
- In the first CLI/provider milestone, `untype ui` may be present only as a clearly documented non-drop-in milestone gap unless the user explicitly approves that temporary state.
- Build the final UI with SwiftUI for the settings, monitor, protocol controls, timeline, and state rendering; use AppKit for macOS-specific windowing, non-activating overlay behavior, menu integration, event taps, and process/application lifecycle.
- Prefer a normal SwiftUI/AppKit window for the monitoring/configuration UI, plus AppKit `NSPanel`/non-activating panel for the overlay.
- Consider `MenuBarExtra` as an optional enhancement for a persistent menu-bar control, not as the primary replacement for `untype ui` unless the user chooses a menu-bar-first product direction.

Apple positions SwiftUI as the declarative UI framework for app structure and views, provides `MenuBarExtra` for persistent menu-bar controls, and AppKit exposes non-activating panel behavior through `NSPanel`/window style masks [R9, R10, R11]. The source UI also needs system-wide event observation and release handling. Apple documents global event monitoring through `NSEvent`, while keyboard event taps and Accessibility trust checks require lower-level macOS APIs [R12, R13, R14]. That points to a mixed SwiftUI/AppKit implementation rather than pure SwiftUI.

UI parity should include:
- settings inspector with resolved provider/model/language/protocol/credential status and no secret values;
- start/stop/manual listening;
- push-to-talk warm session with silence gating;
- system-wide hotkey press/release, fallback toggle behavior, and secondary `R/T/C/I` operator toggles;
- typed event rendering rather than terminal-output parsing;
- non-secret `ui-state.json` persistence;
- overlay window that does not steal focus and does not persist transcript text;
- accessibility/input-monitoring warnings and focused-input permission diagnostics.

### Test Strategy
Recommended strategy:
- Use `swift test` as the single automated test entry point.
- Prefer pure module tests for config parsing, env-chain precedence, parser errors, renderer behavior, marker matching, state machine, settings persistence, JSONL events, provider frame mapping, LLM request/response mapping, and typed errors.
- Add process-level CLI tests that launch `.build/debug/untype` with controlled env and temp directories to verify stdout/stderr separation and exit codes.
- Add mocked transport tests for Soniox and ElevenLabs; live provider tests should be opt-in and documented.
- Add macOS-specific smoke scripts under `test_scripts/` for microphone permission, real provider sessions, focused input, hotkey, overlay, and UI mode.
- Use fixtures derived from source TypeScript tests where possible to preserve behavior.

Swift Testing integrates with SwiftPM testing workflows, and `swift test` supports Swift Testing and XCTest execution controls [R15, R16]. The investigation recommends `swift test` as the stable command regardless of whether individual tests use Swift Testing, XCTest, or both. For maximum compatibility with command process tests and macOS integration assertions, the implementation plan should decide whether to standardize on XCTest, Swift Testing, or a small mix.

### Autonomous-Agent Work-Package Decomposition
Recommended work packages:
1. **Source Contract Extraction**: produce a compatibility checklist from README, config guide, project functions, source tests, and key modules.
2. **SwiftPM Skeleton and Build Contract**: create package targets, executable, version/help placeholders, test harness, and initial docs.
3. **CLI and Configuration Parity**: implement schema, env chain, typed parsers, errors, help/version, config source reporting, and expiry warnings.
4. **Core Session/Event Model**: implement session lifecycle, typed events, signal/shutdown model, stdout/stderr routing, renderer, and protocol interfaces.
5. **Protocol State Machine and Persistence**: port marker matching, operator state, JSONL writer, section lifecycle, and non-secret settings persistence.
6. **LLM Refinement and Translation**: implement Azure OpenAI and Google REST refiners plus the six parity stubs and fail-open runtime behavior.
7. **Native Audio Capture**: implement AVFoundation capture, PCM conversion, permission diagnostics, and audio source tests.
8. **Soniox Adapter**: direct WebSocket adapter, frame parsing, finality/marker filtering, graceful finish, mocked provider tests.
9. **ElevenLabs Adapter**: direct WebSocket adapter, URL/query construction, base64 audio frames, VAD/manual commit, mocked provider tests.
10. **Focused Input and macOS Permissions**: port focused-input helper behavior into Swift modules or a bundled helper, preserving stdin-only text delivery.
11. **Native UI Shell and Settings**: SwiftUI/AppKit monitor/settings/protocol panes, event bridge, non-secret persistence.
12. **Push-to-Talk and Overlay**: global hotkey/event tap, warm session/audio gate, runtime protocol toggles, non-activating overlay.
13. **Compatibility Verification**: run source-derived CLI tests, provider mocks, UI smoke tests, manual live-provider scripts, and produce final drop-in report.
14. **Documentation Sync**: update project design, project functions, configuration guide, pending issues, and deferred gaps.

Each package should list input artifacts, output files, verification commands, out-of-scope boundaries, and handoff notes. Work packages 3-6 can run after skeleton completion; work packages 7-9 can run in parallel after the shared provider/audio protocols exist; UI packages should start only after typed event contracts are stable.

## Comparison Matrix

| Criterion | Option 1: Native SwiftPM Multi-Target | Option 2: Swift Core + Retained Electron UI | Option 3: App Bundle First | Option 4: Monolith + Third-Party Abstractions |
|-----------|----------------------------------------|---------------------------------------------|-----------------------------|-----------------------------------------------|
| Final drop-in fit | High | Low unless transitional only | Medium-high | Medium |
| CLI parity | High | High for CLI, mixed for UI | Medium | Medium |
| `untype ui` parity | High after UI phase | High initially but not Swift-native | High | Medium |
| Native macOS integration | High | Mixed | High | Medium |
| Dependency minimization | High | Low | High | Medium-low |
| SwiftPM build/test fit | High | Medium | Medium | High |
| Provider implementation control | High | High | High | Medium-high |
| Autonomous work-package fit | High | Medium | Medium | Low-medium |
| Time to first useful CLI | Medium | Medium-fast | Slow | Fast |
| Time to final replacement | Medium-slow | Slow/uncertain | Medium-slow | Medium |
| Risk | Medium | Medium-high final risk | Medium-high CLI risk | Medium |
| Long-term viability | High | Low-medium | Medium-high | Medium |

## Recommendation
Choose **Option 1: SwiftPM Native Multi-Target Replacement With Release-Gated UI Parity**.

Why this option wins:
- It best satisfies the refined request's requirement for a Swift implementation while preserving the installed `untype` command.
- It gives the CLI, providers, protocol, LLM, and UI clear module boundaries so autonomous agents can work without duplicating state or stepping on unrelated surfaces.
- It avoids preserving Node/Electron as part of the final runtime, which keeps the replacement honest.
- It allows the CLI/provider/protocol path to be completed and verified before the UI reaches parity, while still treating UI parity as mandatory before declaring the replacement drop-in.
- It keeps dependencies conservative: SwiftPM, Foundation, AVFoundation/AVFAudio, AppKit/SwiftUI, and URLSession are enough for the first implementation unless technical research proves otherwise.

Key decisions:
- **SwiftPM**: use SwiftPM as the authoritative project structure; add app-bundle packaging only when distribution requirements are clarified.
- **CLI**: build a project-owned compatibility parser/schema first; evaluate Swift Argument Parser only if a spike proves it preserves required output and exit behavior.
- **Audio**: implement native AVFoundation capture and explicit PCM conversion; do not keep `sox` as a hidden fallback.
- **Providers**: implement Soniox and ElevenLabs as direct WebSocket adapters over a provider-neutral protocol; start with `URLSessionWebSocketTask`.
- **LLM**: implement Azure OpenAI and Google; preserve the six existing stubs instead of expanding scope.
- **UI**: phase implementation internally, but do not call the project a drop-in replacement until `untype ui` parity is complete.
- **Testing**: use `swift test` for automated coverage and `test_scripts/` for live-provider/macOS-permission smoke tests.

Conditions under which the recommendation would change:
- If the user requires a signed/notarized `.app` as the first deliverable, Option 3 becomes more attractive, with the CLI implemented as a strict compatibility entry point.
- If the user explicitly approves an interim hybrid migration, Option 2 can be used temporarily, but it should be labeled as a bridge, not the final Swift replacement.
- If Foundation WebSockets fail provider requirements in a technical spike, the provider layer should switch to SwiftNIO/WebSocketKit after dependency vetting.
- If exact Commander-style parsing/help is not important, Swift Argument Parser could replace the custom parser to reduce parser maintenance.

Confidence: **Medium-high overall**. The source contract is clear and Swift has native building blocks for the CLI, networking, audio, and UI. Confidence is lower for microphone permission identity, system-wide hotkey release detection, and overlay/focused-input parity until those are validated on macOS.

## Technical Research Guidance

**Research needed**: Yes

### Topic 1: AVFoundation/AVAudioEngine Capture for CLI and App-Bundle Contexts
- **Why**: Native microphone capture is central to removing `sox`, but macOS permission behavior may differ between unbundled CLI execution and bundled app execution.
- **Focus**: `AVAudioEngine` input taps, `AVAudioConverter` to mono signed 16-bit little-endian PCM, sample-rate switching, microphone authorization status/request flow, CLI vs app permission identity, failure mapping.
- **Depth**: Deep dive.
- **Relevance**: Determines the audio module design, packaging assumptions, and manual smoke tests.

### Topic 2: Soniox Direct WebSocket Protocol in Swift
- **Why**: The TypeScript source uses `@soniox/node`, but the Swift replacement should use direct protocol integration unless a native SDK exists and is vetted.
- **Focus**: initial config frame, auth mechanism, binary audio frames, language identification vs hints, endpoint detection, manual finalization, result token schema, error frames, close semantics, repeated final prefix behavior.
- **Depth**: Deep dive.
- **Relevance**: Determines the Soniox adapter implementation and mocked provider test fixtures.

### Topic 3: ElevenLabs Realtime STT Protocol in Swift
- **Why**: The source already implements ElevenLabs directly over WebSocket, but Swift needs provider-accurate URL/query/message handling.
- **Focus**: query parameters, authentication, `input_audio_chunk`, base64 encoding, VAD vs manual commit, partial/committed transcript events, timestamps option, error and close mapping.
- **Depth**: Intermediate to deep dive.
- **Relevance**: Determines ElevenLabs adapter behavior and source parity tests.

### Topic 4: Native macOS Hotkeys, Input Monitoring, Accessibility, and Overlay Windows
- **Why**: `untype ui` parity depends on system-wide push-to-talk press/release, secondary operator toggles, focused-input delivery, and a non-focus-stealing overlay.
- **Focus**: `NSEvent` global monitors, `CGEvent` taps, Accessibility trust checks, Input Monitoring request/preflight APIs, non-activating `NSPanel`, all-spaces/floating window behavior, sandbox/signing implications.
- **Depth**: Deep dive.
- **Relevance**: Determines whether `untype ui` can be implemented as a SwiftPM-launched executable, requires an app bundle, or needs a helper.

### Topic 5: Swift Test Framework Choice for Process-Level CLI and macOS Integration Tests
- **Why**: The project needs both pure module tests and process/macOS smoke tests.
- **Focus**: Swift Testing vs XCTest for SwiftPM packages, launching built executables from tests, temp home/config directories, stdout/stderr capture, async tests, conditional macOS-only tests.
- **Depth**: Intermediate.
- **Relevance**: Determines the test target structure and how compatibility tests are written.

### Topic 6: Distribution and Permission Packaging
- **Why**: "Drop-in" may mean local symlink only, but UI and microphone/accessibility permissions may be more robust with an app bundle, signing, and notarization.
- **Focus**: SwiftPM executable install path, `.app` packaging for SwiftUI/AppKit code, helper embedding, code signing, notarization, Info.plist microphone usage strings, Homebrew or local install strategy.
- **Depth**: Intermediate.
- **Relevance**: Determines whether packaging is a late phase or a first-class design requirement.

## Implementation Considerations
- Build a source-study artifact before implementation. The refined request acceptance criteria require it, and it should become the checklist that all work packages use.
- Keep the source TypeScript tests available as behavioral fixtures. Do not translate tests mechanically without preserving the reason each test exists.
- Use typed errors and stable exit codes as core data types, not strings assembled at call sites.
- Keep config resolution pure and read-only. It must not mutate process environment or write default values.
- Avoid dependency drift in the first milestone. Foundation/AVFoundation/AppKit/SwiftUI should be enough for the recommended path; any external package should trigger dependency vetting first.
- Make all provider adapters transport-injectable so tests do not require live Soniox or ElevenLabs credentials.
- Keep transcript text, processed output, and secrets out of persisted protocol/UI state.
- Design `untype ui` around typed session events from the start. Recreating the Electron UI by parsing terminal output would violate the source architecture.
- Keep `untype ui` visible in milestone tracking. A CLI-only Swift port is useful, but it is not the final drop-in replacement.
- Maintain `Issues - Pending Items.md` for parity gaps discovered during source study, provider protocol uncertainty, permission smoke-test gaps, and dependency vetting notes.

Suggested first steps:
1. Produce `docs/reference/source-study-swift-drop-in-replacement.md` with module map, CLI/config contract, provider contracts, UI behavior, tests, and pending issues.
2. Run the technical research topics above, starting with AVFoundation capture and Soniox direct WebSocket protocol.
3. Create `docs/reference/compatibility-checklist-swift-drop-in-replacement.md` from README, config guide, project functions, and source tests.
4. Create a `docs/design/plan-001-swift-drop-in-replacement.md` that references the refined request, this investigation, the source study, and any research files.

## Assumptions
- SwiftPM is acceptable as the authoritative build structure unless packaging research proves a different structure is required for macOS permissions or distribution.
- "Drop-in" means public behavior parity, not byte-for-byte internal implementation or identical help formatting.
- The replacement may be built in phases, but the final drop-in claim requires `untype ui` parity.
- The Swift implementation should not preserve TypeScript/Electron as a final runtime dependency.
- Live provider testing will require real credentials and should be opt-in/manual outside normal automated tests.
- The target platform for parity is macOS first; cross-platform microphone/UI support is out of scope.

## Open Questions
- Should the final distribution be only a local SwiftPM-built executable/symlink, or does the user require a signed/notarized app bundle and/or Homebrew-style install?
- Is a temporary CLI-only milestone acceptable if it is clearly documented as not yet drop-in, or must `untype ui` parity exist in the first user-visible milestone?
- Should the Swift replacement preserve the exact existing help text wording, or only equivalent flag/subcommand/config documentation?
- Should the native focused-input helper remain a separate internal executable, or should focused input be integrated into the main Swift process/app?
- Are the six unimplemented LLM providers intentionally stubs for parity, or does the user want the Swift replacement to expand provider support beyond the source project?
- What macOS minimum version should the Swift replacement target?

## References
| # | Source | URL | What was learned |
|---|--------|-----|-----------------|
| S1 | Source README | `~/aiwork/coding-platform/untype/README.md` | Public command, install, config, usage, UI, protocol, and error contract. |
| S2 | Source package manifest | `~/aiwork/coding-platform/untype/package.json` | Package name, version, binary name, build/test/audit scripts, dependencies. |
| S3 | Source technical design | `~/aiwork/coding-platform/untype/docs/design/project-design.md` | Architecture, config/mic/provider/renderer/orchestrator contracts. |
| S4 | Source configuration guide | `~/aiwork/coding-platform/untype/docs/design/configuration-guide.md` | Four-tier config chain, defaults, provider/env contract, no hidden fallback rule. |
| S5 | Source functional requirements | `~/aiwork/coding-platform/untype/docs/design/project-functions.md` | Formal functional and non-functional requirements for CLI, protocol, UI, and macOS behavior. |
| S6 | Source config implementation | `~/aiwork/coding-platform/untype/src/config.ts` | Current CLI flags, defaults, env aliases, validation behavior, help/version handling. |
| S7 | Source session runner | `~/aiwork/coding-platform/untype/src/core/sessionRunner.ts` | Runtime composition, shutdown, stdout/stderr separation, UI event bridge, protocol persistence. |
| S8 | Source Soniox adapter | `~/aiwork/coding-platform/untype/src/soniox/client.ts` | Soniox finality, marker filtering, repeated prefix handling, SDK error mapping. |
| S9 | Source ElevenLabs adapter | `~/aiwork/coding-platform/untype/src/elevenlabs/client.ts` | Direct WebSocket query/message format, partial/final event handling, commit behavior. |
| S10 | Source UI implementation | `~/aiwork/coding-platform/untype/src/ui/electronMain.ts` | UI session ownership, warm push-to-talk, hotkey runtime toggles, overlay event delivery. |
| S11 | Source hotkey manager | `~/aiwork/coding-platform/untype/src/ui/globalHotkeyManager.ts` | Current system-wide hotkey and release fallback behavior. |
| S12 | Source focused-input helper | `~/aiwork/coding-platform/untype/native/macos/input-helper/main.swift` | Existing Swift helper behavior for stdin-only focused text delivery and Accessibility diagnostics. |
| R1 | Swift Package Manager documentation | `https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/` | SwiftPM is the build/package/test foundation for Swift packages. |
| R2 | Swift Argument Parser documentation | `https://apple.github.io/swift-argument-parser/documentation/argumentparser/` | Official Swift command-line parsing framework with type-safe declarations and help support. |
| R3 | Swift.org command-line tools | `https://www.swift.org/get-started/command-line-tools/` | Swift supports command-line tool development and commonly uses ArgumentParser. |
| R4 | Apple AVAudioEngine documentation | `https://developer.apple.com/documentation/avfaudio/avaudioengine` | AVAudioEngine manages audio graphs and real-time rendering constraints. |
| R5 | Apple AVAudioNode installTap documentation | `https://developer.apple.com/documentation/avfaudio/avaudionode/installtap%28onbus%3Abuffersize%3Aformat%3Ablock%3A%29` | Audio taps can record/monitor a node output bus. |
| R6 | Apple URLSessionWebSocketTask documentation | `https://developer.apple.com/documentation/foundation/urlsessionwebsockettask` | Foundation provides native WebSocket task support. |
| R7 | Soniox WebSocket API documentation | `https://soniox.com/docs/api-reference/stt/websocket-api` | Soniox exposes realtime STT over a persistent WebSocket API. |
| R8 | ElevenLabs realtime STT API documentation | `https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime` | ElevenLabs realtime STT uses WebSocket audio chunk messages and transcript events. |
| R9 | Apple SwiftUI documentation | `https://developer.apple.com/documentation/swiftui` | SwiftUI provides app structure and declarative view composition. |
| R10 | Apple MenuBarExtra documentation | `https://developer.apple.com/documentation/swiftui/menubarextra` | SwiftUI can render persistent menu-bar controls. |
| R11 | Apple nonactivatingPanel documentation | `https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel` | AppKit supports non-activating panel window behavior. |
| R12 | Apple NSEvent documentation | `https://developer.apple.com/documentation/appkit/nsevent` | AppKit supports local and global event monitors. |
| R13 | Apple AXIsProcessTrustedWithOptions documentation | `https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions` | Accessibility trust can be checked/prompted for the current process. |
| R14 | Apple CGEvent tapCreate documentation | `https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29` | CGEvent taps can receive key events when required permissions are granted. |
| R15 | Apple Swift Testing documentation | `https://developer.apple.com/documentation/testing/` | Swift Testing integrates with SwiftPM testing workflows. |
| R16 | SwiftPM `swift test` documentation | `https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/swifttest/` | `swift test` runs package test targets and supports Swift Testing/XCTest controls. |
| R17 | Microsoft Azure OpenAI REST API reference | `https://learn.microsoft.com/en-us/azure/foundry/openai/reference` | Azure OpenAI can be integrated through documented REST APIs. |
| R18 | Google Gemini API documentation | `https://ai.google.dev/gemini-api/docs` | Gemini exposes documented generate-content APIs suitable for REST integration. |
| R19 | OpenAI Chat Completions API reference | `https://developers.openai.com/api/reference/chat-completions/overview` | OpenAI exposes HTTP APIs if the project later expands stubs. |
| R20 | Anthropic API overview | `https://platform.claude.com/docs/en/api/overview` | Anthropic exposes an HTTP API if the project later expands stubs. |

## Original Request
"Investigate the implementation approach for creating a Swift drop-in replacement of the TypeScript `untype` project.

Active project root: ~/aiwork/coding-platform/untype-s
Source TypeScript project root: ~/aiwork/coding-platform/untype
REFINED_REQUEST_FILE: ~/aiwork/coding-platform/untype-s/docs/reference/refined-request-swift-drop-in-replacement.md

Read the refined request specification first. Read relevant source project files/docs as needed. Produce the investigation document at ~/aiwork/coding-platform/untype-s/docs/reference/investigation-swift-drop-in-replacement.md.

Focus decisions:
- SwiftPM structure for CLI and native macOS support.
- CLI parity and compatibility strategy.
- Native audio capture strategy on macOS.
- WebSocket/provider implementation strategy for Soniox and ElevenLabs.
- LLM provider strategy, including preserving stubs versus full implementation.
- UI parity approach for `untype ui`: first milestone or phased; SwiftUI/AppKit/menu-bar/overlay options.
- Test strategy and autonomous-agent work-package decomposition.

Include: executive summary, context, options, comparison matrix, recommendation, technical research guidance, implementation considerations, assumptions, open questions, and original request. Return the report path, recommendation, confidence, and any technical research topics that should be run next."
