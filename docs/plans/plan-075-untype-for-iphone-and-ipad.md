# Plan 075 - untype for iPhone and iPad

Date: 2026-11-20. Status: first version built and installed on the user's iPhone and two iPads (development build 0.1.0, build 1); not yet used on a device. Scope and bundle identifier confirmed by the user.

## Request

Start a project for an iOS version of untype, next to the macOS app or inside its folder, whichever is easier to manage, and say how it is installed on an iPad and an iPhone.

## Decisions

1. **Same repository, folder `ios/`.** The speech providers, the model calls (Refine, Translate, Ask), the dictionary, the prompts and the meeting transcript are Swift code with no macOS dependency in themselves; a second repository would have to import them as a package and release the two in step. One repository gives one history, one issue register and one set of tests.
2. **The Xcode project is generated** (`ios/project.yml`, XcodeGen 2.46, already installed; a build tool, not a dependency of the app). `*.xcodeproj` is already ignored by git, and a YAML file can be reviewed and merged where a `.pbxproj` cannot.
3. **Signing team `9F9H8NCAUB`** (the team of the macOS Developer ID certificate), automatic signing. Bundle identifier `com.biks2013.untype` (confirmed by the user). The development build is signed with the team's wildcard profile.
4. **iOS 17 or later, iPhone and iPad** in one app.

## What iOS allows, and what it does not

- No global hotkey and no typing into another app's field. The macOS push-to-talk into the focused field has no direct equivalent.
- A **custom keyboard** can insert text into any app, but a keyboard extension cannot use the microphone. Apps of this kind open their own app to record and come back.
- An app can record only its own microphone: there is no capture of another app's sound, so a call on the device cannot be recorded as the "System" side. A meeting in the room can.
- Other ways in: the Action Button, a Control Center control, Shortcuts (App Intents), the share sheet.

## Shared code (measured 2026-11-20)

`Sources/UntypeCore` is one target of 66 files; 19 import AppKit, ApplicationServices, Carbon or ScreenCaptureKit. The other files do not compile without them yet: a few types they use (`TextRefining`, `FocusedInputDeliveryResult`, `UntypeTurnContext` and what it holds, `HandsFreePreferences`, `UntypePermissionStatus`) are declared in macOS files, and `UntypeAEC` is built for macOS arm64 only.

Step proposed: keep one package and one module; add iOS to its platforms; put the macOS-only files inside `#if os(macOS)`; move the few shared declarations to files of their own; make `UntypeAEC` a macOS-only dependency. On macOS this changes no code that runs, and the 514 tests check it. Configuration on iOS: keys in the Keychain, entered in the app; `~/.tool-agents` does not exist there.

## Steps

1. Done: `ios/` project (XcodeGen), SwiftUI app.
2. Done: `UntypeCore` builds for iOS. `Package.swift` lists iOS 17; `UntypeAEC` is linked on macOS only; 35 macOS-only files are inside `#if os(macOS)` (also the second half of `TranscriptionSessionRuntime.swift` and of `ReleaseLatencyLogger.swift`); `TextRefining` moved to its own file; `FileManager.untypeHomeDirectory` (`UntypeHome.swift`) replaces `homeDirectoryForCurrentUser` (the home folder on macOS, Application Support on iOS). No code that runs on macOS changed; 514/514 tests.
3. Done: first version in the app (`ios/UntypeApp`):
   - `DictationEngine`: tap to start, tap to finish; microphone (`AVFoundationAudioSource`, 16 kHz) to Soniox (`SonioxTranscriber`, `stt-rt-v6`), live text; the audio captured while Soniox connects waits in a queue; the dictionary's words go to Soniox and the text is corrected (`DictionaryCorrector`).
   - Refine, Translate (to English or Greek), or both in one call, with the Mac app's prompts (`LLMRefinerFactory`); Undo puts the text back.
   - The text can be edited; Copy, Share, Clear.
   - Settings: Soniox key, languages, model provider (DeepSeek, Google Gemini, Azure OpenAI, Claude on Azure Foundry) with its key, model and address, dictionary (add, remove). Keys in the Keychain (`KeychainStore`, this device only); no setting has a value until the user gives one, and a missing one is reported when it is needed.
   - Simulator runs only (`#if DEBUG && targetEnvironment(simulator)`): keys from the launch environment, and `UNTYPE_TEST_DICTATE_SECONDS` for a timed dictation.
4. To decide after use: the keyboard, the Action Button / Shortcuts, meeting recording of the room, Teach for dictionary words, Ask, Only my voice, ElevenLabs / Google speech.

## Verified

- macOS: `swift build`, 514/514 tests.
- iPhone 17 Pro simulator (iOS 27.2): a sentence spoken by `say` through the Mac's loudspeakers was written in full (83 characters, 25 text updates); Soniox connected in 0.6 s.
- Not run: Refine / Translate from the app, the Settings screen by hand, the Keychain on a device, any use on a device, iPad layout.

## Installing on a device

- **From Xcode or `xcodebuild` + `devicectl`**, on devices paired with this Mac (an iPhone and two iPads are paired): Developer Mode on the device, a development build signed by the team. Valid for a year with the paid membership.
- **TestFlight**: an archive uploaded to App Store Connect; installed from the TestFlight app on any device of the user and of invited testers, updated over the air, each build valid 90 days. Needs an app record in App Store Connect.
- **App Store**: the same upload, after App Review.

## Open

- The app icon is the macOS one (transparent corners); an iOS icon must fill the square with no transparency before an upload.
- Development builds stop opening when the provisioning profile ends; TestFlight needs an app record in App Store Connect and an explicit App ID.
- No tests of the iOS app's own code yet.
