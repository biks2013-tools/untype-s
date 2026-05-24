---
language: TypeScript
framework: none
package_manager: pnpm
build_command: "tsc -p . && mkdir -p dist/ui/renderer && cp src/ui/renderer/index.html src/ui/renderer/styles.css src/ui/renderer/overlay.html src/ui/renderer/overlay.css dist/ui/renderer/ && node scripts/build-native-helper.mjs"
test_command: "vitest run"
lint_command: null
entry_points:
  - "src/index.ts"
  - "src/main.ts"
last_scanned_commit: fd91911fb138448c3611aae5b0b5c25b11ebdbe7
scanned_for_request: refined-request-swift-drop-in-replacement.md
scanned_at: 2026-05-23T17:29:09Z
---

# Codebase Scan — untype

## 1. Project Overview
`untype` is a TypeScript, pnpm-managed, macOS-only CLI + Electron UI application. The runtime path is split between a CLI bootstrap (`src/index.ts`, `src/main.ts`), a shared session runner, and a UI process that reuses the same transcription/protocol/core modules rather than duplicating behavior.

The repo is unusually explicit about parity rules: the README, design docs, and tool reference all describe the same configuration chain, protocol shapes, and UI behaviors that the code implements. That makes this repository a solid behavioral source of truth for a Swift replacement.

## 2. Module Map
| Path | Purpose | Representative symbols |
| --- | --- | --- |
| `src/index.ts` | Top-level CLI shim that chooses between the terminal runner and the Electron UI subcommand. | `main`, `launchElectronUi` |
| `src/main.ts` | CLI entrypoint wrapper that forwards argv into the shared mic session runner. | `main`, `runMicSession` |
| `src/config.ts` | Parses Commander flags, resolves the four-tier config chain, validates typed config, and materializes `ResolvedConfig`. | `resolveConfig`, `HelpOrVersionShown`, `ResolvedConfig` |
| `src/config/` | Read-only env-chain loader, typed parsers, and expiry warning helpers for secrets and dates. | `loadEnvChain`, `parseBoolean`, `parseIsoDate`, `warnAboutExpiry` |
| `src/core/` | Shared runtime orchestration for CLI and UI sessions, plus the typed event stream used to keep the UI in sync. | `runMicSession`, `safeConfigSummary`, `SessionEvent` |
| `src/elevenlabs/` | ElevenLabs realtime STT adapter built directly on `ws`, mirroring the provider contract used by the orchestrator. | `ElevenLabsTranscriber`, `buildRealtimeUrl`, `mapServerError` |
| `src/errors.ts` | Single error taxonomy with stable codes and exit codes for config, mic, provider, and LLM failures. | `MicToolError`, `MissingConfigurationError`, `LLMRefinementError` |
| `src/llm/` | LLM abstraction and provider implementations for refinement and translation. | `LLMConfig`, `LLMRefiner`, `createRefiner`, `AzureOpenAIRefiner`, `GoogleRefiner` |
| `src/mic/` | Platform-dispatched microphone source abstraction and macOS `sox` implementation. | `MicSource`, `createMicSource`, `SoxMicSource`, `AUDIO_SAMPLE_RATE` |
| `src/platform/macos/` | Native focused-input delivery helper and result parsing for the final processed text pipeline. | `sendToFocusedInput`, `resolveFocusedInputHelperPath`, `FocusedInputDeliveryError` |
| `src/protocol/` | Spoken-command parser, state machine, JSONL writer, settings persistence, and the high-level protocol controller. | `VoiceAgentProtocolController`, `VoiceCommandStateMachine`, `JsonlProtocolWriter`, `normalizeOrdinaryMarker` |
| `src/render/` | Output adapters for stdout and UI event emission, including overwrite/append/final-only rendering semantics. | `StdoutRenderer`, `UiRenderer`, `Renderer` |
| `src/soniox/` | Soniox realtime STT adapter built on the `@soniox/node` SDK. | `SonioxTranscriber`, `commit`, `stop`, `mapSdkError` |
| `src/transcription/` | Provider-neutral transcription contract and factory that chooses Soniox vs ElevenLabs. | `Transcriber`, `TranscriberOptions`, `createTranscriber` |
| `src/turn/` | Guard-phrase turn detector that wraps rendering and optional LLM refinement around committed transcript turns. | `GuardPhraseTurnDetector`, `normalizeForMatch`, `stripGuardPhrase` |
| `src/ui/` | Electron main process, hotkey manager, runtime settings, persisted UI state, overlay controller, and preload bridge. | `launchElectronUi`, `GlobalHotkeyManager`, `loadRendererSettingsForUi`, `TranscriptionOverlayManager`, `savePersistedUiSettings` |

