# Plan 005: UI Audio Diagnostics, Sidebar Collapse, And Overlay Text Size

Refined request: `docs/reference/refined-request-ui-audio-diagnostics-sidebar-overlay.md`

## Objective
Expose enough UI evidence to tell whether the microphone is producing audio, whether push-to-talk is gating provider input, and improve monitor space with a collapsible settings pane and smaller overlay text.

## Files To Modify
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`
- `test_scripts/ui-mode-smoke.md`

## Steps
1. Add throttled `audio.input` event logging from existing `AudioActivitySnapshot` updates.
2. Make audio event text distinguish active microphone input, silent microphone input, and push-to-talk gate muting.
3. Add a transient right-sidebar expanded/collapsed state and header button.
4. Reduce overlay transcript typography and panel height to better match compact monitor text.
5. Update design/function/smoke documentation.
6. Run `swift test`.

## Acceptance Criteria
- Events tab shows whether microphone PCM is arriving and whether the provider is receiving audio or silence.
- Holding or warming push-to-talk cannot be mistaken for missing microphone capture because muted gate events identify the gate.
- Settings sidebar can be collapsed and expanded without changing session state.
- Overlay text is compact.
- `swift test` passes.
