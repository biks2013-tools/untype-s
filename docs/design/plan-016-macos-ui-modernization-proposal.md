# Plan 016: macOS UI Modernization Proposal

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-macos-ui-modernization-proposal.md`
- Technical research: `~/aiwork/coding-platform/untype-s/docs/reference/macos-ui-guidelines-modernization-research.md`
- Source files reviewed:
  - `~/aiwork/coding-platform/untype-s/Sources/UntypeCore/NativeUntypeUILauncher.swift`
  - `~/aiwork/coding-platform/untype-s/Sources/UntypeCore/UntypeUISettings.swift`

## Current UI Inventory from Source

`untype ui` is a native AppKit-hosted SwiftUI window. The app launches as a regular macOS app, creates a resizable titled window named `untype`, and restores width/height from persisted UI settings. The current minimum size is `860 x 620`; the default restored size is `1180 x 760`.

Evidence:
- `NativeUntypeUILauncher.swift:31-39` launches `NSApplication`.
- `NativeUntypeUILauncher.swift:71-89` creates the titled, resizable `NSWindow`.
- `UntypeUISettings.swift:56-59` defines default window size, settings expansion, and selected monitor tab.

The main window is currently a horizontal split:
- left/main pane: title, status line, primary session button, refresh button, settings toggle, and monitor tab view.
- right pane: collapsible settings surface.

Evidence:
- `NativeUntypeUILauncher.swift:825-835` defines the main horizontal layout and collapsible settings pane.
- `NativeUntypeUILauncher.swift:838-864` defines the current header and main pane.

The monitoring area uses a `TabView` with three peers:
- `Transcript`: grouped turns, live partials, Copy, Save, Clear.
- `History`: session-local conversation history and Clear.
- `Events`: retained diagnostic/protocol/event log, Copy, Save.

Evidence:
- `NativeUntypeUILauncher.swift:867-888` defines the three monitor tabs.
- `NativeUntypeUILauncher.swift:891-941` defines the transcript pane.
- `NativeUntypeUILauncher.swift:944-986` defines the events pane.
- `NativeUntypeUILauncher.swift:989-1032` defines the history pane.

The right settings pane contains six grouped sections:
- Credentials: key name, status, source, expiry.
- System: microphone, audio, accessibility, input.
- Provider: STT provider, model, languages, sample rate, endpoint detection.
- Protocol: mode, translation policy, Refine, Translate, Clipboard, Focused input.
- LLM: enabled, provider, model.
- Push to Talk: enabled, hotkey, press/release action, status note.

Evidence:
- `NativeUntypeUILauncher.swift:1158-1300` defines the settings pane sections and controls.
- `NativeUntypeUILauncher.swift:1307-1355` defines the current material section, form row, and status row styling.

The push-to-talk overlay is a borderless non-activating `NSPanel` at status-bar level. It shows live transcript text, four operator indicators (`R`, `T`, `C`, `I`), and a phase indicator. It is intentionally passive and ignores mouse events.

Evidence:
- `NativeUntypeUILauncher.swift:1435-1582` defines the overlay controller and panel behavior.
- `NativeUntypeUILauncher.swift:1584-1629` defines the overlay visual content.

## Current Design Diagnosis

The existing UI is functionally rich, but it still reads like an implementation dashboard more than a polished Mac app:
- The header status line compresses three important state dimensions into one sentence.
- The primary action competes visually with secondary controls.
- `Transcript`, `History`, and `Events` behave like app sections, but top tabs make them feel like temporary subviews.
- The settings pane is useful, but the stacked material sections feel visually busier than an inspector or Form-style settings surface.
- Diagnostics and permission states are present, but remediation hierarchy is weak; errors, warnings, and normal status rely too much on plain text in rows/logs.
- The overlay is practical, but it should feel more like a compact dictation HUD and less like a mini log window.

## Proposed Product Shape

### Design Goal
Make `untype ui` feel like a quiet native macOS utility for live dictation and voice-agent routing: immediate to start, calm while monitoring, dense enough for expert use, and explicit about privacy, permissions, and output delivery.

### Recommended Layout

Use a three-region macOS structure:

1. **Native toolbar**
   - Window title: `untype`.
   - Primary control: `Start Listening` / `Stop Listening` / `Stop Recording` / `Stop Warm Session`.
   - Secondary controls: Refresh, Inspector toggle, optional Push-to-Talk quick control.
   - Compact status cluster: Session, Capture, Audio.

2. **Leading sidebar/source list**
   - `Transcript`
   - `History`
   - `Events`
   - Optional future section: `Setup` or `Permissions`, only if permission remediation grows beyond status rows.

3. **Main content plus trailing inspector**
   - Main content shows the selected section.
   - Trailing inspector replaces the current settings pane and uses native grouped form rows.
   - Inspector can collapse and preserve the selected section/state exactly as today.

This keeps the app close to common macOS document/utility patterns: toolbar for frequent commands, sidebar for persistent navigation, content for work, inspector for configuration.

## Proposed Main Window Design

### Toolbar
Move the current inline header controls into a native-style toolbar:
- Primary button: a prominent bordered/tinted action with a record/microphone SF Symbol and current session label.
- Refresh: icon button with tooltip and optional text in expanded toolbar display mode.
- Inspector toggle: native sidebar/inspector icon button.
- Push-to-talk quick state: visible only when push-to-talk is enabled; shows `Warm`, `Recording`, or `Finalizing`.

Keep `Command+R` for start/stop only if it does not conflict with expected Refresh semantics. Prefer `Command+Return` or a custom menu command for Start/Stop if `Refresh` remains visually present.

### Status Strip
Replace the current single status sentence with compact status pills below the toolbar or at the top of content:
- Session: Idle, Starting, Listening, Warm, Recording, Finalizing, Error.
- Audio: Waiting, Silent, Active, Muted by Push to Talk.
- Output: Off, Clipboard, Focused Input, Clipboard + Focused Input.
- Permission: OK, Needs Microphone, Needs Accessibility/Input Monitoring.

Each pill should include text plus a symbol. Color can reinforce state, but text and symbol must carry meaning without color.

### Sidebar
Replace the monitor `TabView` with a sidebar/source-list:
- `Transcript`: live timeline and export.
- `History`: summarized session turns and processed results.
- `Events`: diagnostics, provider lifecycle, protocol events.

Persist the selection through the existing `selectedMonitorTab` setting, preserving current behavior.

### Transcript View
Keep the grouped turn model, but adjust the presentation:
- Use a transcript-first work area with strong vertical rhythm and less card color.
- Show live partial as a pinned bottom "Listening..." row while recording.
- Show raw and processed output in the same turn with subtle section labels.
- Keep `Copy`, `Save`, and `Clear` in a content toolbar local to Transcript.
- Use warning rows inline when release finalization or operator delivery fails.

### History View
Make History a compact conversation ledger:
- Left column: turn time/status.
- Main column: "User said" and "Processed" summaries.
- Expand/collapse long turns.
- Keep Clear as a local action, matching current memory-only behavior.

### Events View
Make Events an expert diagnostic console:
- Monospaced log remains appropriate.
- Add filter chips: All, Warnings, Provider, Audio, Hotkey, Protocol.
- Keep Copy and Save local to Events.
- Preserve chronological auto-scroll.

### Inspector Settings
Use a trailing inspector with grouped sections:
- Setup: Provider, model, languages, sample rate, endpoint detection.
- Protocol: mode, translation policy, operator toggles.
- Output: clipboard and focused input status/delivery.
- Intelligence: LLM enabled, provider, model.
- Permissions: microphone, accessibility, input monitoring, key status.
- Push to Talk: enabled, hotkey, fallback press/release button.

Important behavior to preserve:
- Session-shaping controls remain disabled while a manual, warm, or recording session is active.
- The four operator toggles remain editable during active sessions.
- Secrets remain invisible.
- Settings persist through `UntypeUISettingsStore`.

## Proposed Overlay Design

Keep the `NSPanel` implementation, but redesign it as a compact dictation HUD:
- Material: regular material with subtle border and shadow.
- Top line: live transcript text, wrapping within the stable width.
- Bottom left: operator indicators with full accessible labels, visually compact.
- Bottom right: phase with dot and text (`Recording`, `Finalizing`, `Processed`).
- Error/warning state: small amber warning symbol and short phrase, never a long diagnostic log.
- No interactive controls in the overlay because it ignores mouse events and should not steal focus.

The overlay should remain secondary to the main window. Long diagnostics belong in Events and warning rows in Transcript/History.

## Visual Style

- Use system background colors, materials, and separators rather than custom glass-card stacking.
- Use SF Symbols for toolbar/status meaning.
- Keep corners modest: 6 to 8 px for transcript rows and inspector groups; avoid deeply rounded promotional styling.
- Use `.secondary` text sparingly for metadata, not for critical state.
- Prefer `Form`, `LabeledContent`, `DisclosureGroup`, and native picker/toggle styling where possible.
- Avoid dominant accent-color fills except for the primary session action and active operator state.
- Preserve dense macOS scanning: compact rows, aligned labels, clear section headers.

## Accessibility and Keyboard Requirements

- Every toolbar icon-only control must have a label/help string.
- Every status indicator must be understandable without color.
- Transcript, history, and event text must remain selectable.
- Start/stop, inspector toggle, monitor navigation, and export actions must be keyboard reachable.
- Disabled controls must explain why they are disabled when feasible, especially active-session settings.
- Window resizing must not hide primary controls or cause text overlap.

## Implementation Phases

### Phase 1: Structure Without Runtime Changes
- Replace inline header controls with a SwiftUI toolbar or AppKit toolbar wrapper.
- Replace monitor `TabView` with a `NavigationSplitView`/source-list style navigation while preserving `selectedMonitorTab`.
- Keep the existing right settings pane behavior but rename the concept to Inspector in code/UI.

### Phase 2: Inspector Polish
- Convert stacked material sections into native grouped inspector rows.
- Add clearer disabled-state messaging for active-session controls.
- Add status severity treatment for credentials and permissions.

### Phase 3: Monitoring Surfaces
- Refine Transcript/History row styling.
- Add Events filtering.
- Keep export behavior unchanged.

### Phase 4: Overlay HUD Polish
- Apply HUD visual treatment and concise phase/warning states.
- Add accessibility labels for operator indicators.
- Confirm overlay frame stability across long transcript updates.

### Phase 5: Verification
- Run `swift test`.
- Run `test_scripts/ui-mode-smoke.md`.
- Capture before/after screenshots for idle, listening, warm push-to-talk, recording overlay, finalizing overlay, warning state, inspector expanded/collapsed, and each monitor section.

## Acceptance Criteria for Future Implementation

- The app opens to a native macOS window with toolbar, sidebar/source-list navigation, content area, and collapsible inspector.
- All existing controls and workflows remain available.
- Existing settings persistence continues to restore window size, inspector visibility, and selected monitor section.
- Active-session editability rules remain unchanged.
- Transcript, History, and Events preserve existing data retention and export semantics.
- Overlay remains non-activating, focus-safe, and visually stable.
- No secrets or transcript content are persisted beyond existing explicit behavior.
- Manual UI smoke verification includes screenshots for the key states listed in Phase 5.
