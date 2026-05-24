# Swift Testing and Distribution Strategy for `untype-s`

## Overview
For a Swift-native `untype` replacement, the strongest default is a SwiftPM executable product named `untype`, with Swift Testing used for most unit and integration coverage and XCTest reserved for UI-specific or legacy interop cases. Swift.org describes Swift Testing as a modern, expressive, cross-platform testing approach that is compatible with XCTest for easy migration, while Apple’s XCTest documentation still positions XCTest as the framework used with XCUIAutomation for UI tests. SwiftPM’s own `swift test` and `swift build` commands can enable either testing framework explicitly, so the project can mix them without changing the package structure. citeturn2search0turn2search1turn2search2turn2search6turn2search8

## Key Decisions
- Use Swift Testing for pure CLI/library behavior, config parsing, protocol state, renderer behavior, and mocked provider adapters. Swift.org describes it as expressive, scalable, and cross-platform, and it is compatible with XCTest for incremental migration. citeturn2search0turn2search5
- Keep XCTest available for UI-heavy tests or future app-bundle automation, because Apple still documents XCTest in combination with XCUIAutomation for validating application UI flows. citeturn2search1turn2search4
- Treat `swift build --show-bin-path`, `swift run`, and `swift package experimental-install` as the primary SwiftPM distribution hooks for the command-line executable. SwiftPM documents executable products, executable package templates, `swift run`, `swift build --show-bin-path`, and experimental install/uninstall commands for executable products. citeturn6search3turn6search4turn6search5turn7search0turn6search0turn6search2

## Testing Strategy

### XCTest versus Swift Testing for CLI libraries
For this project, Swift Testing should be the default test framework for the library and CLI layers. The reason is practical: Swift Testing is the newer framework, is explicitly described by Swift.org as cross-platform and compatible with XCTest, and `swift test`/`swift build` can enable it directly. XCTest still matters, but mainly where the test scope is tied to AppKit/XCUIAutomation or older test infrastructure. citeturn2search0turn2search5turn2search6turn2search2turn2search1

Recommended division:
- Swift Testing: config precedence, error mapping, renderer behavior, voice-agent protocol state machine, provider adapter unit tests, and smoke tests that only need subprocess execution.
- XCTest: any future UI automation for an app bundle, and compatibility shims if some existing helper code is already XCTest-based. Apple still documents XCTest as the UI-testing framework paired with XCUIAutomation. citeturn2search1turn2search4

### Process-level CLI smoke tests
Use `Foundation.Process` for CLI smoke tests that launch the built `untype` executable and assert its stdout/stderr/exit-code contract. Apple documents that a process has controllable current directory, stdin, stdout, stderr, and environment values, and that `Process` can run another program as a subprocess without sharing memory space. The `standardInput`, `standardOutput`, `standardError`, `environment`, `currentDirectoryURL`, and `executableURL` properties are all available for that purpose. citeturn3search2turn3search1turn3search4turn3search5turn3search6turn3search9turn3search11

Implementation guidance:
- Build the executable first, then point `Process.executableURL` at the built binary or an installed symlink/wrapper.
- Capture stdout and stderr separately with pipes so the test can assert pipe-safe output and error separation.
- Set a temporary current directory and temporary environment to verify config precedence deterministically.

This is an implementation recommendation derived from Apple’s `Process` API shape; the framework docs do not prescribe a specific testing style, but they support the subprocess contract required here. citeturn3search2turn3search1turn3search4turn3search5turn3search6

### Mocked WebSocket/provider tests
For Soniox and ElevenLabs adapters, keep the transport behind a protocol boundary and unit-test the adapter against mocked message streams rather than live sockets. Apple’s `URLSessionWebSocketTask` supports binary and UTF-8 text frames, asynchronous send/receive, handshake authentication/redirection, and close-code reporting through `URLSessionWebSocketDelegate`, which gives enough surface area to build a transport abstraction with deterministic fixtures. citeturn9search0turn9search1turn9search4turn9search10turn9search12turn9search14

