# Refined Request: UI Session Conversation History Tab

## Category
Development

## Objective
Add one more tab to the native `untype ui` monitoring area that shows the conversation history retained for the current application session. The tab must let the operator inspect what the user said during the session and how the application recorded the refine and translate outcomes for each turn.

## Scope
In scope:
- Add a new session-local monitoring tab alongside the existing transcript and events tabs.
- Display all conversation turns retained in memory for the current UI session.
- For each turn, show the user-spoken/raw transcript content when available.
- For each turn, show how refinement and/or translation processing was recorded by the application, including processed output labels/statuses already produced by the session pipeline.
- Keep the history session-local and non-persistent unless the user explicitly uses existing export controls.
- Preserve existing Transcript and Events behavior.
- Add focused automated coverage for the history extraction/reducer behavior and selected-tab persistence if the selected tab enum changes.
- Update project documentation and issue tracking to register the change.

Out of scope:
- Persisting conversation history across app launches.
- Creating a database, external history file, or telemetry pipeline.
- Changing the refine/translate LLM behavior.
- Changing provider transcription behavior.
- Adding new runtime dependencies.

## Requirements
- The UI must expose a new tab named `History` or equivalent clear label.
- The tab must be populated from the same current-session in-memory UI timeline/turn data used by the monitor.
- The history must include user/raw transcript entries and processed refine/translate entries when those are present.
- Empty history must render a clear empty state without errors.
- Clearing the transcript timeline must also clear the conversation history if both are backed by the same retained session data.
- Selected-tab persistence must accept and restore the new tab value without persisting transcript/history content.
- The implementation must avoid logging or persisting secrets.
- No fallback configuration behavior may be introduced.

## Constraints
- SwiftPM remains the authoritative build and test entry point.
- The change must fit the existing SwiftUI/AppKit UI architecture in `Sources/UntypeCore`.
- No version-control operations are permitted.
- New test scripts, if any, must be placed under `test_scripts/`; this request should be covered by Swift tests instead.
- No new runtime dependency is expected or allowed without dependency vetting.

## Acceptance Criteria
- `untype ui` includes a third monitoring tab for current-session conversation history.
- The new tab shows all retained current-session turns with raw/user text and processed refine/translate output where available.
- The new tab remains memory-only and is not written into `ui-state.json`.
- The selected tab can be persisted/restored when set to the new tab.
- Existing transcript and event tabs continue to work.
- Relevant Swift tests pass with `swift test`.
- `docs/design/project-design.md`, `docs/design/project-functions.md`, `Issues - Pending Items.md`, and a plan under `docs/design/` are updated to record the change.

## Assumptions
- The existing grouped transcript timeline already contains enough information to render session-local conversation history without changing the runtime event schema.
- The requested phrase "conversation history for the current session" means UI process/session memory only, not cross-launch persistence.
- The "user has said" means raw dictated/final transcript text captured before refinement or translation.
- "How the Refine or Translate was done" means showing the processed outputs and their recorded labels/statuses, not exposing hidden prompts, secrets, provider payloads, or LLM internals.

## Open Questions
- None blocking.

## Original Request
Can you add one more tab in the application that shows the conversation history for the current session? It should display all the conversations that have taken place in the current session, what the user has said and how the Refine or Translate was done, how it has been recorded by the application for the current session.
