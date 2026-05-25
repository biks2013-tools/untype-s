---
language: Swift
framework: SwiftUI/AppKit
package_manager: Swift Package Manager
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/UntypeCore/NativeUntypeUILauncher.swift
last_scanned_commit: null
request_file: ~/aiwork/coding-platform/untype-s/docs/reference/refined-request-ui-session-conversation-history-tab.md
scan_scope: request-driven UI/session-history integration scan
generated_at: 2026-05-25T00:00:00+03:00
---

# Codebase Scan: UI Session Conversation History Tab

## Metadata Notes
- Git commit detection was intentionally not run because the project instructions prohibit version-control operations unless explicitly requested.
- The project is a SwiftPM package with no third-party runtime dependencies in `Package.swift`.
- Build and test commands are documented in `README.md` and match the SwiftPM manifest.

## Module Map

### `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- Owns the native `untype ui` model, SwiftUI monitoring layout, session controls, export actions, and AppKit integration.
- `UntypeUIModel` retains session-local UI state, including `timeline`, `events`, and selected UI settings at lines 180-189.
- `updateLayout(...)` persists non-secret layout fields, including selected monitor tab, at lines 233-250.
- `clearTranscriptTimeline()` clears the grouped timeline and latest transcript at lines 342-347.
- The current monitor area is a `TabView` with `Transcript` and `Events` tabs at lines 854-870.
- `transcriptPane` renders the timeline, exposes Copy/Save/Clear, and scrolls to the latest turn or partial at lines 872-923.
- `eventsPane` renders retained event lines and export controls at lines 925-968.
- Timeline bubble rendering is centralized in `timelineTurnView`, `timelineBubbleView`, `livePartialView`, and `bubbleBackground` at lines 970-1033.
- `monitorTabBinding` binds the `TabView` selection to persisted UI layout settings at lines 1260-1265.

### `Sources/UntypeCore/UntypeUITimeline.swift`
- Owns the in-memory grouped transcript timeline.
- `UntypeUITimelineBubbleKind` currently classifies `.raw`, `.processed`, and `.error` bubbles at lines 3-7.
- `UntypeUITimelineBubble`, `UntypeUITimelineTurn`, and `UntypeUILivePartial` define the session-local UI transcript data model at lines 9-30.
- `UntypeUITimelineState` retains `turns`, live `partial`, clear state, and monotonic UI IDs at lines 32-48.
- `visibleItemCount` and `exportPlainText()` already derive readable content without persisting the retained transcript at lines 50-82.
- `commitFinal(...)` records dictated/raw user text at lines 100-103.
- `commitProcessed(...)` records refine/translate processed output as a `.processed` bubble labeled `Processed output` at lines 105-119.
- `commitError(...)`, `sealCurrentTurn()`, `clearPartial()`, and `clear()` manage warnings, turn boundaries, and visible-history clearing at lines 121-151.

### `Sources/UntypeCore/UntypeUISettings.swift`
- Owns persisted non-secret UI settings.
- `selectedMonitorTab` is a string field on `UntypeUISettings` at line 30 and defaults to `transcript` at line 59.
- `normalized()` validates and stores the monitor tab through `normalizeMonitorTab(...)` at lines 62-100.
- `normalizeMonitorTab(...)` currently accepts only `transcript` and `events` at lines 789-795.
- Persisted UI state intentionally includes layout choices but not transcript/event contents.

### `Sources/UntypeCore/UntypeUIExport.swift`
- Owns transcript/events export document construction.
- Transcript export already derives text from `UntypeUITimelineState.exportPlainText()` and returns nil for empty content.
- No change is required unless history-specific export is requested later.

### `Tests/UntypeCoreTests`
- `UntypeUITimelineTests.swift` covers grouping raw and processed output, clear behavior, and plain-text export.
- `UntypeUISettingsTests.swift` covers non-secret persistence, selected monitor tab validation, and persisted monitor state restoration.
- `UntypeUIExportTests.swift` covers transcript/events export actions.

## Conventions
- UI state models are plain Swift structs using `Equatable` and `Sendable` where practical.
- Session transcript content is kept in memory and excluded from `ui-state.json`; only explicit user export writes transcript/events.
- SwiftUI UI sections use compact `VStack`/`HStack` layouts, text selection for transcript/event content, and 6px rounded rectangles.
- Tests use the Swift Testing package (`import Testing`) and focused pure-model coverage where possible.
- Configuration validation raises `UntypeError.invalidConfiguration`; no fallback configuration values are introduced for invalid persisted values.

## Integration Points

### In Scope
- `Sources/UntypeCore/UntypeUITimeline.swift`
  - Add a derived current-session history representation or formatter that maps retained turns into user/raw and refine/translate processed history entries.
  - Reuse existing `turns`, `.raw`, `.processed`, and `.error` bubbles. Do not create a second persisted history store.
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
  - Add a third monitor tab backed by the existing `timeline`.
  - Render an empty state when no retained turns/partials exist.
  - Reuse existing clear behavior through `clearTranscriptTimeline()`.
- `Sources/UntypeCore/UntypeUISettings.swift`
  - Accept the new selected monitor tab value so tab selection can persist.
  - Keep transcript/history content excluded from the persisted settings payload.
- `Tests/UntypeCoreTests/UntypeUITimelineTests.swift`
  - Add model coverage for derived conversation-history content.
- `Tests/UntypeCoreTests/UntypeUISettingsTests.swift`
  - Update/extend selected monitor tab validation and persistence coverage for the new tab.
- `docs/design/project-design.md`, `docs/design/project-functions.md`, `Issues - Pending Items.md`
  - Register the feature and document the session-local/no-persistence behavior.

### Out of Scope
- Provider adapters (`SonioxTranscriber.swift`, `ElevenLabsTranscriber.swift`) do not need changes.
- LLM refiner implementations (`LLMRefiners.swift`) do not need changes; history displays already recorded outputs rather than changing processing.
- Runtime protocol controller behavior does not need changes unless timeline data proves insufficient.
- Export functionality does not need to add a history export action for this request.

### New Integration Point
- A small history model/view can be added beside the existing timeline model and UI helpers. The preferred landing site is `UntypeUITimeline.swift` for the derived data and `NativeUntypeUILauncher.swift` for rendering.

## Duplication Check
- The requested data is partially implemented as the grouped transcript timeline. A parallel conversation-history store would duplicate existing session-local data.
- The implementation should extend the existing timeline derivation and monitoring `TabView`.
