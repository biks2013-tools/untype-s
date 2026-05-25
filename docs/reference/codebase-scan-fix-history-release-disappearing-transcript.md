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
last_scanned_commit: null
request_file: ~/aiwork/coding-platform/untype-s/docs/reference/refined-request-fix-history-release-disappearing-transcript.md
scan_scope: request-driven push-to-talk release timeline retention scan
generated_at: 2026-05-25T00:00:00+03:00
---

# Codebase Scan: Fix History Release Disappearing Transcript

## Metadata Notes
- Git commit detection was not run because project instructions prohibit version-control operations unless explicitly requested.
- The project remains a SwiftPM app/library with build command `swift build` and test command `swift test`.

## Relevant Module Map

### `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `UntypeUIModel.timeline` stores the retained in-memory transcript/history data.
- `startHotkeySession(...)` clears only live partial text before recording starts.
- `stopHotkeySession(...)` closes the audio gate, submits pending text, and sets `restartWarmSessionAfterStop`.
- `stopSession(...)` restarts the warm hotkey session after release when `restartWarmSessionAfterStop` is true.
- `startHotkeyWarmSession()` creates a new hotkey-owned runtime and calls `startSession(owner: .hotkey, audioGate: control)`.
- `startSession(...)` currently sets `timeline = UntypeUITimelineState()`, which wipes committed raw/processed turns each time a new runtime starts.
- `handleTranscript(...)` commits raw final text and processed output into the timeline.

### `Sources/UntypeCore/UntypeUITimeline.swift`
- `clear()` intentionally clears all retained visible transcript/history for explicit Clear.
- `clearPartial()` removes only live partial text and preserves committed turns.
- `conversationHistory` derives history from retained committed turns and live partial text.

## Integration Points

### In Scope
- `NativeUntypeUILauncher.startSession(...)`
  - Replace the full timeline reset with `timeline.clearPartial()` so warm-session restarts remove stale live partial text without deleting committed release output.
- `UntypeUITimelineTests.swift`
  - Add regression coverage that `clearPartial()` preserves committed raw/processed turns and derived history.
- Documentation and issue log
  - Record the defect and the fix.

### Out of Scope
- Runtime provider finalization logic.
- LLM refine/translate implementation.
- Persisting transcript/history content.

## Duplication Check
- The session history already exists as a derived view of `UntypeUITimelineState`.
- The fix should preserve this single source of truth and avoid adding another store.
