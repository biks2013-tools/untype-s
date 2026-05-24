# Plan 004: Push-To-Talk Overlay Release Handling

Refined request: `docs/reference/refined-request-push-to-talk-overlay-stuck.md`

## Objective
Prevent the push-to-talk overlay from remaining visible after release without introducing repeated start/stop loops while the key is held.

## Files To Modify
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`
- `test_scripts/ui-mode-smoke.md`

## Diagnosis
`stopHotkeySession` hides the overlay only after the hotkey monitor dispatches a release event. When Quartz/AppKit misses `keyUp` or `flagsChanged`, the shared hotkey state remains pressed and the next matching key-down can be interpreted as the fallback release. That exactly matches the observed behavior: the overlay stays open after physical release and closes only on the next press.

Follow-up live evidence showed that polling physical key state was not reliable enough for the configured macOS hotkey path: the poll could report released while the key was still held, causing an early `ui-hotkey-release`, `no text was submitted`, and a repeated press/release flash loop driven by key-repeat events.

## Steps
1. Remove the aggressive physical key-state reconciliation.
2. Ignore autorepeated key-down events for the configured push-to-talk hotkey in both Quartz and AppKit monitor paths.
3. Preserve normal `keyUp`/`flagsChanged` release handling and the explicit press-to-toggle fallback when the event tap cannot start.
4. Document the issue and solution.
5. Run `swift test`.

## Acceptance Criteria
- Normal release behavior is unchanged when `keyUp`/`flagsChanged` arrives.
- Holding the hotkey cannot repeatedly restart push-to-talk sessions through key-repeat.
- Existing press-to-toggle fallback remains available when the OS cannot expose reliable key state.
- `swift test` passes.
