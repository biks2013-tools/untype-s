# Refined Request: UI Audio Diagnostics, Sidebar Collapse, And Overlay Text Size

## Category
Development / Debugging

## Objective
Improve the native UI so it helps diagnose whether listening mode is actually receiving microphone audio, make the right settings sidebar collapsible/expandable, and reduce the push-to-talk overlay transcript text size to be closer to the Events tab text size.

## Scope
In scope:
- Surface audio capture activity in the Events tab using existing runtime audio snapshots.
- Make the event wording distinguish raw microphone activity from push-to-talk gate muting.
- Preserve existing transcription, provider, protocol, clipboard, and focused-input behavior.
- Add a UI control to collapse or expand the right settings sidebar.
- Reduce overlay transcript text size while keeping operator indicators and phase label readable.
- Update project documentation and issue log for the change.

Out of scope:
- Changing STT provider APIs or adding dependencies.
- Reworking the full UI layout beyond sidebar collapse.
- Persisting the sidebar expanded/collapsed state.

## Requirements
- Audio activity events must show whether microphone PCM is arriving.
- Audio activity events must make it clear when push-to-talk is intentionally sending silence to the provider.
- Audio events must be throttled so the Events tab remains usable.
- The settings sidebar must be collapsible and expandable from the main UI.
- Overlay transcript text must be materially smaller than the previous large display text.

## Constraints
- No new dependencies.
- Keep changes localized to the existing SwiftUI/AppKit native UI and runtime event handling.
- Do not log secrets.
- Do not persist transcript text or audio samples.

## Acceptance Criteria
- During listening, the Events tab receives `audio.input` lines showing active/silent/muted microphone activity.
- During warm push-to-talk with the gate closed, events explicitly say the provider receives silence.
- The right settings pane can be hidden and shown again.
- The overlay transcript text is similar in scale to compact monitor/event text.
- `swift test` passes.

## Assumptions
- The likely “not capturing/transcribing” case is either no microphone PCM, low/silent input, or a closed push-to-talk audio gate; the new events should identify which case is happening.
- Sidebar collapse state can be transient for this request.

## Open Questions
- None blocking.

## Original Request
although the listenning mode seems to be activeted the app doesnt capture the sound (or doesnt transcribe it)
can you add events to understand if any sound is capturing at all ? 
can you fix the issue ? 
I want you to make the right sidebar, collapsible / expandable 
I want you to make the text in overlay mush smaller, similar in size to text in the events
