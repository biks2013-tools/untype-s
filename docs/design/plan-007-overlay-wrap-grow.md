# Plan 007: Overlay Wrap And Grow

Refined request: `docs/reference/refined-request-overlay-wrap-grow.md`
Investigation: skipped - localized SwiftUI/AppKit overlay layout change using existing platform APIs.
Technical research: skipped - no new technology or dependency introduced.
Codebase scan: skipped - overlay implementation is already localized in `Sources/UntypeCore/NativeUntypeUILauncher.swift`.

## Objective
Make the push-to-talk overlay wrap long transcript text and grow upward from its bottom-center screen position so the wrapped lines remain visible.

## Files To Modify
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Sources/UntypeCore/UntypeOverlayLayout.swift`
- `Tests/UntypeCoreTests/UntypeOverlayLayoutTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`
- `test_scripts/ui-mode-smoke.md`

## Steps
1. Add a small overlay layout calculator for fixed-width variable-height panel sizing.
2. Resize the `NSPanel` content height whenever overlay text or operator display changes.
3. Keep the overlay bottom edge anchored while changing height, so the panel grows upward.
4. Remove the SwiftUI text line cap and allow vertical wrapping.
5. Add focused tests for minimum height and increased height with long wrapped text.
6. Update design/function/smoke documentation.
7. Run `swift test`.

## Acceptance Criteria
- Long overlay text wraps instead of truncating at a fixed line count.
- Panel height increases for wrapped multiline text.
- Panel width remains stable.
- The panel remains bottom-centered and grows upward.
- Short/empty overlay content remains compact.
- `swift test` passes.
