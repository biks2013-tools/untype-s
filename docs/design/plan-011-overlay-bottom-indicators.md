# Plan 011: Overlay Bottom Indicators

Refined request: `docs/reference/refined-request-overlay-bottom-indicators.md`
Investigation: skipped - localized SwiftUI/AppKit overlay layout adjustment with no approach or dependency choice.
Technical research: skipped - no new framework, API, or external library is introduced.
Codebase scan: reused `docs/reference/codebase-scan-overlay-position-wrap-correction.md` because it already maps the current overlay controller, view, layout helper, and focused tests for this same UI surface.

## Objective
Move the overlay protocol operator indicators to a fixed bottom row and place the recording/phase indicator at the bottom right on that same row, while preserving transcript wrapping and upward panel growth.

## Files To Modify
- `Sources/UntypeCore/UntypeOverlayLayout.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/UntypeOverlayLayoutTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Steps
1. Replace the overlay view's header/body/footer stack with fixed top transcript and bottom indicator regions.
2. Anchor the operator row 5 px above the overlay bottom.
3. Anchor the phase indicator to the bottom right on the same vertical row.
4. Reserve bottom-row height in overlay text measurement so wrapped transcript text does not overlap the indicators.
5. Update focused layout tests for the revised bottom-row reserved space.
6. Update project design, functional requirements history, and issue notes.
7. Run `swift test`.

## Acceptance Criteria
- Operator indicators are aligned in a bottom row with bottom edges 5 px above the overlay bottom.
- The phase/recording indicator is bottom-right aligned on the same row.
- Wrapped transcript text remains above the bottom indicator row.
- Existing overlay upward growth behavior remains intact.
- `swift test` passes.
