# Refined Request: Quick Close

## Category
Development

## Objective
Add a configurable push-to-talk release policy named `Quick Close` that, when enabled, submits the latest visible partial transcript immediately or near-immediately on push-to-talk release instead of waiting for the full provider finalization timeout. When disabled, the application must preserve the current behavior: request provider finalization, wait up to the existing finalization window, and only then fall back to the latest partial transcript if no final transcript arrives.

## Scope
- **In scope**:
  - Define and implement a `Quick Close` policy for native UI push-to-talk release handling.
  - Make the policy configurable on/off through the existing non-secret push-to-talk/UI configuration surface.
  - When enabled, use the latest current-turn partial transcript as the submitted text on release without waiting for the existing long finalization timeout.
  - Preserve the normal protocol processing pipeline after submission, including raw timeline entry, optional refine/translate, clipboard delivery, focused-input delivery, warnings, and History retention.
  - Keep privacy-safe diagnostics that make it clear whether a released turn used final text, Quick Close partial text, timeout fallback partial text, or no text.
  - Add focused automated coverage for enabled and disabled policy behavior.
  - Update project design, functional requirements, issue log, and smoke-test documentation as part of downstream implementation.
- **Out of scope**:
  - Changing Soniox or ElevenLabs authentication, endpoints, streaming frame format, or provider selection.
  - Adding new STT, LLM, clipboard, focused-input, or output providers.
  - Redesigning the native UI beyond the minimal setting and diagnostics needed for this policy.
  - Persisting transcript text, processed text, provider payloads, secrets, or permission state.
  - Changing CLI behavior unless the implementation intentionally reuses a shared runtime option and preserves current CLI defaults.

## Requirements
1. The policy must be named `Quick Close` in user-facing UI/configuration text.
2. The policy must be configurable as enabled or disabled and persisted only as non-secret configuration/state.
3. The disabled state must preserve the current release behavior: request provider finalization, wait for the existing finalization timeout, then fall back to the latest partial only if no final text arrives.
4. When `Quick Close` is enabled and the current push-to-talk turn has a non-empty latest partial transcript, release must submit that partial text immediately or after only a minimal debounce/settling interval.
5. When `Quick Close` is enabled and a final transcript is already available at release time, the final transcript should be preferred over the partial transcript.
6. When `Quick Close` is enabled and neither final nor partial text exists, release must produce the existing no-text warning rather than submitting empty content.
7. Quick Close submissions must flow through the same protocol processing path as finalized submissions, including raw transcript recording, optional refinement/translation, clipboard delivery, focused-input delivery, transcript timeline updates, History updates, and diagnostic events.
8. Diagnostics must distinguish Quick Close partial submission from timeout fallback partial submission so users can understand why provider finalization was not awaited.
9. Repeated push-to-talk press/release cycles must not submit stale partial text from a prior turn.
10. Automated tests must cover at least: disabled behavior waits for finalization/fallback, enabled behavior submits the latest partial without waiting for the full timeout, final text still wins when already present, and no stale partial is submitted across turns.

## Constraints
- Swift Package Manager remains the authoritative build and test entry point.
- Preserve the existing no-fallback rule for required configuration values; this policy is optional configuration and must not mask missing provider, LLM, clipboard, or focused-input configuration.
- No new runtime dependency is expected.
- Existing privacy guarantees must remain intact: transcript text and processed text must not be persisted outside current allowed in-memory/export surfaces and must not appear in diagnostic logs.
- Existing fail-open behavior for refinement, translation, clipboard, and focused-input failures must be preserved.
- Live provider behavior can vary; the implementation must not rely on Soniox returning final text on release.

## Acceptance Criteria
1. With `Quick Close` disabled, push-to-talk release still waits for the current finalization window before using the latest partial fallback when no final transcript arrives.
2. With `Quick Close` enabled and Soniox returning only partial hypotheses after release, the latest current-turn partial is submitted without waiting for the default 1.5s finalization timeout.
3. With `Quick Close` enabled and a final transcript already available on release, the final transcript is submitted instead of the partial.
4. Quick Close-submitted text appears in the Transcript and History views and is processed by enabled refine, translate, clipboard, and focused-input operators exactly like finalized text.
5. The UI/event diagnostics show whether a turn was submitted from provider final text, Quick Close partial text, timeout fallback partial text, or no available text.
6. Enabling or disabling `Quick Close` persists across UI launches without persisting transcript content, processed output, secrets, or permission status.
7. Repeated push-to-talk turns do not submit stale partial text from a previous turn.
8. `swift test` passes after the downstream implementation.
9. Relevant project documentation and smoke-test instructions are updated to describe the policy and how to verify it.

## Assumptions
- `Quick Close` is primarily a native UI push-to-talk policy because the observed issue is tied to UI push-to-talk release behavior.
- The default should be disabled to preserve existing behavior for users who prefer provider-finalized text when available.
- `Immediate or near-immediate` means materially shorter than the existing 1.5s finalization timeout; the implementation may use a small debounce/settling interval if needed to avoid dropping the last partial callback.
- Latest partial text refers only to the active push-to-talk turn and must be cleared or isolated when a new turn starts.
- The policy changes when text is submitted, not how the submitted text is refined, translated, copied, inserted, rendered, or retained.

## Open Questions
- Should `Quick Close` be exposed only in the native UI settings, or also as a CLI/config-file option for shared runtime use?
- If a minimal debounce is used, what exact upper bound should be accepted as "near-immediate" for release submission?

## Original Request
> "We can name this policy ‘Quick Close’ and make it configurable, so that it can be enabled or disabled."
