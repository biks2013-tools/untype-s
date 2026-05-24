# Plan 001: Swift Drop-In Replacement

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-swift-drop-in-replacement.md`
- Investigation: `~/aiwork/coding-platform/untype-s/docs/reference/investigation-swift-drop-in-replacement.md`
- Technical research:
  - `~/aiwork/coding-platform/untype-s/docs/research/avfoundation-audio-capture.md`
  - `~/aiwork/coding-platform/untype-s/docs/research/soniox-websocket-swift.md`
  - `~/aiwork/coding-platform/untype-s/docs/research/elevenlabs-realtime-stt-swift.md`
  - `~/aiwork/coding-platform/untype-s/docs/research/macos-ui-hotkey-overlay.md`
  - `~/aiwork/coding-platform/untype-s/docs/research/swift-testing-distribution.md`
- Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-source-untype.md`
- Source study: `~/aiwork/coding-platform/untype-s/docs/reference/source-study-untype.md`
- Compatibility checklist: `~/aiwork/coding-platform/untype-s/docs/reference/compatibility-checklist-swift-drop-in-replacement.md`

## Objective
Create a Swift-native implementation in `untype-s` that can replace the TypeScript `untype` command once CLI, provider, protocol, macOS, and UI parity are implemented and verified.

## Milestone Strategy
The first milestone creates a SwiftPM skeleton and CLI/config compatibility base. The final drop-in claim is gated on native UI parity and live macOS/provider smoke tests.

## Autonomous Work Packages
| Phase | Owner scope | Inputs | Outputs | Verification |
| --- | --- | --- | --- | --- |
| 1. Source contract extraction | Docs/reference only | Refined request, source scan, source docs/tests | Source study and compatibility checklist | Checklist reviewed for every source module |
| 2. SwiftPM skeleton | `Package.swift`, `Sources`, `Tests` | Investigation, Swift testing research | Executable product named `untype`, buildable test target | `swift build`, `swift test` |
| 3. CLI/config parity | Config and CLI modules | Source `src/config.ts`, config guide, checklist | Flag/env schema, parsers, help/version, typed config errors | Config unit tests and CLI process tests |
| 4. Renderer/session core | CLI/runtime modules | Source `sessionRunner`, renderer tests | stdout/stderr routing, renderer modes, shutdown model | Renderer and process tests |
| 5. Protocol/persistence | Protocol modules | Source `src/protocol`, protocol tests | marker matcher, state machine, JSONL writer, settings store | Protocol unit tests |
| 6. LLM parity | LLM modules | Source LLM modules/tests | Azure OpenAI, Google, six accepted stubs | Mocked REST tests |
| 7. Native audio | Audio/macOS modules | AVFoundation research | Permission preflight, AVAudioEngine capture, PCM conversion | Unit tests with synthetic buffers, manual mic smoke |
| 8. Soniox provider | Provider module | Source adapter/tests, Soniox research | Direct WebSocket adapter, typed error mapping | Mock transport tests, live smoke script |
| 9. ElevenLabs provider | Provider module | ElevenLabs research | Direct WebSocket adapter | Mock transport tests, live smoke script |
| 10. Focused input | macOS helper module | UI/macOS research, source helper | stdin-fed focused-input helper and diagnostics | Unit tests and manual Accessibility smoke |
| 11. Native UI shell | UI module | Source UI scan, UI research | SwiftUI/AppKit settings/monitor/event rendering | UI smoke test |
| 12. Push-to-talk and overlay | UI/macOS modules | Source hotkey/overlay, UI research | Event tap, warm session, non-activating overlay | Manual hotkey/overlay smoke |
| 13. Compatibility verification | Tests/scripts/docs | Checklist and all modules | Verification report and updated checklist | `swift build`, `swift test`, smoke tests |
| 14. Documentation sync | Docs only | Implementation results | Updated design, functions, pending items | Docs reviewed against checklist |

## Files to Create or Modify
- `Package.swift`
- `Sources/untype/main.swift`
- `Sources/UntypeCore/*`
- `Sources/UntypeConfig/*`
- `Sources/UntypeCLI/*`
- `Sources/UntypeProtocol/*`
- `Sources/UntypeProviders/*`
- `Sources/UntypeAudio/*`
- `Sources/UntypeLLM/*`
- `Sources/UntypeMacOS/*`
- `Sources/UntypeUI/*`
- `Tests/*`
- `test_scripts/*`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `docs/reference/*`
- `Issues - Pending Items.md`

## Out of Scope for Phase 1
- Live Soniox/ElevenLabs network sessions.
- Full AVFoundation capture.
- Full voice-agent protocol.
- Native UI parity.
- App bundle signing/notarization.

## Phase 1 Acceptance Criteria
- `swift build` succeeds.
- `swift test` succeeds.
- Built executable supports `--help` and `--version`.
- Missing active STT API key produces a typed config error with exit code `2`.
- Documentation and pending issues clearly state which parity items remain open.
