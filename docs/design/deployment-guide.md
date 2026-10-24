# Deployment Guide

> Looking for the step-by-step procedure? Use **[`release-runbook.md`](release-runbook.md)** — it is the operational checklist (one-time setup, build, sign, notarize, disk image, install, smoke test, distribute, maintenance calendar). This guide keeps the background, the manual equivalents of what the script does, and the design rationale.

This project currently builds SwiftPM executable products:

- `untype`
- `untype-input-helper`

It does not yet define an Xcode `.app` target. For a deployable macOS application, package the release executable and helper inside an app bundle, sign the nested binaries and bundle with Developer ID, notarize the archive, staple the notarization ticket, and distribute a notarized zip or DMG.

## Recommended Distribution Path

Use Developer ID distribution outside the Mac App Store for the first deployable release. This fits the current project because `untype ui` is a native AppKit/SwiftUI app launched from the executable and needs microphone, Accessibility/Input Monitoring, global hotkey, overlay, and focused-input behavior.

## Prerequisites

- macOS 14 or newer for running the app.
- Xcode or Xcode command-line tools with Swift 6.
- Apple Developer Program membership.
- A Developer ID Application certificate installed in Keychain.
- App Store Connect API key or Apple ID app-specific password configured for `notarytool`.
- A final bundle identifier, for example `com.example.untype`.

Check local signing identities:

```sh
security find-identity -v -p codesigning
```

Store notarization credentials once:

```sh
xcrun notarytool store-credentials "untype-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"
```

For CI, prefer App Store Connect API key credentials instead of an Apple ID password.

## Build Release Binaries

```sh
swift build -c release
```

Expected binaries:

```sh
.build/release/untype
.build/release/untype-input-helper
```

Run the test suite before packaging:

```sh
swift test
```

## Recommended Scripted Packaging

Use the repository packaging script for repeatable builds:

```sh
scripts/package-macos-app.sh \
  --bundle-id "com.example.untype" \
  --version "0.1.0" \
  --build "1" \
  --sign-identity "Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)" \
  --notary-profile "untype-notary"
```

For local app-bundle testing without public distribution signing:

```sh
scripts/package-macos-app.sh \
  --bundle-id "com.example.untype" \
  --version "0.1.0" \
  --build "1" \
  --unsigned
```

The production procedure (used since build 7 on 2026-09-12) signs with the team's Developer ID Application identity and notarizes through the `untype-notary` keychain profile; the script submits, waits, staples, and runs the Gatekeeper assessment itself:

```sh
security find-identity -v -p codesigning   # must list "Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)"
scripts/package-macos-app.sh \
  --bundle-id "com.local.untype" \
  --version "0.1.0" \
  --build "<next CFBundleVersion>" \
  --sign-identity "Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)" \
  --notary-profile untype-notary
osascript -e 'tell application "untype" to quit'
mv /Applications/untype.app .build/deploy/untype.app.previous
ditto .build/deploy/untype.app /Applications/untype.app
spctl --assess --type execute --verbose=4 /Applications/untype.app   # expect "accepted", source=Notarized Developer ID
open -a /Applications/untype.app
```

If `codesign` reports the name as **ambiguous** (since 2026-10-24 the same Developer ID certificate name exists in both the login and the System keychain), pass the SHA-1 of the leaf used since build 13 instead of the name: `--sign-identity 2C7D6068C232BA74073D56085DDBB04E5F14DF30` (check with `security find-identity -v -p codesigning`). Keeping that leaf keeps the TCC grants.

Identity facts (login keychain, verified 2026-09-12):

