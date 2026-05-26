# Plan 020: Overlay Theme Alignment

## Provenance
- Refined request: `docs/reference/refined-request-overlay-theme-alignment.md`
- Investigation/research: skipped because the design system and overlay direction are already established in `docs/design/project-design.md`.
- Codebase scan: reused existing overlay surface knowledge from `docs/reference/codebase-scan-overlay-position-wrap-correction.md`; affected files are localized to the native UI overlay and design docs.

## Objective
Make the push-to-talk overlay look and behave as part of the same native UI theme as the main untype window.

## Implementation
1. Expose the main UI appearance setting to the overlay controller.
2. Refresh the overlay when layout/theme settings change.
3. Apply the overlay's preferred color scheme from the main app setting.
4. Restyle bottom operator indicators as compact, non-interactive versions of the main operator chips.
5. Restyle the phase indicator as a compact status pill.
6. Preserve overlay layout, wrapping, upward growth, non-activating behavior, and lifecycle.

## Files Modified
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- Overlay follows the main window appearance setting.
- Overlay operator indicators use the main app's amber/accent chip language.
- Overlay phase indicator uses the main app's status-pill language.
- No runtime, provider, protocol, or hotkey behavior changes.
- `swift build` succeeds.
- `swift test` passes.

## Verification
- `swift build` passed on 2026-05-26.
- `swift test` passed on 2026-05-26 with 130 tests passing.
- Manual live screenshot verification remains recommended because the overlay is a native macOS floating panel.