Recommended fixture coverage:
- Open-handshake success and negotiated-protocol callbacks.
- Binary audio frame send paths.
- Text JSON event parsing paths.
- Server close codes and reasons.
- Error frames, decode failures, and reconnect/finalization behavior.

This adapter-first test design is a recommendation, not an Apple requirement, but it aligns well with `URLSessionWebSocketTask`’s delegate model and message types. citeturn9search0turn9search1turn9search12

## macOS Manual Smoke Tests
Keep microphone, Accessibility, hotkey, and overlay verification as manual smoke tests in addition to automated unit coverage. Apple documents that microphone access requires an `NSMicrophoneUsageDescription` purpose string, that `AVAudioApplication.recordPermission` and `requestRecordPermission(_:)` expose microphone authorization state, and that global key-event monitoring requires Accessibility trust or enabled accessibility. Apple also documents `AXIsProcessTrustedWithOptions(_:)` for checking whether the current process is a trusted accessibility client. citeturn4search1turn4search14turn4search18turn8search0turn8search1turn8search4

Recommended manual checks:
- First launch microphone prompt appears and `recordPermission` transitions correctly.
- Accessibility trust prompt or settings path is documented for hotkey/global-monitor behavior.
- Global key monitoring works only after the expected trust path is granted.
- Overlay windows remain non-activating if the UI path uses `NSWindow.StyleMask.nonactivatingPanel`. Apple documents that style mask specifically for panels that do not activate the owning app. citeturn5search4turn8search1turn5search10turn5search12turn2search1

If the later UI path moves into a bundled app, keep these tests around because permission and event-monitor behavior can differ materially between an unbundled CLI and a signed app bundle. That distinction is an implementation inference based on Apple’s permission and signing documentation. citeturn4search2turn4search3turn8search0

## SwiftPM Install and Symlink Strategy
Model `untype` as an executable product in `Package.swift`. SwiftPM documents executable products, executable package templates, and commands for building and running executables. It also documents `swift build --show-bin-path`, which prints the binary output location, and the experimental install/uninstall commands for executable products. citeturn6search3turn6search4turn6search5turn7search0turn6search0turn6search2

Recommended local distribution path:
1. `swift build -c release --show-bin-path` to locate the built executable. SwiftPM documents the release/debug build split and the `--show-bin-path` switch. citeturn7search3turn7search0
2. Install the executable via `swift package experimental-install` if you want package-manager-managed executable installation. SwiftPM documents that command as installing executable products of the current package. citeturn6search0turn6search2
3. If you want a simple developer PATH entry, create a symlink or wrapper that points at the built binary output path. That symlink step is an implementation pattern inferred from SwiftPM’s exposed binary output path, not a distinct SwiftPM feature. citeturn7search0turn7search3

For the replacement project, keep the installed command name `untype` even though the active repository is `untype-s`, because SwiftPM executable products are named in the manifest and exposed as externally visible build artifacts. citeturn6search3turn6search4

## Later App-Bundle and Notarization Considerations
If the UI path later becomes a bundled macOS app, move distribution planning to Apple’s app-bundle and notarization model rather than treating the CLI binary as the final shipping artifact. Apple documents that macOS bundles place `Info.plist` in the `Contents` directory, that microphone access requires `NSMicrophoneUsageDescription`, and that the app should be distribution-signed and notarized before shipping outside the Mac App Store. Apple also documents that directly distributed Mac software should be signed, packaged into a distribution container, and notarized. citeturn4search4turn4search1turn4search2turn4search3turn4search9turn4search13

Practical implications:
- Add the microphone usage string before any real mic capture path ships.
- If Accessibility or other entitlements become required, plan them as bundle-level capabilities rather than ad hoc CLI behavior. Apple documents entitlements as the bundle-level permission mechanism. citeturn4search1turn4search14turn4search18turn4search2
- Do not treat signing and notarization as late packaging only; Apple says invalid signatures or modifying a bundle after signing can break notarization. citeturn1search11turn4search2

