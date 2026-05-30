# Plan 033: Focused Input Target Restoration

## Provenance
- Refined request reused: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-bundled-app-focused-input-delivery.md`
- Codebase scan reused: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-bundled-app-focused-input-delivery.md`
- Investigation/research: skipped because this is a localized continuation of the existing focused-input delivery design.

## Objective
Fix UI sessions where the processed output is produced and copied, but focused-input delivery targets `untype.app` or no external edit control because the app regained foreground focus before the input operator sends text.

## Implementation
1. Track the most recent foreground application that is not the current `untype` process through `NSWorkspace.didActivateApplicationNotification`.
2. Capture the intended external foreground application when manual or push-to-talk recording starts.
3. Before UI focused-input delivery runs, restore the captured external application when `untype` is currently frontmost.
4. Force UI sessions to run the focused-input implementation in-process so macOS Accessibility trust applies to the app/`untype` UI process rather than the `untype-input-helper` subprocess.
5. Preserve the existing privacy boundary: processed text still flows only through the existing focused-input writer path and is not stored in UI state or diagnostics.
6. Keep CLI helper-subprocess behavior unchanged.

## Files Modified
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Sources/UntypeCore/UntypeRuntimeFactory.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- UI sessions invoke target restoration before the focused-input writer sends processed output.
- UI sessions do not require `untype-input-helper` Accessibility permission for focused-input delivery.
- If another external app is already foreground, the UI does not steal focus back to the captured app.
- If no external target is known, the UI emits a privacy-safe warning instead of silently appearing successful.
- `swift build` passes.
- Focused focused-input tests pass.
