# Plan 013: UI Session Conversation History Tab

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-ui-session-conversation-history-tab.md`
- Investigation: skipped; existing UI timeline architecture defines the approach.
- Technical research: skipped; no new technology or external API is introduced.
- Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-ui-session-conversation-history-tab.md`

## Objective
Add a third native UI monitor tab that shows current-session conversation history derived from the existing in-memory transcript timeline.

## Design
- Keep `UntypeUITimelineState` as the single source of truth for current-session transcript and processed-output history.
- Add a derived history representation that groups each retained turn into:
  - raw/user-spoken text from `.raw` bubbles;
  - refine/translate recorded output from `.processed` bubbles;
  - session warnings/errors from `.error` bubbles when present.
- Add a `History` monitor tab in `NativeUntypeUILauncher.swift` beside `Transcript` and `Events`.
- Accept `history` as a valid persisted selected monitor tab in `UntypeUISettings`.
- Do not persist conversation-history content. Only the selected tab name may be persisted as non-secret layout state.

## Files to Modify
- `Sources/UntypeCore/UntypeUITimeline.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Sources/UntypeCore/UntypeUISettings.swift`
- `Tests/UntypeCoreTests/UntypeUITimelineTests.swift`
- `Tests/UntypeCoreTests/UntypeUISettingsTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Out of Scope
- Provider behavior changes.
- LLM/refine/translate prompt or API changes.
- Cross-launch conversation persistence.
- New dependencies.

## Verification
- Run `swift test`.
- Confirm selected-tab validation accepts `history` and rejects unknown values.
- Confirm derived history output includes raw, processed, error, and live partial entries in session order.
