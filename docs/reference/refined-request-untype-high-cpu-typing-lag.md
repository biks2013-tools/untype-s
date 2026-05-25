# Refined Request: Untype High CPU and Focused Typing Lag

## Category
Development / Performance Investigation

## Objective
Determine why `untype` is consuming high CPU while running and why it lags when delivering text into the active editing field. Identify the likely faulty code paths, explain what they are doing wrong, and implement a focused fix if the cause is clear and low-risk.

## Scope
In scope:
- Inspect the Swift-native `untype` implementation for CPU-intensive loops, event monitors, timers, UI update paths, transcription callbacks, and focused-input delivery behavior.
- Focus on the active typing path, overlay/UI runtime, and any helper process used to inject text into the focused field.
- Add or update focused tests where the behavior can be verified without live microphone, provider, or macOS permission dependencies.
- Document any issue found and the solution in the project issue tracker if a fix is made.

Out of scope:
- Live provider performance profiling against Soniox or ElevenLabs unless the static code investigation points there.
- macOS Instruments profiling unless source inspection and tests are insufficient.
- UI redesign, provider changes, or broad architecture replacement.
- Changes to configuration fallback behavior.

## Requirements
- Prefer the existing Swift and XCTest patterns in the repository.
- Do not add new runtime dependencies.
- Preserve the existing CLI and UI behavior except where needed to reduce CPU load and typing lag.
- Avoid duplicate implementations; extend existing focused-input or UI runtime code.
- Keep edits narrowly scoped to the cause.

## Constraints
- The project requires missing configuration values to raise errors rather than falling back.
- Manual live smoke testing may require microphone and accessibility permissions and may not be fully runnable in this environment.
- The screenshot only shows high CPU symptoms; root cause must be inferred from code and available local tests unless runtime profiling is available.

## Acceptance Criteria
- The likely source of high CPU usage is identified with concrete file and line references.
- The likely source of lag while typing into the active field is identified with concrete file and line references.
- If a low-risk fix is available, the implementation reduces unnecessary busy waiting, polling, or repeated expensive work.
- Relevant automated tests pass, or any tests that cannot be run are explicitly reported with the reason.
- Any discovered issue and implemented solution are documented in `Issues - Pending Items.md`.

## Assumptions
- The high CPU shown in Activity Monitor corresponds to the Swift `untype` process or its focused-input helper while a UI/transcription session is active.
- The lag occurs when `untype` writes recognized or refined text to the currently focused macOS editing field.
- The user wants diagnosis and a practical fix, not only a written explanation.

## Open Questions
- Does the high CPU occur only during push-to-talk capture/transcription, or also while the UI is idle?
- Is the lag seen with clipboard delivery, focused-input delivery, or both?

## Original Request
Can you figure out why untype is consuming so much CPU and what it might be doing wrong?
I also notice that it lags when it tries to type in the active editing field.
