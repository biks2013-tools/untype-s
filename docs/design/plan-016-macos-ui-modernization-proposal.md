# Plan 016: macOS UI Modernization — Design-Bundle Implementation

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-macos-ui-modernization-proposal.md`
- Technical research: `~/aiwork/coding-platform/untype-s/docs/reference/macos-ui-guidelines-modernization-research.md`
- Design handoff bundle (Claude Design): `docs/reference/design-bundle-macos-modernization/`
  - Primary file: `docs/reference/design-bundle-macos-modernization/project/untype - modern macOS redesign.html`
  - Chat transcript: `docs/reference/design-bundle-macos-modernization/chats/chat1.md`
  - Shared design tokens / primitives: `docs/reference/design-bundle-macos-modernization/project/src/shared.jsx`
  - Main window variants: `docs/reference/design-bundle-macos-modernization/project/src/main-windows.jsx`
  - Peripherals (overlay / menubar / mini): `docs/reference/design-bundle-macos-modernization/project/src/peripheral.jsx`
  - Screens (onboarding / settings / history): `docs/reference/design-bundle-macos-modernization/project/src/screens.jsx`
- Source files reviewed:
  - `Sources/UntypeCore/NativeUntypeUILauncher.swift`
  - `Sources/UntypeCore/UntypeUISettings.swift`
  - `Sources/UntypeCore/UntypeUITimeline.swift`
  - `Sources/UntypeCore/UntypeOverlayLayout.swift`

## Direction Locked

After the user reviewed the design canvas, the locked direction is:

- **Main window: V1 Classic Sidebar.** Closest to the existing `UntypeRootView` HStack
  (left rail + monitor + right inspector), so most of the existing data plumbing
  (`UntypeUIModel`, `UntypeUITimeline`, `UntypeUISettings`, settings persistence,
  active-session disabling rules) survives intact.
- **Visual language: native SwiftUI materials.** Use `.regularMaterial`,
  `.thinMaterial`, `Color.accentColor`, and SF Symbols rather than literal port
  of the `unMaterial()` blur/saturate stack from `shared.jsx`. The design's
  amber-accent identity comes through via a single tinted accent color and an
  amber `UntypeBrandMark`, not via deeply rounded promotional gradients on every
  surface.
- **Overlay: dictation HUD (overlay variant C, the card).** Best fit for the
  current non-activating `NSPanel` with wrap-grow text and four R/T/C/I chips.
- **Mini window: deferred behind a hidden setting.** Built but not surfaced on
  the toolbar until the V1 main flow is validated.

The chat transcript (`docs/reference/design-bundle-macos-modernization/chats/chat1.md`)
documents the user's choices: Tahoe / Liquid Glass era, warm amber accent, glassy
operator pills with status lights, both light + dark, real provider names from
the repo, R/T/C/I treatment, material-strength as the only tweak.

## Mapping: Design Surfaces → Swift Integration Points

| Design surface (file:symbol)                  | Swift target                                                            | Phase |
|-----------------------------------------------|-------------------------------------------------------------------------|-------|
| `shared.jsx:UN_THEMES / unMaterial`           | `UntypeDesignSystem.swift:UntypePalette / UntypeMaterials`              | 1     |
| `shared.jsx:UnBrandMark`                      | `UntypeDesignSystem.swift:UntypeBrandMark`                              | 1     |
| `shared.jsx:UnOperatorPill`                   | `UntypeDesignSystem.swift:UntypeOperatorChip`                           | 1     |
| `shared.jsx:UnRecordButton`                   | `UntypeDesignSystem.swift:UntypeRecordButton` (toolbar primary)         | 1     |
| `shared.jsx:UnWaveform`                       | `UntypeDesignSystem.swift:UntypeWaveformView`                           | 1     |
| `shared.jsx:UnStatusDot`                      | `UntypeDesignSystem.swift:UntypeStatusDot`                              | 1     |
| `shared.jsx:UnLabel / UnKV / UnTabs / UnBtn`  | `UntypeDesignSystem.swift:UntypeFormStyles`                             | 1     |
| `main-windows.jsx:V1Sidebar`                  | `UntypeRootView.sidebar` (NavigationSplitView leading column)           | 1     |
| `main-windows.jsx:V1Monitor`                  | `UntypeRootView.monitor` (content column)                               | 1     |
| `main-windows.jsx:TranscriptTurn`             | `UntypeRootView.timelineTurnView`                                       | 1     |
| `main-windows.jsx:V1Inspector`                | `UntypeRootView.settingsPane` (refactor to grouped inspector)           | 3     |
| `peripheral.jsx:OverlayCard`                  | `UntypeOverlayView`                                                     | 2     |
| `peripheral.jsx:UnMenubarDropdown`            | Future `UntypeMenubarController` (out of scope for this plan)           | —     |
| `peripheral.jsx:UnMini`                       | `UntypeMiniWindowController` (compact-mode toggle)                      | 5     |
| `screens.jsx:Onboarding`                      | `UntypeOnboardingView` shown when `apiKeyStatus == "missing"`           | 5     |
| `screens.jsx:SettingsProviders / Shortcuts`   | Sections inside the redesigned inspector (no separate window)           | 3     |
| `screens.jsx:HistoryBrowser`                  | `UntypeRootView.historyPane` styling                                    | 4     |

## Phase 1 — Design System + Main Window Restructure

### 1.1 New file: `Sources/UntypeCore/UntypeDesignSystem.swift`

Contains, in this order:

1. `enum UntypeAccent` — semantic colors (`amber`, `recording`, `success`,
   `warning`) backed by `Color(.sRGB, red:…, green:…, blue:…, opacity:…)` so they
   render identically in light and dark. Source values from `shared.jsx:UN_THEMES`.
2. `struct UntypeBrandMark: View` — 28-pt amber rounded square with white "u"
   monogram. Matches `shared.jsx:UnBrandMark`.
3. `struct UntypeStatusDot: View` — 7-pt dot with 3-pt halo. Tone enum:
   `ok / warn / recording / accent / off`.
4. `struct UntypeStatusPill: View` — text + dot + optional SF Symbol icon, in a
   `.thinMaterial` Capsule. Matches plan-016's "compact status pill" requirement.
5. `struct UntypeOperatorChip: View` — letter + label + status dot. Tinted with
   `accentColor.opacity(0.18)` background and `accentColor.opacity(0.35)` stroke
   when `on`. When `recording && on`, dot uses the recording red. Click toggles.
6. `struct UntypeRecordButton: View` — amber gradient capsule when idle, red
   gradient when recording, white shape inside (circle → rounded square on
   recording). Drives `model.startManualSession()` / `model.stopPrimarySession()`
   via a closure passed in.
7. `struct UntypeWaveformView: View` — deterministic pseudo-waveform (24–36 bars).
   Mirrors `shared.jsx:UnWaveform` but uses `TimelineView` only when `recording`
   to keep CPU low when idle (relevant to plan-015).
8. `struct UntypeKbd: View` — kbd-style pill for hotkey display.
9. `struct UntypeSectionHeader: View` — uppercase 11-pt label for inspector
   sections. Matches `shared.jsx:UnLabel`.

All primitives MUST:
- Accept their data through arguments, never read from `UntypeUIModel` directly.
- Honor `@Environment(\.colorScheme)` for light/dark.
- Use SF Symbols (`mic.fill`, `stop.fill`, `record.circle`, `keyboard`,
  `checkmark.circle.fill`, `exclamationmark.triangle.fill`).

### 1.2 Refactor `UntypeRootView` (`NativeUntypeUILauncher.swift:822`)

Replace the existing HStack body with a `NavigationSplitView`:

```
NavigationSplitView(columnVisibility: $columnVisibility) {
    sidebar
} content: {
    monitorContent
} detail: {
    inspectorPane
}
.toolbar { toolbarContent }
```

- **`sidebar`** — Source list with three items (`Transcript`, `History`,
  `Events`) bound to `model.settings.selectedMonitorTab`. Below the source list:
  a "Status" card (`.thinMaterial`) showing four `UntypeStatusPill` rows
  (Microphone / Accessibility / SONIOX_API_KEY / AZURE_OAI_KEY) backed by
  `model.settings.{microphoneStatus,accessibilityStatus,apiKeyStatus}`.
  Width: 200 pt, persisted via `settings.windowWidth`/`settings.windowHeight`.
- **`monitorContent`** — Switches on `selectedMonitorTab`:
  - `transcript` → existing `transcriptPane` body, but the top bar becomes:
    operator chip row (`UntypeOperatorChip` × 4) on the left, `UntypeWaveformView`
    + dB readout on the right, then a content-toolbar row with `Copy / Save /
    Clear` aligned right. Existing turn rendering (`timelineTurnView`) gets a
    light restyle: time gutter (40 pt, monospaced), `RAW` prefix in muted
    monospace, refined text with 2-pt amber left border per `TranscriptTurn` in
    `main-windows.jsx:232`.
  - `history` → see Phase 4.
  - `events` → see Phase 4.
- **`inspectorPane`** — Existing `settingsPane` reskinned to grouped `Form`
  (see Phase 3). Toggle visibility via `settings.settingsExpanded`.
- **Toolbar** (via `.toolbar`):
  - Leading: `UntypeBrandMark` + "untype" title (so it shows even when title bar
    is hidden by NavigationSplitView).
  - Center: `UntypeStatusPill` cluster — Session, Audio, Output, Permission.
    Each pill computes its tone from existing model state
    (`model.isRunning`, `model.audioStatus`, `model.settings.{clipboard,focusedInput}`,
    `model.settings.{microphoneStatus,accessibilityStatus}`).
  - Trailing: `UntypeRecordButton`, Refresh button (SF Symbol
    `arrow.clockwise`), Inspector toggle (SF Symbol `sidebar.right`).
- **Keep `keyboardShortcut("r", modifiers: [.command])`** on the record button
  for parity with the current build. Add `Cmd+\` for inspector toggle.

### 1.3 Window chrome

Change `NSWindow` creation at `NativeUntypeUILauncher.swift:71-89`:
- Set `window.titleVisibility = .hidden`
- Set `window.titlebarAppearsTransparent = true`
- Set `window.styleMask.insert(.fullSizeContentView)`
- Keep `minSize` at `860 x 620` (current) — the V1 layout still fits.

### 1.4 Active-session disabling rules — UNCHANGED

`UntypeUIControlAvailability(isSessionActive: model.isRunning)` continues to
gate session-shaping controls (provider, model, languages, sample rate,
endpoint detection, protocol mode, translation policy, LLM provider, LLM
model, hotkey, hotkey-enabled). Operator toggles remain editable mid-session.

### 1.5 Persistence — UNCHANGED

`UntypeUISettings.selectedMonitorTab`, `settingsExpanded`, `windowWidth`,
`windowHeight` continue to flow through `model.updateLayout(...)` →
`UntypeUISettingsStore.save`.

### 1.6 Acceptance for Phase 1

- `swift build` succeeds.
- `swift test` passes the existing `TranscriptionSessionRuntimeTests` and
  `UntypeUISettingsStoreTests` without modification.
- Launching `untype ui` shows:
  - Toolbar with brand mark, status pills, record button, refresh, inspector
    toggle.
  - Left sidebar with three navigation entries + a Status card.
  - Center monitor with the existing Transcript view styled per the design.
  - Right inspector (existing settings content, even if not yet restyled).
- Clicking the record button starts a manual session exactly as before; the
  button shape morphs and changes color.
- Toggling Inspector hides/shows the trailing column; the choice survives a
  relaunch (verified by inspecting `ui-state.json`).

## Phase 2 — Overlay HUD

Replace the body of `UntypeOverlayView` (`NativeUntypeUILauncher.swift:1585`)
with the OverlayCard layout from `peripheral.jsx:108-146`:

- Top row, left: 36-pt circle, recording-tint background, recording-red
  border, white square inside.
- Top row, center: `Push-to-talk` heading + `soniox · {elapsed} · sec_xxxxxx`
  metadata in monospace.
- Top row, right: `UntypeWaveformView` (14 bars, 22 pt).
- Middle: live transcript text in a `.thinMaterial` capsule, 17-pt body.
- Bottom row, left: four `UntypeOperatorChip` views (small size) for R/T/C/I.
- Bottom row, right: `release to submit` in monospaced 10.5 pt, muted.

Constraints to preserve from `UntypeOverlayLayout`:
- Width and wrap rules (`layout.width`, `layout.anchoredPanelFrame`).
- Bottom-left anchor stability while text grows vertically (plan-007, plan-010).
- `panel.ignoresMouseEvents = true` MUST remain `true`.
- `panel.level = .statusBar` MUST remain.

Add accessibility labels:
- `.accessibilityLabel("Push-to-talk overlay, \(phase), \(text)")` on the root.
- `.accessibilityLabel("Operator \(letter), \(enabled ? "on" : "off")")` on each
  chip.

Add a warning-state branch: when `model.events.last?.contains("warning")`, show
a small amber `exclamationmark.triangle.fill` next to the phase label.

### 2.1 Acceptance for Phase 2

- Pressing the hotkey shows the new HUD layout.
- HUD frame matches `UntypeOverlayLayout` exactly (no regression in plan-008,
  plan-010, plan-011 behavior).
- Long transcripts wrap and grow upward; bottom anchor stays put.
- Mouse over the HUD does not steal focus from the underlying window.

## Phase 3 — Inspector Polish

Refactor `settingsPane` (`NativeUntypeUILauncher.swift:1158`) to a SwiftUI
`Form` with `.formStyle(.grouped)`:

Sections, in order, matching `main-windows.jsx:V1Inspector` and
`screens.jsx:SettingsProviders`:

1. **Session** — read-only KV: State (with dot), Mode, STT provider, Model,
   Language, Sample rate, Endpoint detection.
2. **Refinement** — LLM toggle, Provider picker, Model text field, Translation
   target picker. Disabled when `isSessionActive`.
3. **Operators** — Four `Toggle` rows for R/T/C/I (always enabled per current
   rule).
4. **Push-to-talk** — Enabled toggle, Hotkey text field, fallback button,
   status footer.
5. **Permissions** — Microphone, Accessibility, Input Monitoring. Each row uses
   an `UntypeStatusPill`. If `microphoneStatus != "granted"`, add a "Open
   System Settings" button using `NSWorkspace.shared.open(URL(string:
   "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)`.
6. **Config source** — monospaced read-only display of
   `~/.tool-agents/untype/.env` path; only shown if storage source is
   `user .env`.

Inspector width drops from 360 → 300 pt to reclaim content space, but is
gated on `settings.windowWidth >= 1000` (still respect 860 minimum).

## Phase 4 — History + Events refinement

- **History** (`historyPane`): replace card-only grouping with a two-column
  layout — leading 56-pt time/status gutter, main column with "User said" and
  "Processed" rows separated by a subtle divider. Use `DisclosureGroup` for
  long turns (collapsed by default if turn text > 280 chars).
- **Events** (`eventsPane`): add a filter `Picker` (segmented control) above
  the log: `All / Warnings / Provider / Audio / Hotkey / Protocol`. Filter is
  pure UI — does not change retention or the underlying `model.events` array.
  Persist the choice in a new `UntypeUISettings.selectedEventsFilter` field
  (additive, defaulting to `"all"`).

## Phase 5 — Onboarding + Mini Window

### 5.1 Onboarding

Show a full-window cover (`.sheet` on the root view, not modal-blocking)
when:
- `model.settings.apiKeyStatus == "missing"`, OR
- `model.settings.microphoneStatus != "granted"`, OR
- `model.settings.accessibilityStatus != "granted"`.

Layout (per `screens.jsx:Onboarding`):
- Hero amber `UntypeBrandMark` (size 64), "Welcome to untype" headline,
  short subtitle.
- Three checklist rows: Provide STT credentials → Grant Microphone →
  Grant Accessibility. Each row has a status icon + "Take action" link.
- Footer: "Skip for now" (dismiss sheet but persist a flag so we don't
  re-prompt for 24h), "Open System Settings".

### 5.2 Compact mini window

Add `UntypeUISettings.compactWindow: Bool` (default `false`, additive). When
true, the main `NSWindow` resizes to 440 × 280 and `UntypeRootView` switches
to the `UntypeMiniView` layout from `peripheral.jsx:UnMini`:
- Title bar with brand mark + "mini" label.
- Status row: brand + state pill + record button.
- Live partial in `.thinMaterial` capsule.
- Operator chip strip + tiny waveform.

Toolbar adds a `rectangle.compress.vertical` button that flips
`compactWindow`. Compact mode forces `settingsExpanded = false` and hides the
sidebar.

## Phase 6 — Verification

- `swift build` — must pass on the project's current toolchain.
- `swift test` — full test suite, no regressions.
- `test_scripts/ui-mode-smoke.md` — extend with explicit visual checks for:
  - Toolbar layout (idle / listening / recording).
  - Sidebar selection persistence across relaunch.
  - Overlay HUD with short text, long wrapped text, and warning state.
  - Inspector collapse + width restore.
  - Onboarding sheet trigger and dismissal.
  - Compact window toggle.
- Capture screenshots for: idle main, listening main, recording overlay,
  finalizing overlay, warning overlay, inspector expanded, inspector collapsed,
  onboarding sheet, compact window.
- Add a "Dependency vetting log" entry to `Issues - Pending Items.md` if any
  new SwiftPM dependency is introduced (none expected for Phase 1–4).

## Out of Scope for This Plan

- Menubar status item / dropdown popover (`peripheral.jsx:UnMenubarDropdown`).
  Tracked separately because it requires `NSStatusItem` infrastructure and a
  decision about whether `untype ui` becomes an `LSUIElement` agent app or
  keeps its regular activation policy.
- V2 (Unified Glass) and V3 (Voice-First) variants. They live in the bundle
  for record-keeping only — only V1 is implemented.
- Light/dark theme switching beyond what macOS provides automatically. The
  design's amber accent should look correct in both because all colors derive
  from a single accent + system materials.

## Risks and Mitigations

| Risk                                                | Mitigation |
|-----------------------------------------------------|------------|
| NavigationSplitView pre-macOS 14 quirks             | We already require recent toolchains for SwiftUI .toolbar; double-check `Package.swift` platforms before merging. |
| Overlay frame regression                            | Phase 2 changes the View body only; `UntypeOverlayLayout` math stays untouched, and existing layout tests catch regressions. |
| Active-session control desync                       | Reuse `UntypeUIControlAvailability` verbatim; no new gating logic. |
| Persistence schema drift                            | `selectedEventsFilter` and `compactWindow` are additive `Bool/String` fields with safe defaults — existing `ui-state.json` files keep loading. |
| Onboarding cover blocking expert relaunch flow      | "Skip for now" sets a 24-hour timestamp; expert users see it once. |
