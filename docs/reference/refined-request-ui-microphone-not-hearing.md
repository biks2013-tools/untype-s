# Refined Request: UI microphone appears not to hear speech

## Category
Development bug fix.

## Objective
Diagnose and address the reported native UI behavior where the app appears not to hear speech.

## Scope
In scope:
- Inspect the Swift UI, session runtime, microphone capture, and push-to-talk audio-gate paths.
- Determine whether the behavior is caused by microphone capture failure, provider startup failure, or push-to-talk gating.
- Improve the product behavior or diagnostics if the UI can mislead the operator into speaking while audio is intentionally muted.
- Run focused Swift verification after any source changes.

Out of scope:
- Adding a new STT provider.
- Changing secret/configuration fallback behavior.
- Performing live provider verification that requires the user to speak or expose API keys.
- Changing app signing, notarization, or distribution.

## Requirements
- The UI must continue to use the existing AVFoundation microphone path and provider runtime.
- Push-to-talk warm sessions must keep the provider session alive while sending silence when the gate is closed.
- The UI must make it clear when audio is muted by the push-to-talk gate versus when microphone capture is silent or waiting.
- No transcript text, API keys, or provider secrets may be persisted or logged by the diagnostic improvement.

## Constraints
- Do not introduce new runtime dependencies.
- Preserve the existing strict configuration behavior; missing configuration must raise typed errors rather than using fallbacks.
- Preserve existing user state files and unrelated project files.

## Acceptance Criteria
- The likely cause of the reported behavior is identified from local project state and code.
- If the issue is push-to-talk gating, the UI labels/status text distinguish that state clearly.
- Existing automated tests pass after the change.
- The issue and solution are recorded in the project issue log or design/function documentation as appropriate.

## Assumptions
- The screenshot corresponds to `untype ui`.
- The persisted UI state is representative of the user's current UI configuration.
- If the UI shows `Audio: muted <n>%`, microphone capture is active and the push-to-talk gate is closed.

## Open Questions
- Was the user holding `Control+\`` or pressing the UI `Press Hotkey` button while speaking?
- Did the UI show `Audio: muted`, `Audio: silent`, or `Audio: waiting` at the time of the report?

## Original Request
> it doesn't hear anything
