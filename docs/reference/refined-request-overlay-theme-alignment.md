# Refined Request: Overlay Theme Alignment

## Category
Development / Design

## Objective
Align the push-to-talk overlay visual treatment with the current main native app theme so it feels like the same UI system rather than a separate floating surface.

## Scope
- In scope: Update the existing SwiftUI/AppKit overlay used by `untype ui`.
- In scope: Reuse the existing `UntypeDesignTokens`, material surfaces, status colors, chip styling, and light/dark appearance behavior already used by the main app.
- In scope: Keep the overlay's non-activating `NSPanel`, status-bar level, pointer-screen placement, text wrapping, upward growth, bottom-row operator indicators, and delayed hide behavior.
- Out of scope: New dependencies, new configuration settings, changes to transcription/runtime behavior, changes to overlay geometry beyond visual padding needed for the existing layout.

## Requirements
1. The overlay MUST respect the same appearance setting as the main window (`system`, `light`, or `dark`).
2. The overlay MUST use the app's existing amber, recording red, secondary text, and native material design tokens.
3. The `R`/`T`/`C`/`I` operator indicators MUST visually align with the main app's operator-chip language.
4. The phase indicator MUST visually align with the main app's status-pill language.
5. The overlay MUST preserve the existing fixed-width and upward-growing wrapped transcript behavior.
6. The implementation MUST stay inside the existing SwiftUI/AppKit overlay architecture.

## Constraints
- Do not add runtime dependencies.
- Do not persist transcript text or overlay-only visual state.
- Do not change provider, hotkey, or protocol behavior.

## Acceptance Criteria
1. Changing the main app appearance setting also changes the overlay's color scheme.
2. The overlay uses the same warm amber and recording-red accents as the main UI.
3. Enabled/disabled operator indicators read like compact versions of the main operator chips.
4. The phase indicator reads like a compact status pill.
5. `swift build` succeeds.
6. `swift test` passes.

## Assumptions
- "Align the overlay theme" means visual consistency with the current SwiftUI main app, not a full redesign or new overlay interaction model.
- Manual live screenshot verification remains useful after this change because the overlay is a native macOS floating panel.

## Open Questions
- None blocking.

## Original Request
"can you align the overlay theme with the main app theme ?"
