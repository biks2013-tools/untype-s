# Plan 029: Bundled App Focused-Input Delivery

## Provenance
- Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-bundled-app-focused-input-delivery.md`
- Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-bundled-app-focused-input-delivery.md`
- Investigation/research: skipped because the project already has one established focused-input delivery path and the defect localizes to bundled app process identity.

## Objective
Fix bundled `untype.app` sessions so refined and translated protocol output is delivered to the active foreground application when the focused-input operator is enabled.

## Root Cause
The protocol controller already passes the final processed text to focused-input delivery after refinement, translation, or composite refine-plus-translate processing. In bundled app mode, that delivery currently spawns `Contents/MacOS/untype-input-helper`.

That subprocess does the Accessibility and keyboard-event work under the nested helper process identity, while users grant Accessibility/Input Monitoring to `untype.app`. This can leave the app authorized but the helper process untrusted, so processed output appears in the UI but is not inserted into the foreground app.

## Implementation
1. Extend `FocusedInputDelivery` with testable bundled-app detection.
2. When no explicit helper path is supplied and the process is running from a `.app` bundle, execute `FocusedInputHelperMain.run(...)` in-process using stdin-style `Data` construction.
3. Keep the existing helper subprocess path for CLI and unbundled runs.
4. Preserve result/error semantics so expected focused-input failures remain fail-open protocol warnings.
5. Add regression tests for:
   - bundled app helper path resolution from `untype.app/Contents/MacOS/untype`;
   - bundled app delivery using the in-process runner instead of spawning the helper;
   - bundled app detection when `Bundle.main.bundleURL` resolves inside `.app/Contents/MacOS`;
   - non-bundled delivery continuing to use the helper subprocess;
   - browser target detection for paste-keycode-first delivery hardening;
   - `ok=false` focused-input results surfacing as protocol warnings instead of false `input.sent` success;
   - processed text staying out of arguments.

## Files to Modify
- `Sources/UntypeCore/FocusedInputDelivery.swift`
- `Tests/UntypeCoreTests/FocusedInputDeliveryTests.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `docs/design/deployment-guide.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- `swift build` passes.
- `swift test` passes.
- Existing CLI/unbundled helper subprocess behavior is preserved.
- Bundled app UI sessions use the main app process identity for focused-input delivery.
- Documentation records the defect and fix, including the manual permission remediation for rebuilt app bundles.

## Verification
- `swift build` passed on 2026-05-27.
- `swift test` passed on 2026-05-27 with 167 tests passing.
- `scripts/package-macos-app.sh --bundle-id com.example.untype --version 0.1.0 --build 1 --unsigned --skip-tests` passed on 2026-05-27.
- Generated `.build/deploy/untype.app/Contents/Info.plist` has `CFBundleExecutable` set to `untype`.
- Generated `.build/deploy/untype.app/Contents/MacOS` contains both `untype` and `untype-input-helper`.
- Generated `.build/deploy/untype-0.1.0.zip` contains no `untype-launcher`, `__MACOSX`, or AppleDouble `._*` entries.
- `.build/deploy/untype.app/Contents/MacOS/untype --help` prints CLI help and exits zero.

## User Remediation
After installing the rebuilt app, remove old `untype.app` entries from System Settings > Privacy & Security > Accessibility and Input Monitoring, add the rebuilt `/Applications/untype.app`, then quit and relaunch. Focused-input delivery in bundled UI mode now runs under that app identity rather than the nested helper process.
