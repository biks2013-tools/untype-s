# Refined Request: Transcript And Events Export Copy

## Category
Development

## Objective
Add user-facing actions in the native `untype ui` monitoring window that let the user extract the current transcript timeline and current event log, then either save each extracted output to a file or copy each output to the macOS clipboard.

## Scope
- **In scope**: Add copy and save capabilities for the Transcript tab's visible transcript timeline.
- **In scope**: Add copy and save capabilities for the Events tab's visible event log.
- **In scope**: Define extracted transcript text so it includes the meaningful visible transcript content: live partial text when present, committed dictated text, processed output, session issue/warning bubbles, turn grouping, and timestamps/status labels where they help preserve context.
- **In scope**: Define extracted event text so it includes the same event lines currently visible in the UI event log, in chronological order.
- **In scope**: Ensure copy/save actions are available while the UI is idle, listening, warm, or recording without stopping or restarting the active session.
- **In scope**: Update project design and functional-requirements documentation during implementation to record the new UI export/copy behavior.
- **Out of scope**: Changing transcription, provider adapters, protocol marker handling, push-to-talk behavior, LLM refinement/translation, clipboard operator delivery, focused-input delivery, or CLI rendering behavior.
- **Out of scope**: Adding automatic transcript or event persistence outside explicit user-triggered save actions.
- **Out of scope**: Persisting secrets, credentials, raw audio, provider endpoints, or hidden protocol payloads that are not already visible in the current UI.
- **Out of scope**: Adding new runtime dependencies unless a later implementation plan proves one is necessary and completes project dependency vetting first.

## Requirements
1. The Transcript tab MUST provide a user-facing copy action for the currently extractable transcript timeline.
2. The Transcript tab MUST provide a user-facing save action for the currently extractable transcript timeline.
3. The Events tab MUST provide a user-facing copy action for the currently extractable event log.
4. The Events tab MUST provide a user-facing save action for the currently extractable event log.
5. Copy actions MUST place the extracted text for the selected content type on the macOS clipboard.
6. Save actions MUST let the user write the extracted text for the selected content type to a user-chosen file.
7. Transcript extraction MUST preserve chronological reading order and distinguish at least live partial, dictated text, processed output, and session issue/warning entries when those entries exist.
8. Event extraction MUST preserve chronological order and include the same bounded set of event lines currently retained by the UI model.
9. Copy and save actions MUST be disabled or otherwise unavailable when their corresponding content type has no extractable content.
10. Copy and save actions MUST NOT clear the transcript, clear events, mutate session state, toggle protocol operators, or alter runtime configuration.
11. The implementation MUST continue to honor the project privacy rule that transcripts and protocol/event payloads are not persisted unless the user explicitly chooses to save them.
12. Automated tests MUST cover transcript extraction formatting, event extraction formatting, empty-content behavior, and copy/save action routing at the most appropriate testable boundary.

## Constraints
- The project is a Swift Package Manager macOS 14 Swift project with native SwiftUI/AppKit UI code in `Sources/UntypeCore/NativeUntypeUILauncher.swift`.
- The existing UI already separates monitoring into `Transcript` and `Events` tabs and keeps transcript state in `UntypeUITimelineState` plus event state in a bounded `[String]` log.
- The existing app menu already supports standard text-control copy behavior; the new copy actions must be explicit actions for the extracted transcript/events content, not only text selection.
- Missing configuration values must continue to raise typed errors; no configuration fallback may be introduced.
- New runtime dependencies should be avoided. If any dependency is proposed later, it must satisfy the project's dependency-vetting procedure before being added.
- No version-control operation may be performed unless explicitly requested.

## Acceptance Criteria
1. In `untype ui`, when transcript content exists, the Transcript tab exposes both `Copy` and `Save` actions for the transcript.
2. In `untype ui`, when event-log content exists, the Events tab exposes both `Copy` and `Save` actions for events.
3. Copying the transcript places extracted transcript text on the macOS clipboard and does not change the visible transcript timeline.
4. Copying events places extracted event-log text on the macOS clipboard and does not change the visible event log.
5. Saving the transcript writes the extracted transcript text to the destination selected by the user and does not stop or alter the active session.
6. Saving events writes the extracted event-log text to the destination selected by the user and does not stop or alter the active session.
7. Empty Transcript and Events states do not allow producing empty copy/save output.
8. Extracted transcript text includes visible live partial text when present and committed timeline entries when present.
9. Extracted event text includes the visible bounded event log in chronological order.
10. `swift test` passes after implementation.
11. Project documentation is updated to describe the new UI transcript/events copy and save behavior.

## Assumptions
- The request targets the native `untype ui` monitoring window because the project already has Transcript and Events tabs and the user refers to transcript/events as two user-visible areas.
- "Extract" means deriving exportable text from the current in-memory UI state, not adding a new backend data collection pipeline.
- "Save" means a user-triggered file write to a destination chosen at action time, not automatic session logging or background persistence.
- "Copy" means copying the extracted text to the macOS clipboard.
- The exported transcript should be human-readable plain text rather than a structured JSON format unless a later clarification asks for structured export.
- The exported events should be newline-delimited plain text matching the visible event log lines unless a later clarification asks for structured JSONL.
- Only currently visible/retained UI state should be exported; transcript items already cleared by the user and event lines already dropped by the 300-line event bound are not recoverable or included.

## Open Questions
- Should transcript and event exports also support structured formats such as JSON or JSONL, or is plain text sufficient for the first implementation?
- Should default save filenames include a timestamp and content type, such as `untype-transcript-YYYYMMDD-HHMMSS.txt` and `untype-events-YYYYMMDD-HHMMSS.txt`?

## Original Request
"I want you to add the ability to extract and save the transcript and the events. For each of the two, the user should be able to save them and copy them."
