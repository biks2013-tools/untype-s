# Compatibility Checklist: Swift Drop-In Replacement

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-swift-drop-in-replacement.md`
- Source study: `~/aiwork/coding-platform/untype-s/docs/reference/source-study-untype.md`
- Source scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-source-untype.md`

## Status Legend
- `[ ]` Not started
- `[~]` Started, not complete
- `[x]` Complete and verified
- `[deferred]` Intentionally phased, tracked in pending issues

## Command Surface
- [x] SwiftPM executable product named `untype` exists.
- [x] `untype --help` exits `0` and documents commands, flags, env aliases, and examples.
- [x] `untype --version` exits `0` and prints semantic version.
- [~] `untype ui` launches a native SwiftUI/AppKit monitoring UI; live UI smoke verification remains pending before final parity.
- [x] UI mode installs a native app menu so standard macOS shortcuts such as `Command+W` and `Command+Q` work.
- [x] Unknown flags produce deterministic config errors and exit code `2`.
- [~] Diagnostic stderr separation is verified for scaffold/config errors, protocol-controller diagnostics, provider-neutral runtime diagnostics, and CLI runtime startup/shutdown routing; full live transcript stdout separation remains pending live smoke verification.

## Configuration
- [x] CLI flag tier has highest priority.
- [x] `<cwd>/.env` tier has second priority.
- [x] `~/.tool-agents/untype/.env` tier has third priority.
- [x] Shell environment tier has fourth priority.
- [x] Required missing settings raise typed errors, with no hidden fallback.
- [x] Malformed configuration values raise typed invalid-configuration errors, and `.env` parser edge cases for comments, `export`, quoted values, inline comments, blank lines, and whitespace-only fallthrough are covered.
- [x] API-key expiry warnings are emitted without blocking startup.
- [x] Non-secret protocol settings and non-secret UI settings are persisted without transcript text or credentials.
- [x] UI startup derives display settings from the CLI configuration chain plus persisted non-secret UI/protocol state, and reports strict LLM configuration errors without blocking settings display.
- [x] Legacy `~/.tool-agents/mic-tool-ts/` migration detection raises the source-compatible no-fallback migration hint when the current `~/.tool-agents/untype/` folder is absent.

## Audio and STT Providers
- [~] AVFoundation microphone permission preflight maps denial/restriction to typed microphone errors with exit code `3`; live permission smoke remains pending.
- [~] AVAudioEngine capture is implemented with mono PCM16 conversion at the configured sample rate and synthetic converter tests; live microphone capture smoke remains pending.
- [~] Soniox direct WebSocket adapter supports config/audio/finalize/finish frames, partials, finals, marker filtering, final-prefix merge, endpoint commits, typed errors at the mockable transport boundary, and a concrete `URLSessionWebSocketTask` receive loop; live smoke remains pending.
- [~] ElevenLabs direct WebSocket adapter supports base64 audio chunks, manual/VAD commit, partials/finals, and typed errors at the mockable transport boundary; live smoke remains pending.
- [x] Provider-neutral runtime forwards PCM audio chunks to the active transcriber.
- [x] Provider-neutral runtime forwards STT partial/final transcript events into the protocol controller.
- [x] Provider adapters are covered by mocked transport tests for Soniox and ElevenLabs.
- [~] Real provider/audio smoke tests are documented under `test_scripts/soniox-live-smoke.md`, `test_scripts/elevenlabs-live-smoke.md`, and `test_scripts/microphone-live-smoke.md`; manual execution remains pending.

## Rendering
- [x] `overwrite` mode renders partials in place on TTY.
- [x] `overwrite` mode clears wrapped terminal rows.
- [x] `overwrite` mode downgrades to `append` for non-TTY output.
- [x] `append` mode emits each non-duplicate partial/final as a line.
- [x] `final-only` suppresses partials and emits finals only.
- [x] Duplicate partial snapshots are suppressed.
- [x] `<end>` and `<fin>` marker tokens are filtered.

## Voice-Agent Protocol
- [~] Dictation, agent-protocol, and hybrid state-machine primitives are implemented and wired into the Swift protocol controller, provider-neutral session runtime, concrete audio source, selected STT provider, partial voice-command commit triggering, and async CLI lifetime; live provider verification remains pending.
- [x] Spoken state commands update operator state and the controller exposes the latest settings snapshot for shutdown persistence.
- [~] `command status`, `command send`, `command cancel`, and `literal phrase` semantics are covered at the state-machine/controller/runtime level; live provider verification remains pending.
- [x] JSONL events use the source event names and monotonically increasing `seq`.
- [x] Section pipeline order is raw -> refine -> translate -> render/event -> clipboard -> focused input at the protocol-controller boundary.
- [~] Protocol warnings are fail-open at the controller boundary; concrete provider/session warning behavior remains pending.

## LLM
- [x] Azure OpenAI refiner is implemented with direct REST requests, mockable HTTP tests, response trimming, dispose cancellation, and auth/server/network/timeout/shape error mapping.
- [x] Google Gemini refiner is implemented with direct REST requests, mockable HTTP tests, response trimming, dispose cancellation, and auth/server/network/timeout/shape error mapping.
- [x] Six other standard provider names remain accepted stubs unless separately approved.
- [x] Startup LLM configuration failures are fatal exit code `2`.
- [x] Runtime LLM failures are fail-open at the protocol-controller boundary and concrete Azure/Google refiner error mapping is covered by Swift tests.
- [x] No API keys, prompts, transcript text, or processed content are persisted in protocol or UI settings.

## macOS Integration and UI
- [x] Focused-input helper reads processed text from stdin, not argv.
- [x] Accessibility failures produce actionable non-fatal warnings at the protocol/runtime boundary.
- [~] Native UI renders session events through typed runtime callbacks and UI text outputs; grouped transcript timeline and clear action are implemented, while live UI smoke remains pending.
- [x] UI settings, credential status, and transient macOS permission status avoid exposing secret values or host-specific permission state in persistence and tests.
- [x] Native UI locks session-shaping controls during manual, warm, or recording sessions while keeping the four protocol operator switches editable.
- [~] Push-to-talk press/release, operator hotkeys, Quartz event-tap suppression with AppKit fallback, warm hotkey-owned session reuse, silence gating, and five-minute idle recycling are implemented; live Accessibility/Input Monitoring verification remains pending.
- [~] Non-activating overlay displays live/committed text, shows compact protocol operator indicators, and clears text on hide; live focus behavior smoke remains pending.
- [~] Manual smoke tests cover microphone permission, live provider paths, focused-input helper delivery, UI launch, push-to-talk, and overlay behavior; manual execution remains pending.

## Documentation and Verification
- [x] Refined request, investigation, research, source scan, source study, and checklist exist.
- [x] Project design and project functions are initialized.
- [x] Pending parity gaps are tracked in `Issues - Pending Items.md`.
- [x] `swift build` passes.
- [x] `swift test` passes.
- [x] Final verification report states whether the Swift implementation can replace the TypeScript command: `docs/reference/verification-report-swift-drop-in-replacement.md`.
