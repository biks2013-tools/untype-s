# Source Study: TypeScript `untype`

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-swift-drop-in-replacement.md`
- Investigation: `~/aiwork/coding-platform/untype-s/docs/reference/investigation-swift-drop-in-replacement.md`
- Source scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-source-untype.md`
- Source project: `~/aiwork/coding-platform/untype`

## Executive Summary
The TypeScript project is a macOS-focused dictation and voice-agent tool exposed as the installed command `untype`. It captures microphone audio, streams PCM to Soniox or ElevenLabs realtime STT, renders human transcripts or JSONL protocol events, optionally processes submitted sections with LLM refiners, and exposes an Electron UI with settings, push-to-talk, hotkey overlay, and protocol controls.

The Swift replacement must preserve the public behavior, not the internal implementation. The strongest compatibility boundaries are the README usage contract, `docs/design/project-functions.md`, `docs/design/configuration-guide.md`, source tests, and the modules listed in `codebase-scan-source-untype.md`.

## Source Module Responsibilities
| Source area | Swift replacement responsibility |
| --- | --- |
| `src/index.ts`, `src/main.ts`, `src/core/sessionRunner.ts` | Executable dispatch, `untype ui`, session lifecycle, signal handling, exit-code mapping, stdout/stderr separation. |
| `src/config.ts`, `src/config/*` | CLI flags, env-chain precedence, typed validation, expiry warnings, no hidden config fallbacks. |
| `src/errors.ts` | Stable error codes and exit codes for config, mic, provider, and LLM failures. |
| `src/mic/*` | Replace `sox` capture with native AVFoundation capture and PCM conversion. |
| `src/soniox/client.ts` | Direct Soniox WebSocket adapter with marker filtering, final-prefix merge behavior, typed errors, commit/finish semantics. |
| `src/elevenlabs/client.ts` | Direct ElevenLabs WebSocket adapter with base64 JSON audio frames, commit/VAD mode, typed errors. |
| `src/render/*` | `overwrite`, `append`, `final-only`, non-TTY downgrade, duplicate partial suppression, TTY cleanup. |
| `src/protocol/*`, `src/turn/*` | Spoken command matching, operator state, section lifecycle, JSONL event schema, non-secret persistence. |
| `src/llm/*` | Azure OpenAI and Google refiners, provider stubs for the remaining accepted LLM provider names, fail-open runtime behavior. |
| `src/platform/macos/*` | Focused-input delivery through stdin-fed helper semantics and Accessibility diagnostics. |
| `src/ui/*` | Native SwiftUI/AppKit equivalent for monitoring UI, settings, push-to-talk, overlay, typed event rendering, and non-secret UI state. |

## CLI Contract Highlights
- Installed command: `untype`.
- `untype --help` and `untype --version` exit `0`.
- `untype ui` is part of the public command surface.
- Human transcript output belongs on stdout; diagnostics, readiness, warnings, and errors belong on stderr unless UI mode owns presentation.
- JSONL protocol mode emits one event per line with monotonically increasing `seq` values.
- `overwrite` output mode must auto-downgrade to `append` when stdout is not a TTY.

## Configuration Contract Highlights
Priority order, highest first:
1. CLI flag
2. `<cwd>/.env`
3. `~/.tool-agents/untype/.env`
4. Shell environment

Required settings must raise typed errors when missing. The replacement must not invent placeholder keys, fallback credentials, or hidden defaults for required configuration. Optional documented defaults are allowed only when they are part of the source contract.

## Provider Contract Highlights
- Soniox default model: `stt-rt-v4`.
- ElevenLabs default model: `scribe_v2_realtime`.
- Active STT providers: `soniox`, `elevenlabs`.
- LLM providers accepted by config: `azure-openai`, `openai`, `anthropic`, `google`, `azure-ai-inference`, `ollama`, `litellm`, `openai-compat`.
- LLM providers implemented in the source: `azure-openai`, `google`.
- The six remaining LLM provider names are accepted-but-not-implemented compatibility stubs.

## Test Evidence
The source has broad unit coverage under `tests/`, especially for config, renderers, provider adapters, protocol state, LLM refiners, UI settings/hotkeys, and focused input. It does not include live provider end-to-end automation or UI automation, so the Swift replacement needs mocked automated tests plus manual macOS/live-provider smoke tests.

## Handoff Notes
- Preserve source behavior first. Do not expand provider support or UI behavior unless the expansion is explicitly planned.
- Treat `untype ui` as mandatory final parity, but it can be phased after CLI/protocol/provider parity.
- Keep all parity gaps in `Issues - Pending Items.md` until implemented and verified.
