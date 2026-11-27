# untype for iPhone and iPad

The iOS app lives in this folder of the untype repository, next to the macOS
app, so both can use the same Swift code (plan: `docs/plans/plan-075-untype-for-iphone-and-ipad.md`).

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and is not kept in git.

```
cd ios
xcodegen generate
open untype-ios.xcodeproj
```

Simulator, from the command line:

```
xcodebuild -project untype-ios.xcodeproj -scheme untype \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Device (paired with this Mac, Developer Mode on):

```
xcodebuild -project untype-ios.xcodeproj -scheme untype -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath <folder> \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <udid> <folder>/Build/Products/Release-iphoneos/untype.app
```

## State

Meetings (2026-11-26, FR-84): the Meetings tab records a meeting with one tap
(or the "Record meeting" shortcut: Siri, Shortcuts, Action button), with a live
transcript that can be switched on or off during the recording, and saves it in
the Mac's meeting format for untype studio (see `docs/design/project-design.md`,
"Meetings on the iPhone and iPad"). Simulator test:
`SIMCTL_CHILD_UNTYPE_TEST_MEETING_SECONDS=25 xcrun simctl launch …`
(`SIMCTL_CHILD_UNTYPE_TEST_MEETING_TRANSCRIPT=0` for audio only).

First version: dictation with live text (Soniox), Refine / Translate, the
dictionary, Copy and Share; keys in the Keychain. It uses `UntypeCore` from
the package one folder up. Checked in the simulator with spoken audio;
installed on devices, not yet used there.
