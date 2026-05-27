# Plan 028: Bundled App Global Hotkey

## Provenance
- Refined request: `docs/reference/refined-request-bundled-app-global-hotkey.md`
- Codebase scan: `docs/reference/codebase-scan-bundled-app-global-hotkey.md`
- Investigation/research: skipped because the project already has one established hotkey path and the issue localized to packaging/runtime launch identity.

## Objective
Fix packaged-app push-to-talk behavior when another application has focus by aligning the macOS app bundle executable identity with the process that installs the Quartz event tap.

## Root Cause
The packaging script previously generated `Contents/MacOS/untype-launcher`, declared it as `CFBundleExecutable`, and then used `execv` to replace the process with `Contents/MacOS/untype ui`.

That made double-click launch work, but it also meant LaunchServices/TCC saw one bundle executable while the running process that installed the global keyboard event tap was a different nested executable. For Accessibility/Input Monitoring, the safer shape is a conventional app bundle where `CFBundleExecutable` is the actual long-running executable.

## Implementation
1. Add `Sources/UntypeCore/BundledAppLaunch.swift` with testable launch-mode detection.
2. Update `Sources/untype/main.swift` so:
   - explicit `untype ui` still launches the native UI;
   - no-argument launches from a `.app` bundle launch the native UI;
   - legacy LaunchServices `-psn_*` app-launch arguments also launch the native UI;
   - normal CLI invocations outside an app bundle keep existing behavior.
3. Update `scripts/package-macos-app.sh` so:
   - `CFBundleExecutable` is `untype`;
   - no generated `untype-launcher` is created;
   - no `swiftc` dependency is required for packaging;
   - signing signs `untype`, `untype-input-helper`, and the app bundle only.
4. Add regression coverage for bundled app launch-mode routing.
5. Update deployment and design documentation.

## Files Modified
- `Sources/UntypeCore/BundledAppLaunch.swift`
- `Sources/untype/main.swift`
- `Tests/UntypeCoreTests/UntypeCommandTests.swift`
- `scripts/package-macos-app.sh`
- `docs/design/deployment-guide.md`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- `swift test` passes.
- `scripts/package-macos-app.sh --bundle-id com.example.untype --version 0.1.0 --build 1 --unsigned --skip-tests` passes.
- Generated `Info.plist` has `CFBundleExecutable` set to `untype`.
- Generated `Contents/MacOS` contains `untype` and `untype-input-helper`, not `untype-launcher`.
- Generated zip contains no `untype-launcher` and no AppleDouble `._*` entries.
- Running the bundled executable with explicit `--help` still shows CLI help.

## Verification
- `bash -n scripts/package-macos-app.sh` passed on 2026-05-27.
- `swift test` passed on 2026-05-27 with 161 tests passing.
- `scripts/package-macos-app.sh --bundle-id com.example.untype --version 0.1.0 --build 1 --unsigned --skip-tests` passed on 2026-05-27.
- Generated `Info.plist` contains `CFBundleExecutable => "untype"`.
- Generated `Contents/MacOS` contains only `untype` and `untype-input-helper`.
- Generated zip contains no `untype-launcher` and no AppleDouble `._*` entries.
- `.build/deploy/untype.app/Contents/MacOS/untype --help` prints CLI help and exits zero.

## User Remediation
After installing the rebuilt app, remove the old `untype.app` entry from System Settings > Privacy & Security > Accessibility and Input Monitoring, add the rebuilt `/Applications/untype.app`, then quit and relaunch. This is required because the app executable identity changed from `untype-launcher` to `untype`.
