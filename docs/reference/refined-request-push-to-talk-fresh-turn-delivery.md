# Refined Request: Push-to-talk fresh turn delivery

## Category
Development bug fix and behavior change.

## Objective
Change native UI push-to-talk behavior so every push-to-talk press starts a fresh content collection turn, release finalizes that turn, and the resulting text is visible in the monitor and delivered through the configured output operators.

## Scope
In scope:
- Update native UI push-to-talk session handling.
- Prevent partial transcript text from a previous push-to-talk capture from carrying into the next capture.
- Ensure push-to-talk release finalizes/submits the captured text.
- Ensure final/processed text appears in the transcript monitor.
- Preserve configured clipboard and focused-input operators when a section is submitted.
- Add or update focused tests for the runtime behavior.
- Update project documentation and issue log.

Out of scope:
- Adding new STT or LLM providers.
- Changing provider authentication or configuration fallback behavior.
- Reworking the entire UI design.
- Changing CLI behavior unless required by shared runtime correctness.

## Requirements
- Each push-to-talk press must begin a fresh content collection turn from the user's perspective.
- Release must not leave stale live partial text in the UI as the active buffer.
- Release must give the provider enough time to finalize speech before the protocol controller submits pending text.
- Processed/refined/translated output must be emitted to the UI timeline when the relevant operators are enabled.
- Clipboard and focused-input delivery must be attempted for submitted processed text when their operators are enabled.
- Secrets and transcript text must not be persisted.

## Constraints
- No new runtime dependencies.
- Missing configuration must continue to raise typed errors; no fallback config values.
- Keep changes localized to the current Swift UI/runtime architecture where possible.

## Acceptance Criteria
- Pressing push-to-talk repeatedly does not continue displaying or submitting the previous partial buffer.
- Releasing push-to-talk commits provider output, waits for final text, submits it, and closes the current visible turn.
- UI timeline shows committed raw text and processed text for the released turn.
- Existing automated tests pass.
- The behavior change is documented in project docs and issue log.

## Assumptions
- The user wants press/release cycles to behave as independent dictation turns, not one long warm provider session.
- The existing clipboard and focused-input operators should remain governed by their UI toggles.
- If LLM refinement/translation fails, the protocol controller’s existing fail-open warning behavior remains acceptable.

## Open Questions
- Whether the warm provider session should be removed entirely or kept only as a startup optimization is a product choice; this implementation should favor correctness and independent push-to-talk turns.

## Original Request
> Every time I use the push-to-talk button, I want a new session for content collection to start, instead of continuing the previous one.
> At the end of the session, when I release the push-to-talk button, it doesn’t return the text to the edit field that has focus.
> You can also see from the screenshot that even switching to the events does not reset the text buffer that had been created earlier.
> Also, the text it captures is neither available in the clipboard, nor does the refined or translated version of the text appear, not even on the tool’s monitor.
