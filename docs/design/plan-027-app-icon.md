# Plan 027: App Icon

## Provenance
- Refined request: `docs/reference/refined-request-app-icon.md`
- Codebase scan: `docs/reference/codebase-scan-app-icon.md`
- Investigation/research: skipped because the project already has a single established packaging path and no new technology is required.

## Objective
Add a default macOS app icon for packaged `untype.app` bundles while preserving the packaging script's explicit `--icon` override.

## Design Direction
Use a deterministic vector-derived icon instead of an AI-only raster. The selected mark is based on the user-supplied reference icon: a warm orange rounded-square tile with a centered white rounded lowercase `u`. The macOS version adds subtle depth, highlight, and shadow while preserving the simple orange-and-white brand read at small sizes.

## Implementation
1. Add `packaging/macos/AppIcon.svg` as the human-readable source asset.
2. Render `packaging/macos/AppIcon.png` from the SVG for visual review and regeneration input.
3. Generate a full `packaging/macos/AppIcon.iconset/` with standard macOS icon sizes.
4. Compile `packaging/macos/AppIcon.icns` with `iconutil`.
5. Update `scripts/package-macos-app.sh` so `packaging/macos/AppIcon.icns` is used by default when no `--icon` is provided.
6. Keep `--icon` as an explicit override for future final brand or release-channel icons.
7. Update deployment/design/function/issue documentation.

## Files Modified
- `packaging/macos/AppIcon.svg`
- `packaging/macos/AppIcon.png`
- `packaging/macos/AppIcon.iconset/`
- `packaging/macos/AppIcon.icns`
- `scripts/package-macos-app.sh`
- `docs/design/deployment-guide.md`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- The icon source and generated `.icns` are committed under `packaging/macos/`.
- The app packaging script includes `Contents/Resources/AppIcon.icns` by default.
- The app `Info.plist` includes `CFBundleIconFile` set to `AppIcon`.
- The package script still accepts `--icon` overrides.
- The generated archive contains no AppleDouble `._*` entries.
- `swift test` passes.

## Verification
- `iconutil -c icns packaging/macos/AppIcon.iconset -o packaging/macos/AppIcon.icns` passed on 2026-05-27.
- Visual inspection passed for the revised orange `u` reference-based `packaging/macos/AppIcon.png`, `packaging/macos/AppIcon.iconset/icon_128x128.png`, and `packaging/macos/AppIcon.iconset/icon_16x16.png` on 2026-05-27.
- The icon was revised on 2026-05-27 to match the user-provided orange `u` reference, replacing the earlier voice-cursor proposal.
- `scripts/package-macos-app.sh --bundle-id com.example.untype --version 0.1.0 --build 1 --unsigned --skip-tests` passed on 2026-05-27 and included `Contents/Resources/AppIcon.icns`.
- Generated `Info.plist` includes `CFBundleIconFile` set to `AppIcon`.
- The generated zip contains no AppleDouble `._*` entries.
- `bash -n scripts/package-macos-app.sh` passed on 2026-05-27.
- `swift test` passed on 2026-05-27 with 160 tests passing. A prior run showed an unrelated transient failure in `sessionRuntimeSuppressesLatePartialsAfterFallbackSubmission`, and an immediate rerun passed.