- `Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)` — expires 2027-02-01. Renew it in Xcode → Settings → Accounts → Manage Certificates (or on developer.apple.com → Certificates) before then, and export a `.p12` backup of the certificate + private key from Keychain Access: Apple cannot re-issue the private key. A renewed certificate changes the signing leaf and therefore requires one more re-grant of Accessibility/Input Monitoring.
- `Apple Development: giorgos.marinos@gmail.com (4LF448TU3N)` — expires 2027-08-15. Usable for local-only builds (`--sign-identity` without `--notary-profile`) but Gatekeeper on other Macs rejects it; prefer the Developer ID procedure above so the TCC identity stays constant.
- The `untype-notary` notarytool profile uses the App Store Connect API key `untype-notary` (Key ID `8X27HG66C4`, Developer role, Issuer ID `4100965f-7ed7-4a45-bd2c-3f7ffab3f1ab`) whose private key is stored at `~/.tool-agents/untype/AuthKey_8X27HG66C4.p8` (mode `0600`, never commit it; Apple allows a single download, so back it up). Re-register it on another machine with `xcrun notarytool store-credentials untype-notary --key <p8> --key-id 8X27HG66C4 --issuer 4100965f-7ed7-4a45-bd2c-3f7ffab3f1ab`; check it with `xcrun notarytool history --keychain-profile untype-notary`.

Distributable outputs: `.build/deploy/untype-0.1.0-notarized.zip` (stapled app inside) and, with `--dmg`, `.build/deploy/untype-0.1.0.dmg`.

### Shareable disk image

Add `--dmg` to the production command above to also produce a drag-to-Applications disk image (`untype-<version>.dmg`) containing the stapled app, an `Applications` shortcut, and `packaging/macos/INSTALL.txt` (end-user install, permission, and credential notes). The image is codesigned with the same identity, submitted to notarization, stapled, and assessed with `spctl --assess --type open --context context:primary-signature`. To rebuild only the image from an already signed and stapled `.build/deploy/untype.app` (no rebuild, no app re-notarization):

```sh
scripts/package-macos-app.sh \
  --bundle-id "com.local.untype" --version "0.1.0" --build "<same build>" \
  --sign-identity "Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)" \
  --notary-profile untype-notary \
  --dmg-only
```

Share the `.dmg`; recipients double-click it, drag the app to Applications, and follow `INSTALL.txt`. Keep `INSTALL.txt` in sync with the onboarding checklist in `NativeUntypeUILauncher` and the credential names in `ConfigResolver`.

## Manual App Bundle Steps

Create a staging folder:

```sh
export APP_NAME="untype"
export BUNDLE_ID="com.example.untype"
export VERSION="0.1.0"
export BUILD="1"
export STAGE="$PWD/.build/deploy"
export APP="$STAGE/$APP_NAME.app"

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
```

Copy binaries:

```sh
cp ".build/release/untype" "$APP/Contents/MacOS/untype"
cp ".build/release/untype-input-helper" "$APP/Contents/MacOS/untype-input-helper"
chmod +x "$APP/Contents/MacOS/untype" "$APP/Contents/MacOS/untype-input-helper"
```

Create `Info.plist`:

```sh
/usr/libexec/PlistBuddy -c "Clear dict" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string untype" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string untype" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string untype records microphone audio only while you start listening or hold the push-to-talk hotkey, then sends it to the configured transcription provider." "$APP/Contents/Info.plist"
```

In the current code, `untype ui` remains the CLI UI entrypoint, and no-argument launches from inside `untype.app` also open UI mode. The app bundle must declare `CFBundleExecutable` as `untype` so the long-running process that installs the Quartz push-to-talk event tap matches the bundled app identity that receives Accessibility/Input Monitoring permissions.

Do not reintroduce an intermediate launcher executable for double-click startup unless the global hotkey path is revalidated with the bundled app identity.

## Create Entitlements

Create `untype.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key>
  <true/>
</dict>
</plist>
```

Only add additional entitlements after testing proves they are required. For this app, microphone capture is the expected hardened-runtime entitlement. Accessibility/Input Monitoring permissions are user-granted in System Settings and should be verified with the bundled signed app identity.

## Sign The App

Set your signing identity:

```sh
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)"
```

Sign nested executables first:

```sh
codesign --force --timestamp --options runtime \
  --entitlements untype.entitlements \
  --sign "$SIGN_IDENTITY" \
  "$APP/Contents/MacOS/untype-input-helper"

codesign --force --timestamp --options runtime \
  --entitlements untype.entitlements \
  --sign "$SIGN_IDENTITY" \
  "$APP/Contents/MacOS/untype"
```

