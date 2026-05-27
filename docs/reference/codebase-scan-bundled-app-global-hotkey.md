---
language: Swift
framework: SwiftPM, AppKit/SwiftUI, Quartz Event Services
package_manager: Swift Package Manager
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/UntypeCore/NativeUntypeUILauncher.swift
  - scripts/package-macos-app.sh
last_scanned_commit: b2552f10ccbd697af06fc0037da1d062ada846d7
request_file: docs/reference/refined-request-bundled-app-global-hotkey.md
scan_scope: bundled app push-to-talk global hotkey
generated_at: 2026-05-27T13:25:00Z
---

# Codebase Scan: Bundled App Global Hotkey

## Summary

The native UI uses a Quartz `CGEvent.tapCreate` session event tap for true system-wide push-to-talk press/release detection. If that tap cannot start, the UI falls back to `NSEvent` local/global monitors and press-to-toggle behavior. The fallback is not equivalent for another focused app.

The current app packaging script declares `CFBundleExecutable` as a generated `untype-launcher` binary, then that launcher calls `execv` into `Contents/MacOS/untype ui`. This means LaunchServices starts one bundle executable, but the process image that installs the event tap is a different nested executable. For macOS Accessibility/Input Monitoring permission identity, the safer conventional bundle shape is to declare `untype` itself as `CFBundleExecutable` and make no-argument app-bundle launches enter UI mode directly.

## Module Map

| Path | Role | Relevance |
| --- | --- | --- |
| `Sources/untype/main.swift` | Thin executable entry point dispatching `ui` to `NativeUntypeUILauncher` and other args to `UntypeCommand`. | In scope. Needs app-bundle no-arg UI launch detection. |
| `Sources/UntypeCore/NativeUntypeUILauncher.swift` | Native UI, permissions display, hotkey monitor, Quartz event tap, fallback monitors. | In scope for explanation and status behavior; no direct hotkey logic change needed. |
| `scripts/package-macos-app.sh` | Builds release binaries and creates `untype.app`. | In scope. Needs `CFBundleExecutable=untype` and removal of generated launcher. |
| `Sources/UntypeCore/MacOSPermissionStatus.swift` | Reports microphone and Accessibility status. | Context. Shows `AXIsProcessTrusted()` state, not event-tap success by itself. |
| `docs/design/deployment-guide.md` | Deployment and permission guidance. | In scope for remediation instructions. |
| `docs/design/project-design.md` | Design record. | In scope. |
| `docs/design/project-functions.md` | Functional requirements ledger. | In scope. |
| `Issues - Pending Items.md` | Issue and dependency log. | In scope. |

## Evidence

- `UntypeHotkeyMonitor.configure` warns if `AXIsProcessTrusted()` is false, then attempts to start `UntypeQuartzHotkeyEventTap`.
- If `tap.start()` succeeds, the UI status is `global event tap ready`.
- If `tap.start()` fails, the UI status is `fallback monitor active; press again if release is blocked`, and `NSEvent` monitors are installed instead.
- `UntypeQuartzHotkeyEventTap.start` calls `CGEvent.tapCreate` with `.cgSessionEventTap` and `.defaultTap` over key down/up/flags changed events.
- `scripts/package-macos-app.sh` currently creates and signs/copies a generated `untype-launcher`, and writes `CFBundleExecutable` as `untype-launcher`.

## Integration Points

### In Scope

- Add a small testable helper in `UntypeCore` to decide when a launch should enter UI mode:
  - explicit `untype ui`;
  - app-bundle launch with no arguments;
  - app-bundle launch with only legacy LaunchServices process-serial-number args.
- Update `Sources/untype/main.swift` to use that helper.
- Update packaging so `CFBundleExecutable` is `untype`.
- Remove generated launcher creation/signing from packaging.
- Update docs and issue records.

### Out of Scope

- Changing the event-tap implementation.
- Adding entitlements for Accessibility/Input Monitoring; these remain user-granted macOS privacy permissions.
- Signing/notarization verification without credentials.

## Duplication Check

The global hotkey feature already exists. The likely broken behavior is in the packaged launch identity, not a missing second implementation.
