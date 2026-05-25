# Refined Request: Overlay Position And Wrapping Correction

## Category
Development

## Objective
Correct the native push-to-talk overlay behavior so live transcription text wraps when it exceeds the overlay width and the overlay expands upward to contain additional wrapped lines, without causing the overlay window to slide downward or otherwise drift while transcription text updates.

## Scope
- **In scope**: Correct the existing SwiftUI/AppKit push-to-talk overlay behavior used by `untype ui`.
- **In scope**: Remove or revise the recent behavior that moves the overlay window downward while transcription is active.
- **In scope**: Preserve a stable overlay bottom anchor while the overlay is visible, so text growth adds space upward rather than repositioning the window downward.
- **In scope**: Wrap overlay transcript text onto new lines only when the text exceeds the available overlay text width.
- **In scope**: Increase the overlay height as needed to contain wrapped text while keeping the overlay width stable.
- **In scope**: Add or update focused regression coverage for overlay frame anchoring, wrapping, and upward growth.
- **In scope**: Update project documentation and pending/completed issue notes required by the project conventions for an issue fix.
- **Out of scope**: Changing speech transcription provider behavior, hotkey press/release handling, push-to-talk session lifecycle, operator processing, main transcript/events tabs, or clipboard/focused-input delivery.
- **Out of scope**: Performing a version-control revert, reset, checkout, or other VCS operation.

## Requirements
1. The overlay MUST NOT slide downward, drift, or be re-centered on each transcription update while it is visible.
2. The overlay MUST retain a stable bottom anchor for the duration of a visible overlay session.
3. When updated transcript text still fits within the current overlay height, the overlay frame MUST remain unchanged.
4. When transcript text requires additional wrapped lines, the overlay height MUST increase upward from the stable bottom anchor.
5. Overlay transcript text MUST wrap to a new line when it exceeds the available text width.
6. Overlay transcript text MUST NOT be truncated by a fixed line cap when additional vertical space is available.
7. The overlay width SHOULD remain stable during transcription updates.
8. Short or empty overlay text MUST continue to use a compact overlay height.
9. Existing overlay phase display, `R`/`T`/`C`/`I` operator indicators, non-activating panel behavior, screen selection, and hide/clear lifecycle MUST remain unchanged.
10. The implementation MUST use the existing SwiftUI/AppKit overlay architecture and MUST NOT add new runtime dependencies.
11. Regression tests MUST demonstrate that overlay growth preserves the bottom anchor and does not introduce downward movement during transcript updates.

## Constraints
- The project is a Swift Package Manager macOS 14 project.
- The native UI overlay is documented as a bottom-center non-activating `NSPanel` that wraps long transcript text within a stable panel width and grows upward from a stored anchor.
- Existing related artifacts include `docs/reference/refined-request-overlay-wrap-grow.md` and `docs/design/plan-007-overlay-wrap-grow.md`; this request is a corrective follow-up to that work, not a replacement for the original user intent.
- Project rules require issue fixes to be documented, with relevant updates in `docs/design/project-design.md`, `docs/design/project-functions.md`, `Issues - Pending Items.md`, and smoke-test documentation when behavior changes.
- No version-control operation may be performed unless explicitly requested by the user.
- Missing configuration values must continue to raise errors; this request must not introduce configuration fallbacks.

## Acceptance Criteria
1. During push-to-talk transcription, repeated transcript updates do not move the overlay downward or change its position unless additional height is required.
2. When additional height is required, the overlay grows upward and its bottom edge remains visually anchored.
3. Text that exceeds the overlay text width wraps onto additional lines inside the overlay.
4. Wrapped text remains visible within the overlay without relying on a fixed maximum line count for normal overlay content.
5. Existing phase and operator indicators remain visible and aligned after resizing.
6. Focused automated tests cover stable-frame updates and upward-only growth from the stored bottom anchor.
7. `swift test` passes.
8. Project documentation and issue notes reflect the corrected behavior and the fact that the downward sliding defect was fixed.

## Assumptions
- "Revert the changes" means revise the affected overlay-positioning code to restore the intended behavior, not perform a Git or other version-control revert.
- The desired visible invariant is that the overlay's bottom edge stays fixed while the top edge moves upward only when more wrapped text must fit.
- Existing overlay styling, compact typography, operator indicators, and status-bar-level non-activating panel behavior remain acceptable and should be preserved.
- Extremely long transcript text may still be constrained by the visible screen area; defining scrolling behavior for extreme content is outside this corrective request.

## Open Questions
None.

## Original Request
"You have make the overlay window slidding downwards while you are transcribing, which is an error.
I just asked you to examine whether the transcribed text length exceeds the width of the overlay.
In that case, I asked you to wrap the text, adding a new line.
And to, uh, extend the overlay window upwards, to make it, uh, capable of containing the text.
So I want you to revert the changes that, affect the position of the window while transcribing.
And instead Implement correctly my request."
