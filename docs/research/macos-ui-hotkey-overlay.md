# macOS UI, Hotkey, Overlay, and Focused Input Strategy for Swift `untype`

## Overview
This note narrows the Swift replacement strategy to the macOS surfaces that are most sensitive to platform behavior: app lifecycle, global hotkeys and key release detection, permission handling, non-activating overlay windows, and focused-input delivery.

The current TypeScript project already gives us the parity target:
- `src/ui/transcriptionOverlay.ts` uses a floating, display-only overlay that does not steal focus.
- `src/platform/macos/focusedInputHelper.ts` and `native/macos/input-helper/main.swift` implement focused-input delivery as a separate helper process that reads text from `stdin`, returns JSON on `stdout`, and keeps diagnostics on `stderr`.
- `README.md` documents the user-facing contract: `untype ui`, push-to-talk, fallback to press-to-toggle when the native release hook is unavailable, and explicit Accessibility/Input Monitoring remediation steps. The same README also says the overlay is independent from the main window and must not leak transcript text or secrets.  

The recommended Swift strategy is therefore:
1. Keep SwiftPM as the build root and expose `untype` as the single executable product.
2. Make the macOS UI a native AppKit-owned lifecycle with SwiftUI embedded where useful, rather than trying to force everything through a pure SwiftUI lifecycle.
3. Use a low-level key event tap as the primary push-to-talk release detector, with a global event monitor as fallback or diagnostics.
4. Model microphone, Accessibility, and Input Monitoring as separate runtime readiness states.
5. Implement the overlay as a non-activating `NSPanel` configured to stay above normal windows without taking focus.
6. Keep focused-input delivery in a separate helper binary, fed through `stdin`, so the text never has to appear in argv or logging.

## Recommended Architecture

### SwiftPM shape
Swift Package Manager is a good fit for the replacement because it can build, test, document, and run executable products, and each target compiles into a module or test suite. The package manifest can vend an executable product, not just a library. citeturn4search0turn4search2turn4search3turn4search11

For `untype`, I would keep the package split roughly like this:
- `UntypeCore` for the pure session, protocol, and configuration state.
- `UntypeCLI` for argument parsing and CLI contract compatibility.
- `UntypeMacOS` for AppKit, permissions, hotkeys, and overlay window control.
- `UntypeUI` for SwiftUI screens hosted by AppKit.
- `UntypeInputHelper` for focused-input delivery.

That keeps the UI and the helper isolated without forcing a second project format.

### AppKit + SwiftUI integration
Apple’s current docs explicitly support mixing AppKit and SwiftUI in both directions: AppKit views and view controllers can be embedded in SwiftUI, and SwiftUI views can be hosted inside AppKit using `NSHostingController`. citeturn5search0turn5search1turn5search9turn5search10

For this project, the pragmatic choice is:
- Let AppKit own the top-level lifecycle for the macOS UI process.
- Host SwiftUI inside panels and configuration screens.
- Keep window, hotkey, and permission plumbing in AppKit so the behavior is explicit and testable.

That is the least risky path for a command-oriented macOS tool that also has a UI mode.

## Global Hotkeys and Key Release

### Primary recommendation
Use a Quartz event tap as the primary hotkey/release mechanism. Apple describes event taps as filters for observing and altering low-level input events, and `CGEvent.tapCreate` is the native API for creating them. `NSEvent.addGlobalMonitorForEvents(matching:handler:)` is useful too, but Apple’s docs describe it as receiving copies of events posted to other apps, which makes it better as a monitor than as the canonical release hook. citeturn3search1turn3search2turn3search0

In practice:
- Use the event tap to detect `keyDown`/`keyUp` for the configured push-to-talk key.
- Run the tap on a dedicated thread/run loop so it is isolated from the UI run loop.
- If the tap cannot be created or stops delivering events, downgrade to press-to-toggle and show a visible warning.

### Why not local monitor only?
`NSEvent.addLocalMonitorForEvents(matching:handler:)` only sees events while your app is active. That is not sufficient for a system-wide push-to-talk hotkey. citeturn3search6

### Permissions and fallback behavior
The source README already says the app may require Accessibility or Input Monitoring permission for release detection, and that if the native release hook cannot start the UI should warn and fall back to press-to-toggle. Keep that behavior in Swift. It is the correct failure mode because it preserves usability even when the OS blocks the hook.

My implementation guidance:
- Detect the hotkey path as a runtime capability, not just a compile-time feature.
- Keep the “release hook unavailable” warning visible in the UI settings/status view.
- Treat the hotkey as stateful: `armed`, `recording`, `released`, `fallback-toggle`.

## Permissions

### Microphone
Microphone access is the straightforward one. Apple requires a purpose string in `Info.plist` via `NSMicrophoneUsageDescription`, and the modern macOS API path is `AVAudioApplication.requestRecordPermission(completionHandler:)` on macOS 14+, with `AVCaptureDevice.requestAccess(for:completionHandler:)` and `authorizationStatus(for:)` available for capture-device authorization flow. citeturn2search0turn2search1turn2search3turn2search4turn2search6turn2search7turn2search12

