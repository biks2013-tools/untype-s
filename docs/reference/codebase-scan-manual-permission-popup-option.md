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
last_scanned_commit: 0659ce1eab6e2134651bf85bd23aea6d8c287237
scanned_for_request: refined-request-manual-permission-popup-option
scanned_at: 2026-05-30T11:46:57Z
---

# Codebase Scan: Manual Permission Popup Option

## Request
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-manual-permission-popup-option.md`
- Goal: add a user-facing option to manually activate the existing permission-management popup/sheet.

## Project Overview
The native UI is implemented in `Sources/UntypeCore/NativeUntypeUILauncher.swift`. The app already has an onboarding/permission setup sheet, `UntypeOnboardingView`, presented from `UntypeRootView` when credential, microphone, or Accessibility status needs attention and the sheet was not recently skipped.

## Module Map
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
  - `UntypeRootView.showOnboarding` owns sheet presentation.
  - `evaluateOnboarding()` controls automatic presentation and respects `UntypeOnboardingView.recentlySkipped()`.
  - `settingsPane` contains the right inspector.
  - The `Permissions` inspector group already displays Microphone, Accessibility, and Input Monitoring status rows.
  - `UntypeOnboardingView` is the existing popup/sheet for permission and setup issues.
- `Sources/UntypeCore/UntypeUISettings.swift`
  - Stores transient permission labels on the in-memory settings model but excludes them from persisted UI state.
- `Tests/UntypeCoreTests/UntypeUISettingsTests.swift`
  - Verifies permission status is not persisted.

## Conventions
- UI-only actions should stay inside `UntypeRootView` when they control local sheet state.
- Permission-management UI must not persist transient permission status.
- Use existing SwiftUI controls and symbols.
- Build and test with `swift build` and `swift test`.

## Integration Points

### In Scope
- `UntypeRootView`
  - Add a manual presentation helper that refreshes status and sets `showOnboarding = true`.
  - This helper intentionally bypasses the automatic 24-hour skip check.
- `settingsPane` Permissions group
  - Add a compact option/button such as “Open Permission Setup” below the existing permission rows.

### Out of Scope
- `UntypeOnboardingView` layout and content, unless minor text/action fixes are required.
- Permission status resolution in `UntypeUISettings`.
- macOS TCC APIs, focused-input delivery, hotkey detection, transcription runtime, and provider code.

## Duplication Check
The permission-management popup already exists as `UntypeOnboardingView`. The requested feature is not a new popup; it should add a manual activation path to the existing sheet.

## Recommended Build/Test Commands
- `swift build`
- `swift test`
