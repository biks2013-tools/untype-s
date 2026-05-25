# Plan 010: Overlay Text Wrap Restoration

Refined request: `docs/reference/refined-request-overlay-position-wrap-correction.md`
Investigation: skipped - localized correction to the existing SwiftUI/AppKit overlay behavior; no approach or dependency choice is required.
Technical research: skipped - no new technology, framework, or external API is introduced.
Codebase scan: `docs/reference/codebase-scan-overlay-position-wrap-correction.md`

## Objective
Restore the push-to-talk overlay behavior so transcribed text wraps to additional visible lines when it exceeds the overlay text width, and the overlay grows upward from a stable bottom anchor instead of truncating the text or moving downward.

## Files To Modify
- `Sources/UntypeCore/UntypeOverlayLayout.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/UntypeOverlayLayoutTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Steps
1. Restore text-aware overlay height calculation in `UntypeOverlayLayout`.
2. Render overlay transcript text as multiline SwiftUI text within the stable overlay width.
3. Reframe the visible panel only when wrapped text requires more height, using the stored bottom-left anchor.
4. Preserve the panel frame for shorter visible text after the overlay has already expanded.
5. Add regression tests for compact text, wrapped growth, anchored upward expansion, and no shrink on shorter updates.
6. Update design, function, and issue documentation.
7. Run `swift test`.

## Acceptance Criteria
- Long transcribed overlay text wraps instead of being tail-truncated.
- Additional wrapped lines increase the overlay height while preserving the bottom edge.
- The overlay width remains stable while text changes.
- Short overlay text keeps the compact configured height.
- Existing phase and operator indicators remain in the overlay.
- `swift test` passes.
