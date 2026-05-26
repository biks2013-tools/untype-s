# Plan 021: macOS Packaging Script

## Provenance
- Refined request: `docs/reference/refined-request-macos-packaging-script.md`
- Deployment guide: `docs/design/deployment-guide.md`
- Investigation/research: skipped because the deployment path was already documented from Apple Developer ID/notarization guidance.
- Codebase scan: focused local scan only; no existing project packaging script or `docs/tools/` tool catalog was present.

## Objective
Add a repeatable repository script that packages the SwiftPM release outputs into a deployable macOS `.app` bundle and optionally signs, notarizes, staples, and verifies it.

## Implementation
1. Add `packaging/macos/untype.entitlements` with the hardened-runtime audio-input entitlement required for microphone capture.
2. Add `scripts/package-macos-app.sh`.
3. Require explicit bundle identifier, version, and build number.
4. Build release products and run tests unless skipped.
5. Create `untype.app` with `untype`, `untype-input-helper`, a generated native launcher that opens UI mode on double-click, `Info.plist`, and optional icon.
6. Sign nested executables and app bundle when a Developer ID identity is provided.
7. Submit to `notarytool`, staple, and produce a final notarized archive when a notary profile is provided.
8. Update deployment documentation and project ledgers.

## Files Modified
- `scripts/package-macos-app.sh`
- `packaging/macos/untype.entitlements`
- `docs/design/deployment-guide.md`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- The script exposes clear `--help` usage.
- Missing bundle identifier, version, or build number fails fast.
- Unsigned local packaging is explicit via `--unsigned`.
- Developer ID signing is supported via `--sign-identity`.
- Notarization/stapling is supported via `--notary-profile`.
- `swift build` succeeds.
- `swift test` passes.

## Verification
- `scripts/package-macos-app.sh --help` passed on 2026-05-26.
- Missing `--bundle-id` fails fast with a clear error on 2026-05-26.
- `scripts/package-macos-app.sh --bundle-id com.example.untype --version 0.1.0 --build 1 --unsigned --skip-tests` passed on 2026-05-26.
- The generated app contains `Info.plist`, `untype`, `untype-input-helper`, and a Mach-O `untype-launcher`.
- The generated zip exists at `.build/deploy/untype-0.1.0.zip`.
- `bash -n scripts/package-macos-app.sh` passed on 2026-05-26.
- `swift test` passed on 2026-05-26 with 130 tests passing.
