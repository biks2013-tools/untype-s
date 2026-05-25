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
last_scanned_commit: dbad6af8e529ccc9625cfb4744fec2ac96a5c0e9
scanned_for_request: refined-request-transcript-events-export-copy.md
scanned_at: 2026-05-25T04:42:15Z
---

# Codebase Scan — untype-s

## 1. Project Overview
`untype-s` is a Swift Package Manager project for macOS 14 with two executables and one shared core library. The package is Swift-only, with native UI code living in `UntypeCore` via SwiftUI and AppKit, while the executable targets are thin wrappers around that shared runtime.

The current repository already models transcript and event data in memory, and it already has a clipboard sink, but it does not yet expose user-facing transcript/event copy or save actions. The requested work therefore lands on the native UI and its formatting helpers rather than the provider/runtime pipeline.

## 2. Module Map
| Path | Purpose | Representative symbols |
| --- | --- | --- |
| `Sources/UntypeCore` | Shared runtime, native UI, timeline state, clipboard helper, and session plumbing for the app. | `NativeUntypeUILauncher`, `UntypeUIModel`, `UntypeUITimelineState` |
| `Sources/untype` | Thin executable entry point that dispatches `ui` into the native launcher and otherwise runs the CLI command path. | `UntypeExecutable.main`, `UntypeCommand` |
| `Sources/untype-input-helper` | Helper executable that reads stdin and drives the focused-input delivery path. | `main`, `FocusedInputHelperMain.run` |

Entry points:
- `Sources/untype/main.swift`
- `Sources/untype-input-helper/main.swift`

## 3. Conventions
- The native UI keeps its own observable model with explicit in-memory transcript and event stores. `UntypeUIModel` publishes `timeline` and bounded `events`, `handleTranscript` turns live transcript events into timeline state, and `appendEvent` deduplicates exact repeats while capping the log at 300 items. See `Sources/UntypeCore/NativeUntypeUILauncher.swift:161-167`, `Sources/UntypeCore/NativeUntypeUILauncher.swift:560-625`.
- The transcript reducer already carries the semantics needed for export, but not the formatting API itself. `UntypeUITimelineState` stores live partials, sealed turns, raw dictated text, processed output, and session issue bubbles with label/status/time fields; it only exposes state mutation and counting today. See `Sources/UntypeCore/UntypeUITimeline.swift:32-189`.
- The monitoring UI already separates Transcript and Events into tabs, but the controls are still limited to Clear and text selection. There are no copy/save buttons, no file picker, and no export helper in the current tab views. See `Sources/UntypeCore/NativeUntypeUILauncher.swift:746-830`.
- Clipboard delivery is already abstracted behind a small helper, which makes copy actions easy to wire without touching protocol code. `MacOSClipboardWriter` writes directly to `NSPasteboard.general` and throws a typed error when the pasteboard is unavailable. See `Sources/UntypeCore/MacOSClipboardWriter.swift:4-24`.
- The closest existing tests cover the reducer and the clipboard primitive, not user-facing export behavior. The timeline tests validate grouping and clearing semantics, and the clipboard helper test verifies injected copy routing, but neither covers save panels, export formatting, or UI button routing. See `Tests/UntypeCoreTests/UntypeUITimelineTests.swift:5-44` and `Tests/UntypeCoreTests/FocusedInputDeliveryTests.swift:102-115`.
- Project docs already describe the native UI tabs and the clearable grouped timeline, so the new feature should extend those docs rather than invent a new UI story. See `docs/design/project-design.md:144-157` and `docs/design/project-functions.md:14-19`.

## 4. Integration Points
### In-Scope
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:161-167, 560-625, 746-830` - owns the observable UI state, transcript/event routing, and current tab controls; add the user-facing `Copy` and `Save` actions here or very near this view/model boundary.
- `Sources/UntypeCore/UntypeUITimeline.swift:32-189` - canonical transcript timeline reducer; add export-format helpers here so copy/save output matches the visible grouping semantics.
- `Sources/UntypeCore/MacOSClipboardWriter.swift:4-24` - reusable clipboard primitive for the transcript/event copy action.
- `Tests/UntypeCoreTests/UntypeUITimelineTests.swift:5-44` - reducer coverage that should be extended with export-format assertions and empty-content behavior.
- `Tests/UntypeCoreTests/FocusedInputDeliveryTests.swift:102-115` - existing clipboard-helper test pattern that can be mirrored for copy routing or adapter injection.
- `docs/design/project-design.md:144-157` - existing native UI design notes that should record the new transcript/event export behavior.
- `docs/design/project-functions.md:14-19` - functional requirements ledger that should gain the new user-facing transcript/event copy/save requirements.

### Out-of-Scope
- `Sources/untype/main.swift:4-27` - CLI dispatch remains unchanged; the request is specifically about the native UI monitoring window.
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift:182-475` - audio capture, STT, and session submission are not part of transcript/event export.
- `Sources/UntypeCore/VoiceAgentProtocolController.swift:32-366` - protocol operator delivery is explicitly excluded by the request.
- `Sources/UntypeCore/FocusedInputDelivery.swift:1-345` - focused-input delivery is out of scope even though the clipboard helper it uses is reusable.
- `Sources/UntypeCore/TranscriptRenderer.swift:1-146` - CLI transcript rendering behavior is explicitly excluded.

### New Integration Points
- No dedicated export/copy landing site exists yet. The cleanest new seam is a small export/formatting helper adjacent to `UntypeUIModel` in `Sources/UntypeCore/NativeUntypeUILauncher.swift`, with serialization delegated to `UntypeUITimelineState` and file writes handled by a new save-panel-backed UI helper.
- If copy and save need to share exact formatting, a formatter/serializer API on `UntypeUITimelineState` is the likely new API surface because the state already contains the complete visible transcript semantics.

## 5. Notes
- This request is not already implemented end-to-end. The codebase already has the underlying transcript/event state and a clipboard primitive, but the visible UI still only offers Clear on the Transcript tab and no explicit export/save controls on either tab.
- I did not find any existing `NSSavePanel`, export helper, or file-based transcript/event persistence path, so save support will be new work rather than a reuse of an existing feature.
- The current design docs cover the tabbed monitor and the grouped timeline, so the main documentation delta is to record copy/save behavior and the export text contract.
