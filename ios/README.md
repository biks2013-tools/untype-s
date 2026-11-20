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

First version: dictation with live text (Soniox), Refine / Translate, the
dictionary, Copy and Share; keys in the Keychain. It uses `UntypeCore` from
the package one folder up. Checked in the simulator with spoken audio;
installed on devices, not yet used there.
