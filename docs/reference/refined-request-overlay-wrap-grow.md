# Refined Request: Overlay Wrap And Grow

## Category
Development

## Objective
Update the native push-to-talk overlay so long transcript text wraps within the overlay width and the overlay window grows upward to fit the wrapped lines instead of clipping or truncating the text.

## Scope
- **In scope**: Modify the native SwiftUI/AppKit overlay used by `untype ui`.
- **In scope**: Allow overlay transcript text to wrap onto multiple lines when it exceeds the overlay width.
- **In scope**: Resize the overlay `NSPanel` vertically to fit wrapped text.
- **In scope**: Keep the overlay's bottom placement stable so additional height grows upward from the bottom-center position.
- **In scope**: Preserve the existing overlay phase indicator, operator indicators, non-activating behavior, pointer-screen positioning, and hide/clear lifecycle.
- **In scope**: Add focused automated coverage for the layout sizing calculation where practical.
- **Out of scope**: Changing transcription, provider behavior, push-to-talk state handling, hotkey detection, session lifecycle, or the main transcript/events tabs.

## Requirements
1. Overlay text MUST wrap when it exceeds the available text width.
2. Overlay text MUST NOT be limited to a fixed number of lines.
3. The overlay panel height MUST increase to fit the wrapped text.
4. The overlay panel width SHOULD remain stable so the overlay does not grow horizontally across the screen.
5. The overlay MUST keep its bottom edge near the existing bottom-center screen position while height increases upward.
6. Empty overlay text MUST still render a compact minimum-height panel.
7. Existing overlay phase and operator indicator UI MUST remain visible and aligned.
8. The implementation MUST avoid new runtime dependencies.

## Constraints
- The overlay is implemented in `Sources/UntypeCore/NativeUntypeUILauncher.swift` as an AppKit `NSPanel` hosting a SwiftUI `UntypeOverlayView`.
- The existing overlay uses a fixed panel size and a three-line cap on transcript text.
- The project targets macOS 14 through Swift Package Manager.
- No version-control operation may be performed unless explicitly requested.

## Acceptance Criteria
1. Long overlay transcript text wraps inside the overlay instead of being truncated after a fixed line count.
2. The overlay panel grows taller as wrapped text needs more lines.
3. The overlay bottom edge remains anchored near the existing bottom-center location while extra height extends upward.
4. Short or empty overlay text still uses a compact panel height.
5. Existing overlay phase label and `R`/`T`/`C`/`I` indicators remain visible.
6. `swift test` passes.

## Assumptions
- A fixed overlay width remains desirable for visual stability.
- Plain SwiftUI text wrapping plus an AppKit height calculation is sufficient; no custom text layout engine is needed.
- A practical maximum height may be constrained by the visible screen if text becomes extremely long.

## Open Questions
- Should extremely long overlay text be scrollable instead of constrained to the visible screen height in a future iteration?

## Original Request
"I also want, in the overlay that is being drawn, if the line exceeds the width of the window, for it to start wrapping to the next line. I also want the window to grow upwards so that it can fit the text inside, wrapped into lines, one under the other."