Sign the app bundle:

```sh
codesign --force --timestamp --options runtime \
  --entitlements untype.entitlements \
  --sign "$SIGN_IDENTITY" \
  "$APP"
```

Verify the signature:

```sh
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"
```

Before notarization, `spctl` may still report that the app is not notarized. The code signature itself must be valid before continuing.

## Archive For Notarization

Apple notarization does not accept uploading a bare `.app` bundle directly. Archive it as a zip or put it in a DMG.

Zip path:

```sh
export ZIP="$STAGE/$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
```

## Notarize

Submit and wait:

```sh
xcrun notarytool submit "$ZIP" \
  --keychain-profile "untype-notary" \
  --wait
```

If notarization fails, inspect the log:

```sh
xcrun notarytool log "<submission-id>" \
  --keychain-profile "untype-notary"
```

Fix every signing, hardened-runtime, entitlement, or bundle-layout issue before continuing.

## Staple And Verify

Staple the ticket:

```sh
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
```

Recreate the final distributable zip after stapling:

```sh
export FINAL_ZIP="$STAGE/$APP_NAME-$VERSION-notarized.zip"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"
```

Final verification:

```sh
spctl --assess --type execute --verbose=4 "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

## Smoke Test Before Shipping

On a clean macOS user account or clean machine:

1. Download the final zip from the same channel users will use.
2. Unzip it.
3. Move `untype.app` to `/Applications`.
4. Launch by double-clicking.
5. Confirm the UI opens without Terminal arguments.
6. Grant microphone permission when prompted.
7. Grant Accessibility/Input Monitoring permissions in System Settings if needed. If replacing an older build, remove the old `untype.app` entries from both panes, add the rebuilt `/Applications/untype.app`, then quit and relaunch before testing the global hotkey.
8. Configure provider credentials in the documented config locations.
9. Start a session and confirm live transcription.
10. Hold and release the push-to-talk hotkey.
11. Confirm the overlay appears and disappears.
12. Confirm clipboard output works when enabled.
13. Confirm focused-input delivery works in a real target app. Bundled app UI sessions perform this delivery in the `untype.app` process, so the permission entry to verify is the rebuilt `untype.app`, not the nested `untype-input-helper`.
14. Quit and relaunch; verify non-secret UI settings persist.

Use `test_scripts/ui-mode-smoke.md` as the manual smoke-test checklist and extend it with signed-app checks before the first release.

## Recommended Repository Changes Before First Release

1. Decide the final bundle identifier and app name (still `com.local.untype`; changing it resets every user's TCC grants, so do it in one deliberate release).
2. Review whether the default `packaging/macos/AppIcon.icns` is the final public-release brand icon; if not, pass the replacement to `scripts/package-macos-app.sh --icon`.
3. Add a CI release job that runs build, tests, app bundle creation, signing, notarization, stapling, and final verification (today the runbook is executed by hand).
4. ~~Decide whether to distribute `.zip`, `.dmg`, or both.~~ Done 2026-09-12: the notarized `.dmg` is the primary artifact (GitHub Releases + Homebrew cask), the notarized `.zip` is attached to each release as an alternative.
5. ~~Document end-user installation and permission setup in `README.md`.~~ Done 2026-09-12: README "Install (end users)", `packaging/macos/INSTALL.txt` inside the image, release notes, and the in-app welcome guide.

## Deployment Summary

For local testing, `swift build -c release` is enough.

For a real deployable macOS app, ship only after:

1. The release binaries are inside `untype.app`.
2. `Info.plist`, `PkgInfo`, and entitlements are correct.
3. All nested code and the app bundle are Developer ID signed with hardened runtime.
4. The archive is notarized by Apple.
5. The notarization ticket is stapled.
6. Gatekeeper verification passes.
7. Manual live UI, microphone, hotkey, overlay, clipboard, and focused-input smoke tests pass on a clean machine.
