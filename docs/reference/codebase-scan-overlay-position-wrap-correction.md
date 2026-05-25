---
language: Swift
framework: AppKit + SwiftUI
package_manager: swiftpm
build_command: "swift build"
test_command: "swift test"
lint_command: null
entry_points:
  - "Sources/untype/main.swift"
  - "Sources/untype-input-helper/main.swift"
last_scanned_commit: 27a9633473d1bce257a6e95c07a5fd3fbd9b3b4a
scanned_for_request: refined-request-overlay-position-wrap-correction.md
scanned_at: 2026-05-25T05:18:45Z
---

# Codebase Scan - untype-s

## 1. Project Overview
`untype-s` is a Swift Package Manager macOS 14 project with one shared library target, `UntypeCore`, and two executable targets, `untype` and `untype-input-helper`.

For this request, the important surface is the native overlay path inside `UntypeCore`: an AppKit `NSPanel` hosted by SwiftUI, a fixed-width overlay layout helper, and focused tests around frame anchoring and wrapping.

The rest of the package is adjacent runtime infrastructure for transcription, protocol handling, clipboard/focused-input delivery, and CLI startup, but those areas are not the primary landing site for the overlay-position correction.

## 2. Module Map
| Path | Purpose | Representative symbols |
| --- | --- | --- |
| `Sources/UntypeCore` | Shared runtime library target containing configuration, transcription, protocol, UI state, overlay layout, and the native UI launcher. | `UntypeOverlayLayout`, `UntypeOverlayController`, `UntypeUITimelineState` |
| `Sources/untype` | Main executable entry point that switches to native UI mode or runs the shared CLI command path. | `UntypeExecutable.main`, `UntypeCommand`, `NativeUntypeUILauncher.launchBlockingOnCurrentThread` |
| `Sources/untype-input-helper` | Sibling helper executable used by the focused-input delivery path. | `FocusedInputHelperMain.run`, `FocusedInputHelperMain.parseCommand`, `FocusedInputHelperMain.encodeResult` |

## 3. Conventions
- Small entry points delegate quickly into shared modules, while platform-specific behavior stays in `UntypeCore` as focused types. The native launcher splits bootstrap, AppKit delegate, overlay controller, and overlay view into separate declarations. See `Sources/UntypeCore/NativeUntypeUILauncher.swift:8-56` and `Sources/UntypeCore/NativeUntypeUILauncher.swift:1270-1430`.
- Error handling is typed at the boundary and converted into exit codes or diagnostics instead of being allowed to escape uncategorized. `UntypeCommand` catches `UntypeError`, writes the diagnostic line to stderr, and maps the failure to an `ExitCode`. See `Sources/UntypeCore/UntypeCommand.swift:44-92`.
- Configuration resolution is explicit and injected. `ConfigResolver` receives the current directory, home directory, environment, and clock time, then resolves flags and env values without mutating global state. See `Sources/UntypeCore/ConfigResolver.swift:3-43` and `Sources/UntypeCore/ConfigResolver.swift:45-180`.
- Overlay sizing uses fixed-width text measurement rather than custom drawing logic. The layout helper measures a monospaced attributed string with word wrapping, while the SwiftUI view uses `.lineLimit(nil)` and `.fixedSize(horizontal: false, vertical: true)` so the transcript can expand vertically. See `Sources/UntypeCore/UntypeOverlayLayout.swift:44-111` and `Sources/UntypeCore/NativeUntypeUILauncher.swift:1398-1430`.
- Regression coverage is written with Swift Testing value assertions. The overlay layout tests cover empty content, wrapped growth, bottom anchoring, stable resize behavior, and stored-anchor frame construction. See `Tests/UntypeCoreTests/UntypeOverlayLayoutTests.swift:5-59`.

## 4. Integration Points
### In-Scope
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:254-289, 634-659` - hotkey and transcript event handlers push phase and text into the overlay; repeated transcript updates flow through these call sites before the panel is re-framed.
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:1270-1430` - `UntypeOverlayController` and `UntypeOverlayView` own the `NSPanel`, stored bottom-left anchor, visible text rendering, and the current frame-update policy. This is the primary fix site for the downward-sliding regression.
- `Sources/UntypeCore/UntypeOverlayLayout.swift:4-112` - computes overlay width, minimum height, wrapped text height, initial placement, and anchored resize behavior. This helper is the geometry seam that should keep width stable and growth upward only.
- `Tests/UntypeCoreTests/UntypeOverlayLayoutTests.swift:5-59` - existing focused regression tests for empty content, wrapping growth, stable anchoring, and resize semantics. Extend here if the fix needs to prove the panel does not drift downward during successive transcript updates.

### Out-of-Scope
- `Sources/UntypeCore/SonioxTranscriber.swift` and `Sources/UntypeCore/ElevenLabsTranscriber.swift` - provider adapters only affect incoming transcript content, not overlay frame geometry.
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift` and `Sources/UntypeCore/VoiceAgentProtocolController.swift` - runtime/protocol processing is adjacent, but not the place where overlay anchoring or wrapping is decided.
- `Sources/UntypeCore/FocusedInputDelivery.swift` and `Sources/UntypeCore/MacOSClipboardWriter.swift` - downstream text delivery paths are not part of the overlay-positioning bug.

### New Integration Points
- None identified. The request fits the existing overlay controller/layout seam and should not require a new module or dependency.

## 5. Notes
- The requested behavior is already largely embodied in the current code: `UntypeOverlayLayout` measures wrapped text height, and `UntypeOverlayController` stores a `bottomLeftAnchor` and only re-frames the visible panel when height or width changes. If the defect still reproduces, the bug is likely in the repeated-update path rather than in the layout math itself.
- There is no dedicated controller-level test for repeated transcript updates; current regression coverage is pure layout math.
- `docs/design/project-functions.md` already records the earlier overlay wrap/grow work, so this request reads as a corrective follow-up rather than a new feature area.