## 3. Conventions
- The codebase is consistently ESM-first and favors named imports plus `type` imports; the top-level shims are tiny and defer to shared modules instead of owning behavior. See `src/index.ts:1-15` and `src/main.ts:1-9`.
- Error handling is typed and exit-code-driven. Startup failures are represented by `MicToolError` subclasses, while runtime LLM failures are intentionally fail-open and only logged when verbose. See `src/errors.ts:20-129` and `src/core/sessionRunner.ts:77-355`.
- Configuration resolution is explicit and side-effect free. The four tiers are `CLI flag -> <cwd>/.env -> ~/.tool-agents/untype/.env -> process.env`, and the code never mutates `process.env`. See `src/config/envChain.ts:1-145`, `src/config.ts:1-140`, and `docs/design/configuration-guide.md:12-34`.
- Logging is done with direct `process.stderr.write(...)` calls and `[untype]` prefixes rather than a logging library. That pattern appears in the STT providers, hotkey manager, and session runner. See `src/soniox/client.ts:137-187`, `src/elevenlabs/client.ts:64-135`, and `src/ui/globalHotkeyManager.ts:127-150`.
- Shutdown and disposal are idempotent and promise-based. Mic, STT, renderer, refiner, and UI paths all try to cleanly stop without assuming a single call site. See `src/soniox/client.ts:243-302`, `src/elevenlabs/client.ts:184-235`, `src/mic/soxMicSource.ts:233-282`, and `src/core/sessionRunner.ts:205-355`.
- The protocol layer uses structured, snake_case JSON event shapes, while the implementation code stays camelCase. That split is visible in `src/protocol/types.ts:66-127`, `src/protocol/controller.ts:150-312`, and `src/ui/renderer/app.ts:53-87`.
- The UI is a narrow Electron shell with a preload bridge, sandboxed renderer, and IPC boundary rather than a generic web app. See `src/ui/electronMain.ts:150-260`, `src/ui/preload.cts:35-79`, and `src/ui/renderer/app.ts:219-320`.

## 4. Integration Points
### In-Scope
- CLI/bootstrap/config path: `src/index.ts:1-15`, `src/main.ts:1-9`, `src/config.ts:1-140`, `src/config/envChain.ts:1-145`, `src/config/parsers.ts:1-123`, `src/config/expiry.ts:1-90`.
- Core runtime path: `src/core/sessionRunner.ts:77-355`, `src/core/sessionEvents.ts:1-114`.
- Mic and provider path: `src/mic/index.ts:1-28`, `src/mic/types.ts:1-24`, `src/mic/soxMicSource.ts:1-320`, `src/transcription/factory.ts:1-12`, `src/transcription/types.ts:1-42`, `src/soniox/client.ts:1-320`, `src/elevenlabs/client.ts:1-340`.
- Protocol and turn detection path: `src/protocol/markerMatcher.ts:1-210`, `src/protocol/stateMachine.ts:61-320`, `src/protocol/controller.ts:41-312`, `src/protocol/jsonlWriter.ts:1-36`, `src/protocol/settingsStore.ts:1-320`, `src/turn/detector.ts:1-198`.
- LLM refinement path: `src/llm/types.ts:1-92`, `src/llm/factory.ts:1-53`, `src/llm/azureOpenAI.ts:1-172`, `src/llm/google.ts:1-167`.
- Output/rendering path: `src/render/renderer.ts:1-241`, `src/render/uiRenderer.ts:1-32`.
- Electron/UI path: `src/ui/launcher.ts:1-27`, `src/ui/electronMain.ts:1-260`, `src/ui/globalHotkeyManager.ts:55-240`, `src/ui/runtimeSettings.ts:32-198`, `src/ui/settingsStore.ts:58-260`, `src/ui/transcriptionOverlay.ts:23-192`, `src/ui/transcriptionOverlayState.ts:1-260`, `src/ui/hotkey.ts:1-279`, `src/ui/preload.cts:35-79`, `src/ui/renderer/app.ts:1-320`, `src/ui/renderer/overlay.ts:1-170`.
- Native focused-input path: `src/platform/macos/focusedInputHelper.ts:1-263`.

### Out-of-Scope
- Documentation files are behavioral references, not implementation targets: `README.md:1-242`, `docs/design/project-design.md:1-120`, `docs/design/configuration-guide.md:1-140`, `docs/design/project-functions.md:1-140`, and `docs/tools/untype.md:1-83`.
- Test files are coverage evidence and should stay untouched during a Swift port unless behavior changes require test updates in the source repo: `tests/config.test.ts:1`, `tests/protocol.test.ts:1`, `tests/soniox-client.test.ts:1`, `tests/elevenlabs-client.test.ts:1`, `tests/ui-global-hotkey-manager.test.ts:1`, `tests/focused-input-helper.test.ts:1`, `tests/llm-azure-openai.test.ts:1`, and the other 17 test files under `tests/`.

### New Integration Points
- The source repo has no Swift code, so the Swift replacement will need new landing sites in the destination project for the same responsibilities: mic capture, provider adapters, protocol/state-machine logic, and the UI/runtime bridge. The clearest seams to mirror are `src/mic/soxMicSource.ts:71-320`, `src/soniox/client.ts:65-320`, `src/elevenlabs/client.ts:40-340`, `src/protocol/controller.ts:41-312`, and `src/ui/electronMain.ts:1-260` plus `src/ui/preload.cts:35-79`.
- If the Swift rewrite keeps an interactive UI, the Electron-specific IPC and preload boundary should be replaced by a Swift-native app boundary rather than emulated piecemeal. The source contract to preserve is the typed session-event stream consumed by `src/ui/renderer/app.ts:53-87` and the overlay state reducer in `src/ui/transcriptionOverlayState.ts:91-260`.

## 5. Notes
- There is no `lint` script in `package.json`; the project currently exposes `build`, `dev`, `start`, `typecheck`, `test`, `test:watch`, and `audit` only. See `package.json:12-19`.
- `build` is not just TypeScript compilation. It also copies renderer assets and runs `scripts/build-native-helper.mjs`, so packaging a replacement needs to account for bundled UI assets and a native helper artifact. See `package.json:13-19` and `src/ui/renderer/index.html`.
- `src/llm/factory.ts:5-53` accepts eight provider names, but only `azure-openai` and `google` are implemented; the other six are deliberate config-time stubs. That is a compatibility surface, not dead code.
- The test suite is broad but still unit-heavy: 24 test files cover config, protocol, turn detection, mic capture, STT adapters, renderer, UI hotkey/state, focused-input delivery, and LLM providers, but there is no live end-to-end provider or UI automation harness in this repo.
