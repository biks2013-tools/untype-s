# Plan 008: Overlay Position Wrap Correction

Refined request: `docs/reference/refined-request-overlay-position-wrap-correction.md`
Investigation: skipped - localized correction to the existing SwiftUI/AppKit overlay behavior; no approach or dependency choice is required.
Technical research: skipped - no new technology, framework, or external API is introduced.
Codebase scan: `docs/reference/codebase-scan-overlay-position-wrap-correction.md`

## Objective
Correct the push-to-talk overlay so transcription updates wrap long text and grow the panel upward from the original bottom-left anchor without sliding or re-centering the window while recording.

## Files To Modify
- `Sources/UntypeCore/UntypeOverlayLayout.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/UntypeOverlayLayoutTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Steps
1. Make visible overlay frame updates use an explicit stored-anchor layout result.
2. Preserve the initial bottom-left anchor for all visible updates, including repeated transcript updates and defensive drift correction.
3. Keep the panel frame unchanged when updated text still fits the current height.
4. Grow height only when wrapped text requires more vertical space, using the stored anchor so the bottom edge remains fixed.
5. Add focused regression tests for same-height updates, upward growth, and restoring a drifted frame back to the stored anchor.
6. Update design/function/issue documentation.
7. Run `swift test`.

## Acceptance Criteria
- The overlay does not move downward or re-center during repeated transcription updates.
- Wrapped text increases panel height only when needed.
- Height growth preserves the overlay bottom edge and adds space upward.
- Existing overlay phase and operator rendering behavior is unchanged.
- `swift test` passes.
