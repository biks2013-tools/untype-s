# Refined Request: App Icon

## Category
Design / Development

## Objective
Create and wire a standard macOS application icon for the `untype` app so packaged `.app` bundles include a polished default icon without requiring a caller-provided `--icon` argument.

## Scope
- In scope: Create a proposed icon concept suitable for the current macOS utility app.
- In scope: Add project-local icon source and generated macOS icon artifacts.
- In scope: Update the existing macOS packaging script to use the project icon by default while preserving `--icon` override support.
- In scope: Update project design, functional requirements, deployment guidance, and pending-item records.
- Out of scope: Final brand identity, trademark review, App Store marketing artwork, multiple icon concepts, or redesigning the in-app brand mark.

## Requirements
1. The icon must be committed under the existing `packaging/macos/` packaging area.
2. The packaged app must include `Contents/Resources/AppIcon.icns` by default.
3. The package script must still allow a caller to override the default icon with `--icon`.
4. The icon must remain buildable from a human-readable source asset.
5. The icon must be appropriate for a speech-to-text/focused-input macOS utility.
6. No new runtime dependency may be added.

## Constraints
- Preserve the existing SwiftPM-based packaging approach.
- Do not add package-manager dependencies for icon generation.
- Keep generated release artifacts under `.build/deploy/`.
- Do not perform signing or notarization without release credentials.

## Acceptance Criteria
1. A project icon source exists under `packaging/macos/`.
2. A usable `AppIcon.icns` exists under `packaging/macos/`.
3. Running `scripts/package-macos-app.sh --bundle-id com.example.untype --version 0.1.0 --build 1 --unsigned --skip-tests` includes `Contents/Resources/AppIcon.icns`.
4. The generated bundle `Info.plist` includes `CFBundleIconFile` set to `AppIcon`.
5. The package archive includes the icon and contains no AppleDouble `._*` metadata entries.
6. `swift test` passes.

## Assumptions
- A deterministic vector-derived icon is preferable to an AI-only raster image for a production app icon because it is scalable, repeatable, and easy to revise.
- The final icon direction should follow the user-provided orange `u` reference while adapting it to a standard macOS icon size and depth treatment.
- The existing packaging script remains the authoritative app-bundle creation path.

## Open Questions
- The project owner may still choose a different final brand direction before public release.

## Original Request
"I want you to fix the icon for the app 
can you create and suggest soimething ?"