Guidance:
- Add the microphone usage string early; do not wait until runtime.
- Check authorization before starting capture.
- Surface denial as a typed error with a clear remediation message.

### Accessibility
Accessibility is the permission gate for focused-input delivery and some UI automation paths. Apple’s `AXIsProcessTrustedWithOptions(_:)` returns whether the current process is a trusted accessibility client. The `AXUIElement` APIs are the control surface for querying and changing accessible UI objects, and `kAXFocusedUIElementAttribute` identifies the focused accessibility element. citeturn1search4turn6search0turn6search1turn6search3turn6search5turn6search7

Guidance:
- Check trust early, before attempting focused-input delivery.
- If trust is missing, show an exact remediation message that names the app the user must enable in System Settings.
- Use Accessibility Inspector during QA. Apple explicitly documents it as the tool to query and test accessibility information and system accessibility features. citeturn6search2turn6search5turn6search17turn6search20

### Input Monitoring
I did not find a public Apple authorization API that mirrors microphone authorization for Input Monitoring. The practical strategy is to treat it as a user-managed privacy setting: attempt the hotkey implementation, detect failure, and instruct the user to enable the app under System Settings > Privacy & Security. Apple’s event-tap docs describe the relevant low-level event path, but the permission itself is not exposed as a simple “request access” API in the docs I reviewed. citeturn3search1turn3search2turn2search18

That means the Swift UI should expose a readiness checklist with at least:
- Microphone permission.
- Accessibility trust.
- Hotkey release-hook health.
- Focused-input helper availability.

## Overlay Window Strategy

### Recommended window type
Use `NSPanel` for the transcription overlay. Apple documents `NSPanel` as a special kind of window that is typically auxiliary to the main window, and the `nonactivatingPanel` style mask as a panel that does not activate the owning app. `canJoinAllSpaces` allows the window to appear in all Spaces, and `orderFront(_:)` can bring it to the front without making it key or main. citeturn3search3turn3search4turn3search5turn3search11turn1search14

Practical overlay configuration:
- Frame-less, transparent, shadowless panel.
- `nonactivatingPanel` style.
- `canJoinAllSpaces` collection behavior.
- Floating level.
- Mouse events ignored if the overlay is display-only.

### Behavior goals
The overlay should match the source contract:
- Do not steal focus from the foreground app.
- Show recording status and live transcript text.
- Replace partial text in place.
- Briefly show committed text after release.
- Clear contents when hidden.
- Never persist transcript text, processed output, protocol payloads, or secrets.

### SwiftUI/AppKit split
If the overlay becomes interactive later, do not weaken the display-only panel. Keep the overlay as a presentation surface and put interaction in the main window or a separate panel. That keeps the non-activating behavior easy to reason about.

## Focused Input Delivery

### Keep the helper-process boundary
The current source implementation is the right shape: a separate native helper receives the processed text on `stdin`, returns a structured JSON line on `stdout`, and keeps diagnostics on `stderr`. That avoids putting text into argv, environment variables, or top-level logs.

The helper’s current fallback order is also the correct one to preserve:
1. Direct Accessibility insertion into the focused element.
2. Unicode keyboard events.
3. Clipboard-preserving `Cmd+V` fallback.

### Why this order works
Apple’s Accessibility APIs let you inspect and manipulate the focused element through `AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue`, and `AXUIElementPerformAction`. `NSPasteboard` is the app’s interface to the shared pasteboard server, and `NSPasteboard.general` is the normal cut/copy/paste board. citeturn6search0turn6search1turn6search5turn6search7turn6search8turn6search23

The source helper uses those facts well:
- `AXUIElementCopyAttributeValue(..., kAXFocusedUIElementAttribute, ...)` to find the focused control.
- `kAXValueAttribute` and `kAXSelectedTextRangeAttribute` to insert text directly when the control supports it.
- A `NSPasteboard` snapshot/restore around `Cmd+V` so the clipboard is preserved.

### Leakage prevention guidance
To keep focused text from leaking:
- Never pass the text in argv.
- Never print the text in diagnostics.
- Never persist the text in UI state.
- Pass it only over stdin/pipes to the helper, then return a compact status object.

If direct insertion fails, the helper should still fail closed with a typed error and a remediation message. That matches the source contract and avoids silent partial delivery.

## UI Parity Phasing

The investigation file already recommends that `untype ui` parity must be complete before the project is considered a real drop-in replacement. I agree with that. The UI is not cosmetic here; it owns the runtime permissions, push-to-talk, overlay, and operator controls.

Recommended phases:
1. **Core parity**: config, CLI, transcription session, renderer, and protocol behavior.
2. **UI shell**: AppKit lifecycle, SwiftUI settings views, and readiness diagnostics.
3. **Hotkey + overlay**: event tap, press-to-talk, non-activating overlay, fallback warnings.
4. **Focused-input helper**: Accessibility, Unicode events, clipboard-preserving paste fallback.
5. **Parity verification**: manual smoke tests for permissions, hotkey release, overlay focus behavior, and focused-input delivery.

