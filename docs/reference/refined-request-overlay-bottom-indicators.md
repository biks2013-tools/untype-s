# Refined Request: Overlay Bottom Indicators

## Category
Development

## Objective
Adjust the native push-to-talk overlay layout so protocol operator indicators sit along the bottom of the overlay and the recording/phase indicator sits at the bottom right on the same vertical line.

## Scope
- **In scope**: Modify the existing SwiftUI/AppKit overlay view used by `untype ui`.
- **In scope**: Move the Refine, Translate, Clipboard, and Input operator indicators to the overlay bottom edge area.
- **In scope**: Align the bottom side of the operator indicators 5 px above the bottom of the overlay.
- **In scope**: Move the recording/phase indicator to the bottom right, aligned vertically with the operator indicators.
- **In scope**: Preserve multiline transcript wrapping and upward overlay growth from the existing overlay layout.
- **In scope**: Update focused tests and required project documentation for the UI behavior change.
- **Out of scope**: Changing transcription providers, runtime session handling, hotkey behavior, operator semantics, or main monitoring-window layout.

## Requirements
1. The Refine, Translate, Clipboard, and Input indicators MUST render in the bottom row of the overlay.
2. The bottom edge of those operator indicators MUST be 5 px above the bottom edge of the overlay.
3. The recording/phase indicator MUST render at the bottom right of the overlay.
4. The recording/phase indicator MUST share the same vertical row as the operator indicators.
5. The recording/phase indicator's right side SHOULD align with the overlay's right side while remaining visible and unclipped.
6. Transcript text MUST remain multiline and MUST NOT overlap the bottom indicator row.
7. Existing stable-width, upward-growth overlay behavior MUST remain intact.
8. The implementation MUST use the existing SwiftUI/AppKit overlay architecture and MUST NOT add runtime dependencies.

## Constraints
- The project is a Swift Package Manager macOS 14 project.
- The relevant code path is the existing `UntypeOverlayController`, `UntypeOverlayView`, and `UntypeOverlayLayout` surface identified in `docs/reference/codebase-scan-overlay-position-wrap-correction.md`.
- Missing configuration behavior must remain strict; this request must not introduce configuration fallbacks.
- No version-control operation may be performed unless explicitly requested.

## Acceptance Criteria
1. The four operator indicators are visibly anchored to the overlay bottom row.
2. The operator indicators' bottom edges are 5 px above the overlay bottom.
3. The recording/phase indicator is positioned at the bottom right on the same vertical baseline as the operator indicators.
4. Wrapped transcript text remains visible above the bottom indicator row.
5. Overlay width, wrapping, and upward growth behavior continue to pass focused tests.
6. `swift test` passes.

## Assumptions
- The user's phrase "Clipboard Input indicators" refers to the existing two indicators for Clipboard and Input, alongside Refine and Translate.
- The existing compact letter indicators (`R`, `T`, `C`, `I`) remain acceptable; the request changes placement, not labels or operator behavior.
- "Recording indicator" refers to the existing phase indicator consisting of the colored status dot and uppercase phase text.

## Open Questions
None.

## Original Request
"I want you to make the following adjustments in the overlay window. Move the “Refine,” “Translate,” and “Clipboard Input” indicators to the bottom of the overlay, aligned their bottom side 5px above the bottom of the overlay. 
Then move the recording indicator to the bottom right of the overlay, aligned its right side to the right side of the overlay and at the same vertical height as the Refine, Translate, Clipboard, and Input indicators."
