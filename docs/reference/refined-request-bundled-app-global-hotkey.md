# Refined Request: Bundled App Global Hotkey

## Category
Development / Bug Fix

## Objective
Fix or explain the packaged macOS app behavior where push-to-talk does not work while another app has focus, even after Accessibility and Input Monitoring are enabled.

## Scope
- In scope: Inspect and adjust the bundled app launch path, hotkey event-tap setup, and packaging metadata.
- In scope: Preserve `untype ui` CLI behavior and double-click app launch behavior.
- In scope: Ensure the bundled app's declared executable is the same process that installs the Quartz event tap.
- In scope: Update deployment/design/function/issue documentation.
- Out of scope: Changing the hotkey model, adding a global shortcut framework, signing/notarizing without credentials, or changing transcription/runtime behavior.

## Requirements
1. The packaged app must launch UI mode by double-clicking.
2. The packaged app must use `untype` itself as `CFBundleExecutable`, avoiding a launcher-to-main `execv` hop for the running app identity.
3. CLI invocation `untype ui` must still launch the UI.
4. CLI invocation without `ui` from a normal executable path must retain the existing command behavior.
5. The app bundle must still include `untype-input-helper`, `Info.plist`, `PkgInfo`, and `AppIcon.icns`.
6. Documentation must explain that users may need to remove/re-add the app in Accessibility/Input Monitoring after the executable identity changes.

## Constraints
- Do not add runtime dependencies.
- Do not perform version-control operations.
- Do not sign or notarize without release credentials.
- Keep generated package outputs under `.build/deploy/`.

## Acceptance Criteria
1. `scripts/package-macos-app.sh` creates an app whose `CFBundleExecutable` is `untype`.
2. The generated app bundle no longer contains `Contents/MacOS/untype-launcher`.
3. Double-click app launch still opens UI mode because bundled no-argument launches are routed to the native UI.
4. `scripts/package-macos-app.sh --bundle-id com.example.untype --version 0.1.0 --build 1 --unsigned --skip-tests` passes.
5. `swift test` passes.
6. Project issue/design records document the root cause and remediation.

## Assumptions
- The user's permissions were granted to the `.app`, but the current launcher `execv` design can still confuse macOS privacy identity for system-wide keyboard monitoring.
- Using the actual `untype` binary as the bundle executable is more conventional and more likely to align TCC permission identity with the process installing the event tap.

## Open Questions
- Signed/notarized distribution should still be verified on a clean machine before final release.

## Original Request
"both Accessibility and Input Monitoring are enabled 
but still when i try while another app is focused it doesn't work"
