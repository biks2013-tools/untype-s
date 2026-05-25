# Plan 015: Untype High CPU and Focused Typing Lag

## References
- Refined request: `docs/reference/refined-request-untype-high-cpu-typing-lag.md`
- Codebase scan: `docs/reference/codebase-scan-untype-high-cpu-typing-lag.md`
- Investigation: skipped; localized existing Swift implementation bug, no competing approach.
- Technical research: skipped; no new technology introduced.

## Problem
The native UI can do too much work while a session is active:
- Audio activity events arrive for every microphone buffer and currently update `@Published audioStatus` on every event, causing frequent SwiftUI invalidations.
- Closed push-to-talk warm sessions allocate silence and inspect audio activity for every buffer even while idle.
- Focused-input auto delivery falls back to per-character Unicode keyboard events for up to 500 UTF-16 units before using paste-keycode, which can lag badly in browser/editor fields and drive CPU in both `untype` and the target app.

## Files to Modify
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift`
  - Add light throttling for audio activity event emission while still emitting category changes promptly.
  - Avoid full `Data` equality checks for muted-gate detection.
- `Sources/UntypeCore/FocusedInputHelper.swift`
  - Reorder auto fallback from `AX -> Unicode -> Paste` to `AX -> Paste -> Unicode`.
- `Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift`
  - Add/adjust focused coverage for audio activity throttling and category-change emission.
- `Tests/UntypeCoreTests/FocusedInputDeliveryTests.swift`
  - Add coverage documenting the auto focused-input fallback order where possible without live Accessibility.
- `Issues - Pending Items.md`
  - Document the issue and resolution.
- `docs/design/project-design.md`
  - Record the performance design adjustment.
- `docs/design/project-functions.md`
  - Register the performance/operability behavior change.

## Acceptance Checks
- `swift test`
- Manual verification remains recommended for live macOS Accessibility/Input Monitoring and focused input because automated tests cannot safely type into real applications.
