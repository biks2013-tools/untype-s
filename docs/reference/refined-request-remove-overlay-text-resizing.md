# Refined Request: Remove Overlay Text-Based Resizing

## Category
Development

## Objective
Remove the behavior that changes the push-to-talk overlay window size based on transcribed text length, wrapping, or growth, so the overlay keeps a fixed window size while transcription text updates.

## Scope
- **In scope**: Remove code that measures transcript text height to change the overlay `NSPanel` size.
- **In scope**: Remove visible-update frame resizing logic tied to transcript growth.
- **In scope**: Keep the overlay positioned consistently when it is shown and while text updates.
- **In scope**: Update regression tests so they assert fixed overlay sizing rather than growth from wrapped text.
- **In scope**: Update required design/function/issue documentation for the behavior change.
- **Out of scope**: Changing transcription provider behavior, push-to-talk lifecycle, hotkey handling, operator indicators, main transcript/event tabs, clipboard delivery, or focused-input delivery.
- **Out of scope**: Performing version-control revert/reset/checkout operations.

## Requirements
1. The overlay window MUST NOT change height because transcribed text becomes longer.
2. The overlay window MUST NOT change height because text wraps or would require more lines.
3. The overlay window width MUST remain stable.
4. While visible, repeated transcription updates MUST NOT reframe, resize, slide, or re-center the overlay based on text content.
5. The overlay MAY still use its fixed configured minimum height and fixed width when first shown.
6. Existing phase label, `R`/`T`/`C`/`I` operator indicators, non-activating panel behavior, screen selection, and hide/clear lifecycle MUST remain unchanged.
7. The implementation MUST use the existing SwiftUI/AppKit overlay architecture and MUST NOT add new runtime dependencies.

## Constraints
- The project is a Swift Package Manager macOS 14 project.
- The current overlay implementation includes previous text-measurement and growth behavior; this request intentionally removes that behavior.
- Project rules require issue fixes and behavior changes to be documented in the design/function documentation and issue log.
- No version-control operation may be performed unless explicitly requested by the user.

## Acceptance Criteria
1. Long transcript text no longer causes the overlay `NSPanel` height to increase.
2. Repeated transcript updates while the overlay is visible leave the overlay frame unchanged.
3. The overlay still appears at its normal bottom-center position when first shown.
4. Existing phase and operator indicators remain present.
5. Focused automated tests cover fixed height for short and long transcript text plus stable visible update behavior.
6. `swift test` passes.

## Assumptions
- The user's phrase "completely remove" means removing text-length-driven window resizing behavior, not removing the overlay itself or removing transcript text rendering.
- Text may still be rendered inside the fixed-size overlay using SwiftUI's current text behavior, but the window must not grow to fit it.
- Any overflow/clipping behavior for very long text is acceptable for this request unless separately specified later.

## Open Questions
None.

## Original Request
"I want you to completely remove the code that changes the size of the overlay window based on the size or growth of the transcribed text."
