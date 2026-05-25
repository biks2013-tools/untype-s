# Plan 009: Remove Overlay Text Resizing

Refined request: `docs/reference/refined-request-remove-overlay-text-resizing.md`
Investigation: skipped - localized removal of existing overlay text-driven resizing behavior.
Technical research: skipped - no new technology or dependency introduced.
Codebase scan: skipped - continuation of the previously scanned overlay surface in `docs/reference/codebase-scan-overlay-position-wrap-correction.md`; affected files are fully localized.

## Objective
Remove text-length-driven overlay window resizing so the push-to-talk overlay keeps a fixed configured size while transcription text changes.

## Files To Modify
- `Sources/UntypeCore/UntypeOverlayLayout.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/UntypeOverlayLayoutTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Steps
1. Remove the overlay text-measurement and variable-height frame update code.
2. Make the overlay layout expose fixed-size initial framing only.
3. Stop visible overlay transcript updates from resizing or reframing the panel.
4. Replace growth-focused tests with fixed-size/stable-frame tests.
5. Update design, function, and issue documentation.
6. Run `swift test`.

## Acceptance Criteria
- Long transcript text does not increase overlay height.
- Text updates while the overlay is visible do not resize or reframe the panel.
- Initial overlay placement remains bottom-center with the configured fixed size.
- `swift test` passes.
