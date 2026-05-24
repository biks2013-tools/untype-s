# Refined Request: Push-to-talk release produces no output

## Category
Development bug fix.

## Objective
Diagnose and fix the native UI push-to-talk release path so that releasing the talk button after captured speech reliably produces observable output: transcription/refinement evidence in the monitor, clipboard delivery when enabled, and focused edit-control insertion when input delivery is enabled. If any stage cannot complete because of configuration, permissions, provider, LLM, clipboard, or focused-input errors, the UI must show an explicit diagnostic instead of appearing inactive.

## Scope
- **In scope**:
  - Investigate the native UI push-to-talk press/release path from audio gate opening through provider finalization, protocol submission, optional refinement/translation, monitor timeline rendering, clipboard delivery, and focused-input delivery.
  - Verify whether the issue is a regression of the previously documented push-to-talk release finalization behavior or a separate failure in the same output pipeline.
  - Ensure the UI event log or monitor shows privacy-safe evidence for the relevant stages of push-to-talk release processing.
  - Ensure raw and processed output appears in the monitor when transcription and processing succeed.
  - Ensure clipboard output is attempted and observable when the clipboard operator is enabled.
  - Ensure focused-input delivery is attempted and observable when the input operator is enabled and macOS Accessibility permissions allow delivery.
  - Add or update focused automated tests for the failing release-to-output behavior where practical.
  - Update project documentation and the issue log after the downstream bug fix is implemented.
- **Out of scope**:
  - Adding new STT providers, LLM providers, or output targets.
  - Redesigning the native UI layout beyond status/diagnostic changes needed to expose this failure.
  - Changing provider authentication, configuration precedence, or missing-configuration behavior.
  - Creating fallback configuration values or silently disabling required output stages.
  - Performing implementation work as part of this refinement step.

## Requirements
1. The downstream fix must determine where the release-to-output pipeline stops when the talk button is released.
2. Releasing the push-to-talk button after speech must submit the captured turn once provider final text is available, or produce an explicit provider/finalization diagnostic if final text cannot be obtained.
3. Successful submitted text must appear in the native UI monitor/timeline as raw transcription and, when processing operators are enabled, as processed/refined/translated output.
4. When the clipboard operator is enabled, the submitted processed text must be copied to the macOS clipboard or the UI must show a privacy-safe failure diagnostic.
5. When the input operator is enabled, the submitted processed text must be delivered to the active edit control or the UI must show a privacy-safe failure diagnostic, including permission-related failures.
6. Refinement and translation failures must preserve the existing fail-open runtime behavior while still leaving visible evidence that the stage was attempted and failed.
7. The fix must not persist transcript text, processed text, secrets, or host-specific permission status outside the existing allowed runtime/UI surfaces.
8. The fix must preserve the current source-compatible push-to-talk model: a warm session may exist, press opens the audio gate, release closes the gate, the current turn is submitted, and the next press starts a fresh content collection turn.
9. Automated coverage must be added or updated for the smallest practical unit of the failure, such as runtime submission, UI release handling, timeline event routing, clipboard delivery routing, or focused-input delivery routing.
10. Manual verification steps must cover a real `untype ui` push-to-talk press/release cycle with the monitor, clipboard, and active edit control observed.

## Constraints
- Use Swift Package Manager as the build and test entry point.
- Preserve project rules: no version-control operations unless explicitly requested, no fallback configuration values, and no new runtime dependencies unless separately vetted.
- Maintain privacy guarantees for clipboard/focused-input handling: processed text must not be passed through process arguments or diagnostic logs.
- Keep CLI behavior unchanged unless the defect is proven to be in shared runtime code.
- Treat the existing completed item for push-to-talk release finalization as historical context, not proof that the current report is already resolved.
- This request refinement must only create the refined request file; code changes belong to downstream implementation.

## Acceptance Criteria
1. In `untype ui`, with push-to-talk enabled and required provider credentials configured, pressing the talk button, speaking, and releasing it produces visible monitor/timeline output for the captured turn.
2. With refinement enabled and configured, the monitor/timeline shows either refined output or an explicit fail-open refinement diagnostic for the released turn.
3. With clipboard enabled, the macOS clipboard contains the submitted processed text after release, or the UI shows a clear clipboard-delivery failure diagnostic.
4. With focused-input enabled and a writable edit control focused, the active control receives the submitted processed text after release, or the UI shows a clear focused-input or Accessibility-permission diagnostic.
5. The UI no longer appears to do nothing: each release produces either output or an explicit privacy-safe diagnostic identifying the failed stage.
6. Repeated push-to-talk press/release cycles do not reuse stale partial text from earlier turns.
7. Relevant automated tests pass with `swift test`.
8. The downstream implementation documents the issue and solution in the project issue log and updates design/function documentation if behavior or diagnostics change.

## Assumptions
- The phrase "whole talk button" refers to the native UI push-to-talk/talk button release action.
- The user is reporting `untype ui` behavior, not CLI dictation behavior, because the request mentions the monitor, clipboard, active edit control, and a talk button.
- The expected output pipeline is the existing project pipeline: STT finalization, protocol submission, optional LLM refinement/translation, monitor rendering, clipboard delivery, and focused-input delivery.
- Clipboard and focused-input delivery are expected only when their corresponding protocol operators are enabled.
- The implementation should first preserve the existing architecture and diagnose the pipeline rather than replace the push-to-talk design wholesale.

## Open Questions
- Does the failure occur with the keyboard hotkey, the UI fallback talk button, or both?
- Which STT provider and LLM provider/settings were active when the failure occurred?
- Were the clipboard and input operators visibly enabled in the UI at the time of the release?
- Did the UI event log show microphone/provider activity before release, or was there no activity at all?

## Original Request
> "When the whole talk button is released, nothing appears either in the monitor, or in the clipboard, or in the active edit control. It seems as if neither refinement nor transcription is happening at all; there is no evidence that these actions are being executed. It looks like this part is not working at all."
