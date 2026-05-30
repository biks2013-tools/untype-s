---
language: Swift
framework: SwiftUI/AppKit
package_manager: Swift Package Manager
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/UntypeCore/NativeUntypeUILauncher.swift
last_scanned_commit: 0659ce1eab6e2134651bf85bd23aea6d8c287237
scanned_for_request: refined-request-turn-level-copy-buttons
scanned_at: 2026-05-30T11:23:43Z
---

# Codebase Scan: Turn-Level Copy Buttons

## Request
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-turn-level-copy-buttons.md`
- Goal: add per-turn copy buttons for raw dictated text and processed output in the native UI.

## Project Overview
`untype-s` is a Swift Package Manager project. It exposes the `untype` executable, the `untype-input-helper` executable, and the `UntypeCore` library. The native UI is implemented in SwiftUI/AppKit under `Sources/UntypeCore/NativeUntypeUILauncher.swift` and uses in-memory timeline models from `Sources/UntypeCore/UntypeUITimeline.swift`.

## Module Map
- `Sources/UntypeCore/NativeUntypeUILauncher.swift` — native SwiftUI/AppKit UI, model actions, transcript/history/events panes, and existing export copy/save routing.
- `Sources/UntypeCore/UntypeUITimeline.swift` — in-memory transcript turn, bubble, live partial, and derived conversation-history data model.
- `Sources/UntypeCore/UntypeUIExport.swift` — existing transcript/events export document and testable copy/save action router.
- `Sources/UntypeCore/MacOSClipboardWriter.swift` — existing macOS pasteboard writer used by runtime clipboard delivery and UI export copy.
- `Tests/UntypeCoreTests/UntypeUITimelineTests.swift` — focused timeline model tests.
- `Tests/UntypeCoreTests/UntypeUIExportTests.swift` — focused export router tests.

## Conventions
- Use SwiftUI views in `NativeUntypeUILauncher.swift` for UI-only controls and keep runtime transcript state in `UntypeUITimelineState`.
- Use explicit user-triggered copy/save actions only; do not persist transcript, processed output, or event content automatically.
- Reuse `MacOSClipboardWriter.writeToSystemPasteboard` for macOS pasteboard writes.
- Keep tests in `Tests/UntypeCoreTests/` and verify through `swift test`.
- Use only Apple/Swift standard libraries and frameworks for this UI change; no new dependency is needed.

## Integration Points

### In Scope
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
  - `UntypeUIModel.copyTranscriptExport()` and `copyExport(_:)` show the existing copy routing for whole-document export.
  - `UntypeRootView.transcriptPane` renders committed timeline turns through `timelineTurnView(_:)`.
  - `timelineBubbleView(_:)` renders each raw, processed, and error bubble. This is the right place to add per-bubble copy controls for the Transcript tab.
  - `historyPane` renders derived history turns through `conversationHistoryTurnView(_:)`.
  - `conversationHistorySection(...)` renders each History raw/output/issue section. This is the right place to add per-section copy controls for the History tab.

### Partially Implemented / Reusable
- `Sources/UntypeCore/MacOSClipboardWriter.swift`
  - Already provides `writeToSystemPasteboard(_:)`, which clears and writes plain string content to `NSPasteboard.general`.
- `Sources/UntypeCore/UntypeUITimeline.swift`
  - Already keeps raw and processed text separate through `UntypeUITimelineBubble.kind` and the derived `conversationHistory` records.

### Out of Scope
- Provider/runtime code in `Sources/UntypeCore/TranscriptionSessionRuntime.swift`, `UntypeRuntimeFactory.swift`, `VoiceAgentProtocolController.swift`, `SonioxTranscriber.swift`, and `ElevenLabsTranscriber.swift`.
- Existing whole-transcript and event export format in `UntypeUIExport.swift`, except where tests may reuse copy behavior.
- Focused-input helper and delivery code.

## Duplication Check
The UI already has whole-transcript and whole-event copy actions, but no per-turn raw or processed copy controls. The requested feature is not already implemented. It should extend the existing native UI surfaces and pasteboard writer, not add a parallel clipboard abstraction.

## Recommended Build/Test Commands
- `swift build`
- `swift test`
