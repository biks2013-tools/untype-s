---
language: Swift
framework: SwiftPM, AppKit/SwiftUI
package_manager: Swift Package Manager
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/untype-input-helper/main.swift
  - scripts/package-macos-app.sh
last_scanned_commit: b2552f10ccbd697af06fc0037da1d062ada846d7
request_file: docs/reference/refined-request-app-icon.md
scan_scope: app icon packaging integration
generated_at: 2026-05-27T07:50:00Z
---

# Codebase Scan: App Icon

## Summary

`untype-s` is a SwiftPM macOS project with two executable products, `untype` and `untype-input-helper`. The project already has a repository packaging script that creates `untype.app`, writes `Info.plist`, and supports an optional caller-provided `--icon path/to/AppIcon.icns`.

No committed app icon source or default `AppIcon.icns` exists yet. The correct integration point is the existing macOS packaging area rather than source-code UI changes.

## Module Map

| Path | Role | Relevance |
| --- | --- | --- |
| `scripts/package-macos-app.sh` | Builds SwiftPM release products, creates `untype.app`, writes app metadata, signs/notarizes when configured. | In scope. Already supports `--icon`, but has no default project icon. |
| `packaging/macos/untype.entitlements` | Hardened-runtime audio-input entitlement used by packaging. | In scope as packaging peer location. |
| `docs/design/deployment-guide.md` | Deployment and packaging instructions. | In scope for documenting the default icon. |
| `docs/design/project-design.md` | Current design record. | In scope for recording the icon packaging decision. |
| `docs/design/project-functions.md` | Functional requirement ledger. | In scope for registering icon packaging behavior. |
| `Issues - Pending Items.md` | Pending/completed issue ledger and dependency vetting log. | In scope for documenting the issue and no-dependency outcome. |
| `Sources/UntypeCore/NativeUntypeUILauncher.swift` | Native UI and in-window brand mark. | Out of scope; the request concerns the macOS app bundle icon, not the in-app brand mark. |

## Existing Behavior

- `scripts/package-macos-app.sh` accepts `--icon`, verifies the provided file exists, copies it to `Contents/Resources/AppIcon.icns`, and emits `CFBundleIconFile` only when `ICON_PATH` is non-empty.
- `docs/design/deployment-guide.md` currently lists adding an app icon as a recommended pre-release change.
- Generated app bundles currently omit `Contents/Resources/AppIcon.icns` unless the packager passes `--icon`.

## Integration Points

### In Scope

- Add `packaging/macos/AppIcon.svg` as the human-readable icon source.
- Add `packaging/macos/AppIcon.iconset/` and `packaging/macos/AppIcon.icns` as generated macOS icon artifacts.
- Update `scripts/package-macos-app.sh` so the default icon path is `packaging/macos/AppIcon.icns` when present, while `--icon` still overrides it.
- Update deployment/design/function/issue records.

### Out of Scope

- Replacing UI controls or the SwiftUI titlebar brand mark.
- Adding a new asset-generation tool.
- Signing or notarizing the app.
- Choosing final public-release brand identity.

## Conventions

- Packaging assets belong under `packaging/macos/`.
- Packaging output remains under `.build/deploy/`.
- The package script fails fast for required release identity inputs and avoids configuration fallbacks for release settings.
- No new runtime dependency should be introduced for this icon work.

## Duplication Check

The requested feature is partially implemented: the script already supports an icon override, but no default icon asset exists. The work should extend the existing packaging script rather than creating a parallel app-bundle workflow.
