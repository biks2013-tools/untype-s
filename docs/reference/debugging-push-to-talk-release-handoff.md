# Push-to-talk Release Debugging Handoff

Date: 2026-05-24

## Context
The reported issue was that releasing the native UI push-to-talk button appeared to do nothing: no monitor output, no clipboard update, and no focused-input insertion. The debugging focus was the existing `untype ui` push-to-talk release pipeline:

`hotkey release -> provider commit/finalization -> protocol submission -> optional refine/translate -> monitor timeline -> clipboard -> focused input`

Related artifacts:
- Refined request: `docs/reference/refined-request-push-to-talk-release-no-output.md`
- Codebase scan: `docs/reference/codebase-scan-push-to-talk-release-no-output.md`
- Plan: `docs/design/plan-002-push-to-talk-release-no-output.md`

## What Was Found
- The release handler was firing correctly.
- Audio capture and Soniox partial transcription were working.
- The runtime originally had too little evidence when release did not produce final text, so the UI looked inactive.
- Soniox often continued producing `transcript.partial` after release but did not provide finalized text before the runtime timeout.
- Some Soniox frames can combine semantic finalization markers and `tokens`; the Swift parser previously handled finalization before reading tokens.
- After fallback submission was added, late provider partial callbacks could still appear around processed output.
- UI runtime diagnostics were emitted twice into the transcript timeline because runtime diagnostics and event-sink diagnostics both surfaced the same warning.

## Fixes Applied
- Added release-stage diagnostics in `TranscriptionSessionRuntime`: request final text, submit transcript, processing completed, or no-final timeout.
- Added UI-visible operator diagnostics in `VoiceAgentProtocolController` for refine, translate, clipboard, and focused input.
- Surfaced release/operator warnings in the UI transcript timeline.
- Fixed Soniox parsing order so `tokens` are processed before same-frame `endpoint`, `finalized`, or `finished` markers.
- Added fallback submission: if provider finalization times out but a latest partial exists, submit the latest partial through the normal protocol/refine/clipboard/input path with an explicit warning.
- Suppressed late provider partial callbacks after release submission commits.
- Split UI runtime diagnostics from protocol-controller diagnostics in `UntypeRuntimeFactory` to prevent duplicate warning bubbles.

## Main Files Changed
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift`
- `Sources/UntypeCore/SonioxTranscriber.swift`
- `Sources/UntypeCore/VoiceAgentProtocolController.swift`
- `Sources/UntypeCore/UntypeRuntimeFactory.swift`
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Tests/UntypeCoreTests/TranscriptionSessionRuntimeTests.swift`
- `Tests/UntypeCoreTests/SonioxTranscriberTests.swift`
- `Tests/UntypeCoreTests/ProtocolControllerTests.swift`

## Test Coverage Added
- No-final release warning when provider returns no final and no partial exists.
- Release fallback submits latest partial when provider never finalizes.
- Late provider partials are suppressed after fallback submission.
- Soniox combined `finalized` frame with tokens promotes to final transcript.
- Clipboard/operator failure diagnostics are visible without verbose UI mode.

## Verification
- `swift test` passed after the latest changes: 113 tests.
- Live screenshots showed the pipeline progressed from no output to:
  - fallback warning,
  - `transcript.final`,
  - `transcript.turn_boundary`,
  - `transcript.processed`.

## Next Checks
- Re-run `untype ui` and verify the transcript timeline shows only one fallback warning bubble.
- Verify no stale `transcript.partial` appears after `transcript.final` / `transcript.processed`.
- Verify clipboard and focused-input delivery with operators enabled.
- If Soniox frequently fails to finalize, consider a provider-specific tuning follow-up for commit/finalization timing rather than changing the UI pipeline again.