## Best Practices
- Keep the pure CLI/core logic in one library target and the process-launch smoke tests in a separate integration test target so the unit suite stays fast.
- Prefer Swift Testing for newly written test code, but do not force a framework migration if a UI or legacy XCTest-based path is already in place. Swift.org explicitly supports side-by-side use. citeturn2search0turn2search5
- Use `Process`-based assertions to verify stdout/stderr separation, environment precedence, and exit codes from the built executable. citeturn3search2turn3search1turn3search5turn3search6
- Keep mocked provider tests deterministic by controlling handshake, frame order, close codes, and error injection through an adapter layer over `URLSessionWebSocketTask`. citeturn9search0turn9search1turn9search14
- Preserve manual smoke tests for microphone, Accessibility trust, and overlay focus behavior because Apple’s permission APIs make those paths dependent on user-granted system state. citeturn4search1turn8search0turn8search1

## Common Pitfalls
- Treating XCTest as obsolete. Apple still documents it, and Xcode still uses it for UI automation. citeturn2search1turn2search4
- Hiding CLI smoke tests behind internal function tests only. The subprocess contract is an external behavior and should be exercised through `Process`. citeturn3search2turn3search1
- Shipping microphone capture without `NSMicrophoneUsageDescription` or the correct permission flow. Apple warns that the purpose string is shown in the system prompt and is required for microphone access. citeturn4search1turn4search14turn4search18
- Assuming global key monitoring works without Accessibility trust. Apple states that key-related events may only be monitored if accessibility is enabled or the app is trusted for accessibility access. citeturn8search1turn8search3
- Treating a signed bundle as mutable after signing. Apple’s notarization docs warn that changing a bundle after signing breaks notarization. citeturn1search11turn4search2

## Assumptions & Scope
- I interpreted “Swift testing and distribution strategy” as a research question about test framework selection, CLI smoke test design, provider mocking, manual macOS smoke tests, and local/app-bundle distribution for the Swift replacement. Confidence: high. citeturn2search0turn2search1turn6search5
- I treated the CLI executable as the first distribution target and the app bundle/notarization path as a later packaging concern unless UI requirements force earlier bundling. Confidence: medium-high. This is an implementation recommendation derived from SwiftPM and Apple distribution docs. citeturn6search3turn7search0turn4search2turn4search3
- I assumed `untype` remains the installed command name even though the repository name is `untype-s`, because SwiftPM executables are named in the manifest and installed as executable products. Confidence: high. citeturn6search3turn6search4

## References
1. Swift Testing - Swift.org. Modern test framework guidance, cross-platform support, and XCTest compatibility. citeturn2search0turn2search5
2. XCTest - Apple Developer Documentation. UI-testing role and continued availability alongside Swift Testing. citeturn2search1turn2search4
3. SwiftPM `swift build`, `swift test`, `swift run`, and executable product documentation. Build/test/run flags, executable products, and build output discovery. citeturn2search2turn2search6turn6search3turn6search4turn6search5turn7search0turn6search0turn6search2
4. Foundation `Process`. Subprocess environment, stdio, and executable configuration. citeturn3search2turn3search1turn3search4turn3search5turn3search6
5. URLSessionWebSocketTask / delegate docs. Transport abstraction surface for mocked provider tests. citeturn9search0turn9search1turn9search12turn9search14
6. Apple microphone and Accessibility docs. Permission prompts and trust checks. citeturn4search1turn4search14turn8search0turn8search1
7. Apple distribution and notarization docs. Signing, packaging, notarizing, and bundle layout. citeturn4search2turn4search3turn4search4turn4search9turn1search11

## Clarifying Questions for Follow-up
1. Should the first implementation milestone optimize for a pure CLI drop-in, or should it include a bundled macOS UI path from the start?
2. Do you want XCTest retained only for UI automation, or should we keep a dual-framework test setup long term?
3. Should local developer installation prefer `swift package experimental-install`, a manual symlink, or both?
4. Is notarized app-bundle distribution a hard requirement for the UI milestone, or only a later release target?
