# Refined Request: macOS Packaging Script

## Category
Development / Infrastructure

## Objective
Implement a repeatable macOS packaging script for the current SwiftPM project that creates a deployable `untype.app` bundle and optionally signs, notarizes, staples, and verifies the distribution archive.

## Scope
- In scope: Add a repository script under `scripts/`.
- In scope: Build and test the SwiftPM project before packaging unless explicitly skipped.
- In scope: Create `untype.app` with `Info.plist`, release binaries, app launcher, resources folder, and entitlements.
- In scope: Support Developer ID signing and optional `notarytool` notarization/stapling.
- In scope: Update deployment documentation to reference the script.
- Out of scope: Creating an Xcode app target, adding a DMG designer, adding auto-update infrastructure, adding dependencies, or changing runtime/provider behavior.

## Requirements
1. The script MUST require explicit bundle identifier, version, and build number inputs.
2. The script MUST build the release SwiftPM products.
3. The script MUST include both `untype` and `untype-input-helper` in the app bundle.
4. The script MUST make the app double-click launch UI mode.
5. The script MUST generate or include microphone usage metadata and audio-input entitlement.
6. The script MUST support Developer ID signing when a signing identity is provided.
7. The script MUST support notarization when a notary keychain profile is provided.
8. The script MUST verify outputs with available macOS tools.

## Constraints
- Do not add runtime dependencies.
- Do not invent fallback values for release identity settings such as bundle identifier, version, build number, signing identity, or notarization profile.
- Keep generated artifacts under `.build/deploy/` by default.

## Acceptance Criteria
1. Running the script with required bundle/version/build inputs creates an app bundle and zip archive.
2. Running with signing identity signs nested executables and the app bundle.
3. Running with signing identity plus notary profile submits, staples, and creates a final notarized archive.
4. The documentation explains the script usage.

## Assumptions
- The first release channel is Developer ID distribution outside the Mac App Store.
- The project continues to use SwiftPM as the authoritative build system for now.

## Open Questions
- The final production bundle identifier, icon, and Apple Developer Team ID must still be chosen by the project owner.

## Original Request
"can you implement the packaging script ?"
