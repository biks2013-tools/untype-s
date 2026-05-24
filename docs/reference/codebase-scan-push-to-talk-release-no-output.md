---
language: Swift
framework: SwiftUI/AppKit
package_manager: swiftpm
build_command: "swift build"
test_command: "swift test"
lint_command: null
entry_points:
  - "Sources/untype/main.swift"
  - "Sources/untype-input-helper/main.swift"
last_scanned_commit: null
scanned_for_request: "refined-request-push-to-talk-release-no-output.md"
scanned_at: "2026-05-24T06:56:02Z"
---

# Codebase Scan - untype-s

## 1. Project Overview
`untype-s` is a macOS SwiftPM package with one shared core target and two executables: `untype` and `untype-input-helper`. The shared `UntypeCore` target holds the native UI launcher, transcript timeline reducer, session runtime, protocol controller, clipboard/input adapters, and provider/refinement plumbing. The request surface is concentrated in the native `untype ui` release path, where hotkey release should finalize the current turn, show monitor evidence, and route processed text to clipboard and focused input when enabled.

## 2. Module Map
| Path | Purpose | Representative symbols |
| --- | --- | --- |
| `Sources/UntypeCore` | Shared runtime and UI domain logic for STT capture, protocol submission, timeline rendering, hotkey handling, clipboard delivery, and focused-input insertion. | `NativeUntypeUILauncher`, `TranscriptionSessionRuntime`, `VoiceAgentProtocolController` |
| `Sources/untype` | CLI entry point that forwards `ui` into the native launcher and otherwise dispatches the command-line runner. | `UntypeExecutable.main` |
| `Sources/untype-input-helper` | Helper executable that reads processed text from stdin and delegates focused-input delivery through the native helper path. | `FocusedInputHelperMain.run`, `FocusedInputHelperMain.encodeResult` |
| `Tests/UntypeCoreTests` | Unit coverage for the release pipeline, protocol controller, timeline reducer, clipboard/input delivery, and native UI settings behavior. | `sessionRuntimeStopWithSubmitPendingWaitsForFinalAndDoesNotCancelBufferedText`, `protocolControllerProcessesSectionBeforeClipboardAndInputDelivery`, `focusedInputDeliverySendsTextOverStdinNotArguments` |

## 3. Conventions
- The app keeps the UI/runtime bridge narrow and explicit: `UntypeRuntimeFactory` builds the live runtime, injects the refiner, clipboard writer, focused-input sender, and event sink, and leaves side effects to those adapters. See `Sources/UntypeCore/UntypeRuntimeFactory.swift:92-152`.
- Push-to-talk uses a warm-session model rather than a one-shot dictation flow: press clears the live partial, opens the gate, and release closes the gate, submits pending audio, and starts a fresh warm session for the next press. See `Sources/UntypeCore/NativeUntypeUILauncher.swift:250-285` and `Sources/UntypeCore/TranscriptionSessionRuntime.swift:302-411`.
- The monitor is a reducer-backed timeline, not a direct log append. Raw, processed, and error bubbles are grouped by turn, and release/turn-boundary events seal turns instead of mutating transcript strings in place. See `Sources/UntypeCore/UntypeUITimeline.swift:32-121` and `Sources/UntypeCore/NativeUntypeUILauncher.swift:553-579`.
- Clipboard and focused-input delivery are isolated adapters with typed failure modes. Clipboard uses `NSPasteboard.general`, while focused input goes through a sibling helper process and passes the payload over stdin rather than command-line arguments. See `Sources/UntypeCore/MacOSClipboardWriter.swift:4-24`, `Sources/UntypeCore/FocusedInputDelivery.swift:157-193`, and `Sources/UntypeCore/FocusedInputDelivery.swift:265-345`.
- Failure handling is intentionally fail-open for refinement and translation, but input problems are surfaced as privacy-safe warnings. The controller warns on missing refiners, logs clipboard/input processing order, and preserves the section submission even if downstream operators fail. See `Sources/UntypeCore/VoiceAgentProtocolController.swift:223-293`.
- Tests are small, injected, and unit-level. Runtime submission, protocol ordering, and focused-input transport are all covered with fake audio/transcriber/delivery collaborators rather than live macOS automation. See `Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift:13-183`, `Tests/UntypeCoreTests/ProtocolControllerTests.swift:71-143`, and `Tests/UntypeCoreTests/FocusedInputDeliveryTests.swift:5-115`.

## 4. Integration Points
### In-Scope
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:250-285, 319-433, 553-603, 942-959, 1249-1523` - press/release handling, warm-session recycling, UI button fallback, monitor/event-log updates, and hotkey routing. This is the main landing zone if release looks inactive.
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift:207-411` - audio start/stop, pending submission, final-text waiting, and shutdown orchestration. This is where release turns into provider commit and session submission.
- `Sources/UntypeCore/VoiceAgentProtocolController.swift:188-293` - section processing order for raw output, refinement, translation, clipboard copy, and focused-input insertion, plus runtime diagnostics.
- `Sources/UntypeCore/UntypeRuntimeFactory.swift:92-152` - UI runtime assembly that wires the controller to `MacOSClipboardWriter`, `FocusedInputDelivery`, the STT adapter, and the UI event sink.
- `Sources/UntypeCore/UntypeUITimeline.swift:32-121` - monitor/timeline reducer for raw, processed, and error evidence.
- `Sources/UntypeCore/MacOSClipboardWriter.swift:4-24` - macOS clipboard write path.
- `Sources/UntypeCore/FocusedInputDelivery.swift:157-193, 265-345` and `Sources/UntypeCore/FocusedInputHelper.swift:40-205, 221-345` - focused-input delivery, helper invocation, permission checks, and privacy-safe delivery diagnostics.
- `Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift:79-183`, `Tests/UntypeCoreTests/ProtocolControllerTests.swift:71-143`, `Tests/UntypeCoreTests/FocusedInputDeliveryTests.swift:30-115`, `Tests/UntypeCoreTests/UntypeUITimelineTests.swift:4-45` - existing regression coverage around the same pipeline.

### Out-of-Scope
- `Sources/untype/main.swift:1-29` - CLI dispatcher; the reported defect is in the native UI release flow, not the command-line entry point.
- `Sources/UntypeCore/ConfigResolver.swift`, `EnvChain.swift`, `UntypeCommand.swift`, and `UntypeUISettings.swift` - the refined request explicitly excludes configuration precedence, fallback values, and missing-config behavior.

### New Integration Points
- None identified. The current tree already has the UI/runtime bridge, monitor reducer, clipboard writer, and focused-input helper that the request needs.

## 5. Notes
- This looks like a duplicate or regression of already-implemented behavior rather than a missing subsystem. The source tree already contains the release-to-output chain, and `Issues - Pending Items.md` has a completed 2026-05-24 entry for the same symptom cluster.
- The weakest observability branch is clipboard failure reporting: `VoiceAgentProtocolController.logOperatorFailure` only writes diagnostics when `verbose` is enabled, while input failures always emit a warning. That means a clipboard-only failure can still look like "nothing happened" even though the rest of the pipeline ran.
- I did not find a direct unit test for the native `startHotkeySession` / `stopHotkeySession` pair itself. Current coverage is strong at the runtime and adapter layers, but the AppKit/UI release handler remains indirectly tested.
