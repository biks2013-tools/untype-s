# Plan 014: Fix History Release Disappearing Transcript

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-fix-history-release-disappearing-transcript.md`
- Investigation: skipped; existing push-to-talk UI architecture defines the approach.
- Technical research: skipped; no new technology or external API is introduced.
- Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-fix-history-release-disappearing-transcript.md`

## Objective
Preserve committed Transcript and History entries after push-to-talk release and automatic warm-session restart.

## Root Cause
`UntypeUIModel.startSession(...)` resets `timeline` to a new `UntypeUITimelineState()` for every runtime start. Push-to-talk release stops the active provider runtime and starts a fresh warm runtime for the next press, so the warm restart clears the committed raw and processed output that was just recorded.

## Implementation
- Replace full timeline reset during session start with `timeline.clearPartial()`.
- Keep explicit `Clear` as the only UI action that removes committed timeline/history content.
- Add regression coverage that clearing a stale partial preserves committed raw/processed turns and derived history.

## Files to Modify
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/UntypeUITimelineTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Verification
- Run `swift test`.
- Confirm the retained timeline still contains committed raw and processed bubbles after stale partial cleanup.
- Confirm the derived History view still contains the same retained conversation.
