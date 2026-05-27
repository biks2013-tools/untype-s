---
language: Swift
framework: SwiftPM, SwiftUI, AppKit
package_manager: Swift Package Manager
build_command: swift build
test_command: swift test
lint_command: null
entry_points:
  - Sources/untype/main.swift
  - Sources/untype-input-helper/main.swift
  - Sources/UntypeCore/NativeUntypeUILauncher.swift
last_scanned_commit: b2552f10ccbd697af06fc0037da1d062ada846d7
request_file: ~/aiwork/coding-platform/untype-s/docs/reference/refined-request-bundled-app-focused-input-delivery.md
scan_scope: request-driven
generated_at: 2026-05-27
---

# Codebase Scan: Bundled App Focused-Input Delivery

## Metadata
- Project root: `~/aiwork/coding-platform/untype-s`
- Swift tools version: 6.0
- Minimum platform: macOS 14
- Main products: `untype`, `untype-input-helper`, `UntypeCore`
- Test framework: Swift Testing under `Tests/UntypeCoreTests/`

## Module Map
- `Sources/untype/main.swift`: CLI executable entry point. It routes no-argument bundled `.app` launches to `NativeUntypeUILauncher.launchBlockingOnCurrentThread()` and normal arguments to `UntypeCommand`.
- `Sources/untype-input-helper/main.swift`: focused-input helper executable entry point. It calls `FocusedInputHelperMain.run(...)`, prints one JSON result line, and exits with helper status.
- `Sources/UntypeCore/BundledAppLaunch.swift`: testable bundled-app launch detector. It treats `ui`, no-argument `.app` launches, and LaunchServices `-psn_*` arguments as UI launches.
- `Sources/UntypeCore/UntypeRuntimeFactory.swift`: constructs CLI and UI runtimes. Both paths instantiate `FocusedInputDelivery()` and pass `deliver(_:)` to `VoiceAgentProtocolController`.
- `Sources/UntypeCore/VoiceAgentProtocolController.swift`: performs raw/refine/translate/composite processing, renders processed output, writes protocol events, copies to clipboard, and sends the final processed text to the focused-input writer when the input operator is enabled.
- `Sources/UntypeCore/FocusedInputDelivery.swift`: resolves and launches `untype-input-helper`, sends processed text over stdin, parses JSON helper output, and maps helper failures.
- `Sources/UntypeCore/FocusedInputHelper.swift`: implements AX insertion, paste-keycode insertion, Unicode event insertion, diagnostics, and focused-input result JSON.
- `scripts/package-macos-app.sh`: packages release `untype` and `untype-input-helper` into `untype.app/Contents/MacOS`, declares `CFBundleExecutable=untype`, and signs nested executables plus bundle when configured.

## Conventions Observed
- Runtime behavior is kept behind injectable boundaries. `FocusedInputDelivery` accepts a helper runner for tests, and runtime factories inject clipboard/focused-input closures into the protocol controller.
- Processed text privacy is enforced by stdin delivery to the helper, not command-line arguments.
- Expected focused-input failures are fail-open protocol warnings; they do not terminate the transcription session.
- Bundled app behavior is covered by focused unit tests rather than live macOS permission tests.

## Integration Points

### In Scope
- `Sources/UntypeCore/FocusedInputDelivery.swift`
  - Add bundled-app delivery handling so the app process can use the existing focused-input implementation under the app bundle TCC identity.
  - Preserve subprocess helper delivery for CLI and unbundled runs.
- `Sources/UntypeCore/FocusedInputHelper.swift`
  - Reuse the current AX/paste/Unicode implementation for in-process bundled delivery if needed.
  - Keep the helper executable contract unchanged.
- `Tests/UntypeCoreTests/FocusedInputDeliveryTests.swift`
  - Add regression coverage proving bundled app mode uses in-process delivery and still sends text outside argv.
  - Add path-resolution coverage for `untype.app/Contents/MacOS/untype`.

### Out of Scope
- `Sources/UntypeCore/VoiceAgentProtocolController.swift`
  - Already passes the processed `current` text after refine/translate/composite processing to the focused-input writer; no duplicate processing path is needed.
- `Sources/UntypeCore/LLMRefiners.swift`
  - LLM refinement/translation output generation is not implicated.
- `scripts/package-macos-app.sh`
  - Already includes both `untype` and `untype-input-helper` under `Contents/MacOS`; no packaging layout change is required unless tests reveal otherwise.

### New Integration Point
- No new module is required. The fix should be localized to `FocusedInputDelivery` with regression tests.

## Duplication Check
Focused-input delivery is already implemented and wired through runtime construction. The request should extend the existing delivery implementation for bundled app identity handling, not add another delivery service.

## Risks
- Live Accessibility/Input Monitoring verification still depends on macOS TCC state and must be confirmed manually with a rebuilt app bundle.
- If helper-subprocess delivery is retained for bundled app mode, users may grant permission to `untype.app` while the nested helper process remains untrusted, producing exactly the reported symptom.
