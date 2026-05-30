---
language: Swift
framework: SwiftUI/AppKit/ApplicationServices/Carbon
package_manager: Swift Package Manager
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/UntypeCore/NativeUntypeUILauncher.swift
last_scanned_commit: 0659ce1eab6e2134651bf85bd23aea6d8c287237
scanned_for_request: refined-request-global-push-to-talk-hotkey-regression
scanned_at: 2026-05-30T11:37:34Z
---

# Codebase Scan: Global Push-To-Talk Hotkey Regression

## Request
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-global-push-to-talk-hotkey-regression.md`
- Goal: restore press-and-hold push-to-talk hotkey detection while another app has keyboard focus.

## Project Overview
`untype-s` is a SwiftPM macOS project. Native UI mode is implemented in `Sources/UntypeCore/NativeUntypeUILauncher.swift`, which owns the AppKit application lifecycle, SwiftUI monitoring window, push-to-talk overlay, warm session lifecycle, and hotkey handling.

## Module Map
- `Sources/UntypeCore/NativeUntypeUILauncher.swift` — native UI, hotkey monitor, Quartz event tap, AppKit fallback monitors, push-to-talk start/stop handlers, and overlay.
- `Sources/UntypeCore/UntypeUISettings.swift` — persisted non-secret UI settings, including `hotkeyEnabled` and `hotkey`.
- `Sources/UntypeCore/MacOSPermissionStatus.swift` — current-process microphone and Accessibility status labels.
- `Sources/UntypeCore/BundledAppLaunch.swift` and `Sources/untype/main.swift` — no-argument app-bundle launch routing to UI mode.
- `scripts/package-macos-app.sh` — packages `untype.app` with `CFBundleExecutable=untype`, preserving the identity used by TCC permissions.
- `docs/design/plan-028-bundled-app-global-hotkey.md` — prior hotkey identity fix and user remediation notes.

## Conventions
- UI hotkey work belongs in `NativeUntypeUILauncher.swift` unless the change becomes large enough to split into a separate macOS module.
- Diagnostics must be privacy-safe and must not log transcript text or secrets.
- The existing `UntypeHotkeySharedState` is the dedupe point for multiple hotkey event sources.
- Build and test through `swift build` and `swift test`.

## Integration Points

### In Scope
- `UntypeHotkeyMonitor.configure(settings:)`
  - Currently installs `UntypeQuartzHotkeyEventTap` when possible and falls back to `NSEvent` global/local monitors.
  - Needs a more reliable global press/release fallback for background focus.
- `UntypeQuartzHotkeyEventTap`
  - Keeps preferred suppressing event-tap behavior.
  - Uses the shared state for press/release dedupe.
- `UntypeHotkeyDescriptor`
  - Parses the configured hotkey, maps key names to `CGKeyCode`, and compares modifiers.
  - Can provide Carbon-compatible key code and modifier masks for a global hotkey fallback.

### Out of Scope
- Transcription runtime, provider adapters, protocol controller, focused-input delivery, and timeline rendering.
- Packaging executable identity, which already uses `CFBundleExecutable=untype`.

## Duplication Check
Global hotkey support is partially implemented through Quartz event taps and AppKit monitors, but there is no Carbon `RegisterEventHotKey` fallback. This leaves the app vulnerable to losing global press/release detection when the event tap is unavailable or blocked and the UI is not focused.

## Recommended Approach
Keep the Quartz event tap as the preferred suppressing path and add a Carbon hotkey registration as an additional global press/release source. Use the existing shared state to dedupe events if both systems fire. Retain AppKit local/global monitors as the last fallback and for local operator hotkey handling.

## Recommended Build/Test Commands
- `swift build`
- `swift test`
