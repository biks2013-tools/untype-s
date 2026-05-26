# Plan 017: Titlebar Control Placement

## Provenance
- User screenshot request: move the full-size window session controls from the left native toolbar area into the top-right area of the center monitor column, at the same vertical level as the macOS traffic lights.
- Refined request: skipped because the request was a localized visual placement adjustment with a concrete screenshot target.
- Codebase scan: skipped because the existing implementation was already localized to `Sources/UntypeCore/NativeUntypeUILauncher.swift`.

## Objective
Reposition the full-size native UI action controls so they no longer occupy the left titlebar area near the traffic lights and instead sit on the right side of the middle monitor area.

## Implementation
1. Remove the full-size window's native SwiftUI toolbar usage for the session/action controls.
2. Add a custom `titlebarControls` strip inside `UntypeRootView`.
3. Anchor that strip to the top trailing edge of `contentPane`, which is the center monitor column between the sidebar and inspector.
4. Reserve equivalent top space for the sidebar, monitor content, and inspector so the controls remain level with the traffic lights without overlapping the status strip or settings pane.
5. Keep the existing actions and shortcuts unchanged:
   - Record/start/stop: `Command+R`
   - Inspector toggle: `Command+\`
   - Compact mode: `Option+Command+M`

## Files Modified
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- The full-size window no longer renders the session/action controls in the left native toolbar area.
- The controls render at titlebar height, visually aligned with the traffic-light row.
- The controls are aligned to the trailing side of the center monitor column, not the far right of the inspector.
- Existing control behavior and keyboard shortcuts are preserved.
- `swift build` succeeds.
- `swift test` passes.

## Verification
- `swift build` passed on 2026-05-26.
- `swift test` passed on 2026-05-26 with 130 tests passing.
- Live visual screenshot verification remains part of the pending macOS UI visual review because it requires launching the native app in the user's desktop session.