Do not mark the Swift port as “drop-in” until phase 4 is complete and the macOS smoke tests pass.

## Practical Implementation Sketch

```swift
@main
struct UntypeEntry {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        if args.first == "ui" {
            await runUI()
        } else {
            await runCLI()
        }
    }
}
```

Inside `runUI()`:
- Start `NSApplication`.
- Install an `NSApplicationDelegate`.
- Create the main window and the overlay panel.
- Host SwiftUI configuration views with `NSHostingController`.
- Spin up the hotkey service on a dedicated thread/run loop.

Inside the focused-input helper:
- Read text from `stdin`.
- Resolve the focused element via Accessibility.
- Try AX insertion first.
- Fall back to Unicode events.
- Fall back to clipboard-preserving paste.
- Return a JSON result and keep diagnostics on `stderr`.

## Assumptions & Scope

### Assumptions made
| Assumption | Confidence | Impact if wrong |
|---|---|---|
| The Swift replacement should keep a single `untype` executable product in SwiftPM, with AppKit and SwiftUI used inside that package rather than switching to a separate Xcode project now. | HIGH | If the final distribution must be a full `.app` bundle immediately, the package structure should add a packaging layer earlier. |
| `untype ui` must remain part of parity, so the UI should not be treated as optional. | HIGH | If UI parity is deferred, the replacement is not a true drop-in yet. |
| Focused-input delivery should remain a helper process receiving text on `stdin`. | HIGH | If the text is moved into argv or logs, privacy and process-list leakage risks increase. |
| Input Monitoring should be treated as a user-managed privacy setting rather than a clean authorization API. | MEDIUM | If Apple adds or documents a public prompt API in the future, the hotkey readiness flow can simplify. |
| The overlay should remain display-only and non-activating. | HIGH | If it becomes interactive, the window design should change instead of weakening focus behavior. |

### Uncertainties & gaps
- I did not find a public Apple API that directly prompts for Input Monitoring.
- The exact packaging target for the final macOS UI distribution is still unresolved: pure SwiftPM executable, `.app` bundle, or a packaging wrapper.
- If the minimum supported macOS version is below 14, microphone permission code should use the `AVCaptureDevice` path rather than `AVAudioApplication.requestRecordPermission`.

### Clarifying questions for follow-up
1. Should the Swift UI be distributed as a true signed `.app` bundle, or is a SwiftPM executable sufficient for the first drop-in milestone?
2. What is the minimum supported macOS version for the Swift replacement?
3. Should the focused-input helper stay as a separate helper binary in Swift, or should it be folded into the main executable once parity is reached?

## References

### Apple sources used
- Swift Package Manager docs for executable products, targets, and build/test/run flow. citeturn4search0turn4search2turn4search3turn4search11turn4search12turn4search13
- AppKit/SwiftUI integration docs for `NSHostingController`, `NSViewControllerRepresentable`, and mixed AppKit/SwiftUI composition. citeturn5search0turn5search1turn5search2turn5search9turn5search13turn5search19
- Hotkey/event docs for `NSEvent.addGlobalMonitorForEvents`, `NSEvent.addLocalMonitorForEvents`, `CGEvent.tapCreate`, and Quartz Event Services. citeturn3search0turn3search1turn3search2turn3search6turn3search8turn3search9
- Windowing docs for `NSPanel`, `nonactivatingPanel`, `canJoinAllSpaces`, and `orderFront(_:)`. citeturn3search3turn3search4turn3search5turn3search11
- Permission docs for microphone authorization, `NSMicrophoneUsageDescription`, `AVAudioApplication.requestRecordPermission`, and `AVCaptureDevice.requestAccess(for:)`. citeturn2search0turn2search1turn2search3turn2search4turn2search6turn2search7turn2search12
- Accessibility and focused-element docs for `AXIsProcessTrustedWithOptions`, `AXUIElement`, `AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue`, and `kAXFocusedUIElementAttribute`. citeturn1search4turn6search0turn6search1turn6search3turn6search5turn6search7turn6search8
- Pasteboard docs for `NSPasteboard`, `NSPasteboard.general`, and `writeObjects(_:)`. citeturn6search3turn6search4turn6search15

### Project-local sources used
- `~/aiwork/coding-platform/untype/docs/reference/refined-request-swift-drop-in-replacement.md`
- `~/aiwork/coding-platform/untype/docs/reference/investigation-swift-drop-in-replacement.md`
- `~/aiwork/coding-platform/untype/README.md`
- `~/aiwork/coding-platform/untype/src/platform/macos/focusedInputHelper.ts`
- `~/aiwork/coding-platform/untype/native/macos/input-helper/main.swift`
- `~/aiwork/coding-platform/untype/src/ui/transcriptionOverlay.ts`
