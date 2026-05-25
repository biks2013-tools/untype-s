---
language: Swift
framework: SwiftPM, SwiftUI/AppKit, AVFoundation
package_manager: Swift Package Manager
build_command: "swift build"
test_command: "swift test"
lint_command: null
entry_points:
  - "Sources/untype/main.swift"
  - "Sources/untype-input-helper/main.swift"
last_scanned_commit: null
request_file: "docs/reference/refined-request-untype-high-cpu-typing-lag.md"
scan_scope: "Focused scan of UI runtime, audio activity, push-to-talk warm session, and focused-input delivery"
generated_at: "2026-05-25"
---

# Codebase Scan: Untype High CPU and Focused Typing Lag

## Overview
`untype-s` is a SwiftPM macOS CLI/UI project with two executables: `untype` and `untype-input-helper`. The high-CPU and focused-field lag report maps to the native UI runtime path, the warm push-to-talk audio gate, and the focused-input helper.

Version-control metadata was not read because the active project instruction says not to perform version-control operations unless explicitly requested.

## Module Map
| Path | Purpose | Relevant Symbols |
| --- | --- | --- |
| `Package.swift` | SwiftPM manifest defining `untype`, `untype-input-helper`, `UntypeCore`, and tests. | package targets |
| `Sources/untype/main.swift` | CLI executable entry point; launches UI directly on the initial main thread for `untype ui`. | `UntypeExecutable` |
| `Sources/untype-input-helper/main.swift` | Focused-input helper executable wrapper. | `FocusedInputHelperMain.run` |
| `Sources/UntypeCore/NativeUntypeUILauncher.swift` | SwiftUI/AppKit UI, warm push-to-talk lifecycle, hotkey monitor, overlay, audio status handling. | `UntypeUIModel`, `UntypeHotkeyMonitor`, `UntypeOverlayController` |
| `Sources/UntypeCore/TranscriptionSessionRuntime.swift` | Provider-neutral runtime; routes microphone buffers into STT and emits session/audio events. | `TranscriptionSessionRuntime`, `AudioActivitySnapshot`, `audioChunkForGate`, `emitAudioActivity` |
| `Sources/UntypeCore/AVFoundationAudioSource.swift` | Microphone capture and PCM16 conversion through `AVAudioEngine`. | `AVFoundationAudioSource`, `PCM16MonoConverter` |
| `Sources/UntypeCore/FocusedInputDelivery.swift` | Parent-process launcher for `untype-input-helper`; streams text over stdin. | `FocusedInputDelivery`, `runFocusedInputHelperProcess` |
| `Sources/UntypeCore/FocusedInputHelper.swift` | macOS Accessibility/keyboard/pasteboard focused-input insertion strategies. | `deliverAuto`, `axInsert`, `unicodeType`, `pasteWithKeyCode` |
| `Sources/UntypeCore/SonioxTranscriber.swift` | Soniox WebSocket adapter; accepts binary PCM chunks and finalize commands. | `pushAudio`, `commit`, `stop` |
| `Sources/UntypeCore/ElevenLabsTranscriber.swift` | ElevenLabs WebSocket adapter; base64-encodes each PCM chunk into JSON text frames. | `pushAudio`, `inputAudioChunk` |

## Conventions Observed
- The project is dependency-light and uses only SwiftPM plus Apple frameworks. `Package.swift:1-24`
- Missing configuration must raise typed errors; no configuration fallback should be introduced. `README.md:31-39`
- Runtime behavior is exercised through Swift Testing tests under `Tests/UntypeCoreTests/`.
- Manual live verification remains documented separately in `test_scripts/` for macOS permission and provider-dependent behavior.

## Integration Points

### In-Scope
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift:262-270`: every audio callback computes a gated chunk, emits audio activity, and pushes audio to the transcriber.
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift:519-531`: closed push-to-talk gate allocates a new zero-filled `Data` for every audio buffer and compares full `Data` values to decide whether the stream is muted.
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift:534-549`: `peakAmplitude` scans every PCM sample for every emitted audio activity event.
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:732-735`: the UI mutates `@Published audioStatus` for every `.audioActivity` event, even though event-log writes are throttled later in `appendAudioActivityEvent`.
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:580-589`: enabling push-to-talk starts a warm hotkey-owned session before the key is pressed.
- `Sources/UntypeCore/FocusedInputHelper.swift:134-155`: auto focused-input delivery tries AX insertion, then Unicode keyboard events for up to 500 UTF-16 units, then paste-keycode.
- `Sources/UntypeCore/FocusedInputHelper.swift:280-310`: Unicode delivery posts one key-down/key-up pair per character and sleeps after each character.
- `Sources/UntypeCore/FocusedInputHelper.swift:313-344`: paste-keycode delivery writes text once to the pasteboard, posts Command-V, waits briefly, and restores the pasteboard.

### Out-of-Scope
- Provider frame parsing and error mapping in `Sources/UntypeCore/SonioxTranscriber.swift` and `Sources/UntypeCore/ElevenLabsTranscriber.swift`, except for their role as audio sinks.
- LLM refinement and translation implementations.
- Configuration resolver behavior.
- Overlay visual redesign.

### Duplication Check
The requested functionality is already implemented, but the likely issue is excessive work in the existing implementation:
- Audio activity is implemented but not throttled at the UI mutation boundary.
- Focused input is implemented but `auto` favors per-character Unicode events before the faster paste-keycode fallback.

No parallel implementation should be created.

## Likely Risk Areas
- Throttling audio activity too aggressively could reduce UI evidence that the microphone is alive. A short interval and immediate category-change updates should preserve observability.
- Reordering focused-input fallbacks could affect targets where paste is blocked but Unicode events work. Keeping Unicode events as the final fallback preserves compatibility while making the common fallback faster.
