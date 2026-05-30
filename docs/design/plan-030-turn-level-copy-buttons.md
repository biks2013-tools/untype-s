# Plan 030: Turn-Level Copy Buttons

Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-turn-level-copy-buttons.md`
Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-turn-level-copy-buttons.md`
Investigation: skipped; the project already has a single established SwiftUI/AppKit pasteboard approach.
Technical research: skipped; no new technology or dependency is introduced.

## Objective
Add compact per-turn copy controls to the native UI so raw dictated text and processed output can be copied independently from the existing whole-transcript export action.

## Files to Modify
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
  - Add model methods that copy a single transcript section through `MacOSClipboardWriter.writeToSystemPasteboard`.
  - Add compact icon copy buttons to raw and processed transcript bubbles.
  - Add compact icon copy buttons to raw and processed History sections.
- `docs/design/project-design.md`
  - Record the new explicit per-turn copy behavior.
- `docs/design/project-functions.md`
  - Register the feature slice under FR-17/FR-18.

## Out of Scope
- Runtime transcript/refine/translate behavior.
- Whole transcript/event export formats.
- Automatic transcript persistence.
- New dependencies.

## Steps
1. Add a focused `UntypeUIModel.copyTranscriptSection(_:kind:)` action that trims only for empty detection and writes the exact section text to the pasteboard.
2. Add a reusable compact copy button helper with icon-only display and accessible labels.
3. Wire raw and processed transcript bubbles to the helper.
4. Wire History `User said` and output sections to the helper; avoid copy buttons for issue rows unless explicitly needed later.
5. Update design/function documentation.
6. Verify with `swift build` and `swift test`.

## Acceptance Criteria
- Transcript raw bubbles expose a raw copy control.
- Transcript processed bubbles expose a processed copy control.
- History user-text sections expose a raw copy control.
- History output sections expose a processed copy control.
- The copied payload is exactly the relevant section text.
- Existing whole-transcript and event copy/save controls remain unchanged.
- `swift build` and `swift test` pass.
