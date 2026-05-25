---
language: Swift
framework: AppKit + SwiftUI
package_manager: swiftpm
build_command: "swift build"
test_command: "swift test"
lint_command: null
entry_points:
  - "Sources/untype/main.swift"
  - "Sources/untype-input-helper/main.swift"
last_scanned_commit: 27a9633473d1bce257a6e95c07a5fd3fbd9b3b4a
request_file: "docs/reference/refined-request-ui-window-state-persistence.md"
scan_scope: "request-driven"
generated_at: "2026-05-25T10:45:00+03:00"
---

# Codebase Scan - UI Window State Persistence

## 1. Project Overview
`untype-s` is a Swift Package Manager macOS 14 project. The relevant implementation surface for this request is the native UI path in `Sources/UntypeCore`, where AppKit owns the application/window lifecycle and SwiftUI owns the monitoring window content.

The requested behavior extends existing non-secret UI state persistence. It does not require new modules, new dependencies, or changes to the transcription runtime/provider paths.

## 2. Module Map
| Path | Purpose | Representative Symbols |
| --- | --- | --- |
| `Sources/UntypeCore/NativeUntypeUILauncher.swift` | AppKit application delegate, main window construction, SwiftUI root view, UI model, tabbed monitor, settings pane, overlay, and hotkey monitor. | `UntypeAppDelegate`, `UntypeUIModel`, `UntypeRootView` |
| `Sources/UntypeCore/UntypeUISettings.swift` | UI settings model, normalization, session argument projection, credential refresh, and JSON persistence to `ui-state.json`. | `UntypeUISettings`, `UntypeUISettingsPatch`, `UntypeUISettingsStore`, `PersistedUIStateFile` |
| `Tests/UntypeCoreTests/UntypeUISettingsTests.swift` | Focused tests for UI state privacy, config-chain derivation, hotkey normalization, control availability, and UI audio labels. | `uiSettingsStorePersistsOnlyNonSecretFields`, `uiSettingsLoadForUIDerivesInitialStateFromConfigChain` |

## 3. Conventions
- AppKit-specific lifecycle behavior stays in `NativeUntypeUILauncher.swift`. The app delegate creates a titled, resizable `NSWindow`, sets its minimum size, attaches a SwiftUI hosting view, centers it, and shows it. See `Sources/UntypeCore/NativeUntypeUILauncher.swift:51-84`.
- The root SwiftUI view currently keeps settings visibility in local state, so this value is not persisted yet. See `Sources/UntypeCore/NativeUntypeUILauncher.swift:773-789`.
- The monitoring area uses `TabView` without an explicit selection binding, so selected tab is not persisted yet. See `Sources/UntypeCore/NativeUntypeUILauncher.swift:820-834`.
- UI settings are persisted as JSON at `~/.tool-agents/untype/ui-state.json`, and the store intentionally removes transient credential/permission status values from disk. See `Sources/UntypeCore/UntypeUISettings.swift:285-419` and `Tests/UntypeCoreTests/UntypeUISettingsTests.swift:23-54`.

## 4. Integration Points
### In Scope
- `Sources/UntypeCore/UntypeUISettings.swift:4-138` - add non-secret layout fields to the runtime UI settings model, normalization, and patch merging.
- `Sources/UntypeCore/UntypeUISettings.swift:285-419` - extend load/save to include layout fields in the existing persisted UI state file while preserving transient privacy exclusions.
- `Sources/UntypeCore/UntypeUISettings.swift:474-535` - extend the persisted JSON schema to encode/decode the new layout fields.
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:51-84` - restore saved window size at launch and capture resize changes through an AppKit delegate callback.
- `Sources/UntypeCore/NativeUntypeUILauncher.swift:773-834` - bind settings visibility and selected monitor tab to persisted UI settings instead of local-only SwiftUI state.
- `Tests/UntypeCoreTests/UntypeUISettingsTests.swift:23-54` - extend persistence/privacy coverage for window size, settings visibility, and tab selection.

### Out Of Scope
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift`, `SonioxTranscriber.swift`, and `ElevenLabsTranscriber.swift` - runtime/provider behavior is unrelated to window preference persistence.
- `Sources/UntypeCore/FocusedInputDelivery.swift` and `MacOSClipboardWriter.swift` - delivery paths are unaffected.
- Overlay geometry/state persistence is out of scope for this request.

## 5. Duplication Check
No existing implementation persists main window size, settings-pane visibility, or selected monitor tab. The existing `ui-state.json` persistence path is the correct extension point because it already stores non-secret UI preferences.
