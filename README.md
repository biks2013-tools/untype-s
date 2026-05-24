# untype-s

Swift-native drop-in replacement for the TypeScript [`untype`](../untype) CLI. The shipped executable is named `untype` and preserves the public CLI, configuration, transcription, voice-agent protocol, macOS integration, and UI behavior of the source project.

## Status

Work in progress. The project is being built in autonomous phases tracked under `docs/design/`. Current implementation includes:

- Configuration resolver with the full source precedence chain (CLI flag → `<cwd>/.env` → `~/.tool-agents/untype/.env` → shell env), source-compatible `.env` parsing edge coverage, expiry warnings, and legacy config-folder migration detection
- Transcript renderer for `overwrite`, `append`, and `final-only` modes (with non-TTY overwrite downgrade)
- Voice-agent protocol runtime: marker matching, operator state, section lifecycle, JSONL event writer, non-secret persisted settings, clipboard delivery, and focused-input helper integration
- Provider-neutral session orchestration with native AVFoundation audio capture and signal-aware CLI shutdown
- Soniox and ElevenLabs WebSocket adapters with live `URLSessionWebSocketTask` transport and mock-verified frame contracts
- Azure OpenAI and Google Gemini LLM refiners, with accepted stubs for the other source-compatible provider names
- Native SwiftUI/AppKit `untype ui` mode with non-secret UI settings, credential and transient macOS permission status, grouped transcript timeline, source-compatible active-session editability, Quartz event-tap push-to-talk monitoring with AppKit/UI-button fallback, warm session recycling, and an operator-aware non-activating overlay

Pending: live microphone/provider/macOS permission smoke verification, final UI polish, and signed/notarized app distribution planning. See `Issues - Pending Items.md` for the current backlog.

## Requirements

- macOS 14 or newer
- Swift 6.0 toolchain (Xcode 16 or Swift 6 command-line tools)

## Build

```sh
swift build
```

The executable lands at `.build/debug/untype`. For a release build:

```sh
swift build -c release
```

## Test

```sh
swift test
```

Unit tests live under `Tests/UntypeCoreTests/`. Manual smoke tests for live microphone, provider, and macOS-permission checks live under `test_scripts/`.

## Usage

```sh
.build/debug/untype --help
.build/debug/untype --version
```

Refer to the source project's CLI for the complete flag and command surface; this project preserves that contract.

## Configuration

Settings are resolved in the following precedence order (highest first):

1. CLI flag
2. `<cwd>/.env`
3. `~/.tool-agents/untype/.env`
4. Shell environment

Missing required values raise typed errors — the project does NOT substitute fallback values.

## Project Layout

```
Sources/
  untype/         Thin executable entry point
  UntypeCore/    Config resolver, renderer, protocol runtime, providers
Tests/
  UntypeCoreTests/
docs/
  design/         Plans, project design, functional requirements
  reference/      Refined request, investigations, codebase scans
  research/       Technical research notes per topic
test_scripts/    Manual smoke-test procedures
```

## Documentation

- Project design: [`docs/design/project-design.md`](docs/design/project-design.md)
- Functional requirements: [`docs/design/project-functions.md`](docs/design/project-functions.md)
- Implementation plan: [`docs/design/plan-001-swift-drop-in-replacement.md`](docs/design/plan-001-swift-drop-in-replacement.md)
- Open issues and backlog: [`Issues - Pending Items.md`](Issues%20-%20Pending%20Items.md)

## License

Not yet declared.
