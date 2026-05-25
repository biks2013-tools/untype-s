# Refined Request: Fix History Release Disappearing Transcript

## Category
Development

## Objective
Fix the native UI bug where releasing the push-to-talk button causes the transcript and refined output to disappear from the Transcript tab and leaves no corresponding entry in the History tab.

## Scope
In scope:
- Diagnose the push-to-talk release path, transcript timeline reducer, and History tab derivation.
- Ensure raw transcript and refined/translated processed output remain visible in the Transcript tab after release processing completes.
- Ensure the History tab records the same retained current-session turn after release processing completes.
- Preserve existing clear behavior: explicit Clear may remove transcript/history, but release processing must not.
- Add regression tests for the disappearing release transcript/history case.
- Update project documentation and issue tracking with the issue and solution.

Out of scope:
- Cross-launch transcript/history persistence.
- Provider STT or LLM prompt behavior changes beyond what is necessary to keep already-recorded UI data.
- Adding new export actions.
- Adding new runtime dependencies.

## Requirements
- Releasing push-to-talk must not clear committed raw or processed timeline content.
- Starting/restarting a warm push-to-talk session after release must not reset the retained session timeline/history.
- The Transcript tab and History tab must both use the same retained in-memory session data.
- Empty history should still render only when no retained raw, processed, warning, or live partial content exists.
- Any automatic clear operation must be limited to stale live partial text, not committed turns.

## Constraints
- SwiftPM remains the authoritative build and test entry point.
- No version-control operations are permitted.
- No new runtime dependency is expected.
- Conversation history must remain memory-only and must not be written to `ui-state.json`.
- Missing or invalid configuration must still raise errors; no fallback configuration behavior may be introduced.

## Acceptance Criteria
- A push-to-talk release that produces raw text and refined/translated output leaves both visible in Transcript.
- The same release produces a History entry containing the user/raw text and recorded processed output.
- Starting the next warm push-to-talk session does not clear the previous committed release turn.
- `swift test` passes.
- `docs/design/project-design.md`, `docs/design/project-functions.md`, `Issues - Pending Items.md`, and a plan under `docs/design/` are updated to document the fix.

## Assumptions
- The disappearance is caused by UI timeline state being cleared or ignored during the release-to-warm-session transition, not by provider failure to produce text.
- The intended behavior is session-local retention until explicit Clear or app termination.

## Open Questions
- None blocking.

## Original Request
After releasing the talk button, the transcript and its refined version disappear from the transcript tab and, at the same time, there is nothing recorded in the history. Can you fix it?
