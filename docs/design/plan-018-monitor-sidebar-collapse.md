# Plan 018: Monitor Sidebar Collapse

## Provenance
- User screenshot request: make the titlebar brand/icon area collapse the left monitor sidebar, and clarify how the user restores it afterwards.
- Refined request: skipped because this is a localized UI interaction change with a concrete screenshot target.
- Investigation/research: skipped because no new approach, technology, library, or external behavior is introduced.
- Codebase scan: focused local scan only; the existing implementation was localized to `Sources/UntypeCore/NativeUntypeUILauncher.swift` and `Sources/UntypeCore/UntypeUISettings.swift`.

## Objective
Let the full-size native UI hide and restore the leading Monitor sidebar from the existing titlebar brand/icon area.

## Implementation
1. Add `monitorSidebarExpanded` to the non-secret `UntypeUISettings` layout state.
2. Persist and restore `monitorSidebarExpanded` through `~/.tool-agents/untype/ui-state.json`.
3. Bind the full-size `NavigationSplitView` column visibility to `monitorSidebarExpanded`.
4. Convert the titlebar brand mark / app-name area into a plain toggle button.
5. Restore behavior: the same titlebar brand/icon remains visible when the sidebar is hidden; clicking it again shows the Monitor sidebar.

## Files Modified
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Sources/UntypeCore/UntypeUISettings.swift`
- `Tests/UntypeCoreTests/UntypeUISettingsTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- Clicking the titlebar brand/icon hides the leading Monitor sidebar.
- The content pane expands into the freed space.
- The titlebar brand/icon remains available while hidden and clicking it again restores the sidebar.
- The hidden/visible state is saved and restored as non-secret UI layout state.
- `swift build` succeeds.
- `swift test` passes.

## Verification
- `swift build` passed on 2026-05-26.
- `swift test` passed on 2026-05-26 with 130 tests passing.
- Live screenshot verification remains part of the pending macOS UI visual review because it requires launching the native app in the user's desktop session.
