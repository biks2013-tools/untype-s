# Refined Request: Bundled App Focused-Input Delivery

## Category
Development / Bug Fix

## Objective
Investigate and resolve the defect where, when `untype` is launched as a bundled macOS app, refined and/or translated protocol output is shown/processed by the app but is not delivered to the currently active foreground application.

## Scope
In scope:
- Inspect the bundled-app launch, runtime factory, protocol output, focused-input delivery, helper discovery, and packaging paths.
- Preserve CLI behavior and existing unbundled `untype ui` behavior.
- Ensure bundled `.app` launches can locate and execute the focused-input helper shipped in `Contents/MacOS`.
- Add regression coverage for the bundled helper-resolution behavior and any affected focused-input delivery path.
- Update project documentation, functional requirements, issue tracking, and design notes with the defect and resolution.

Out of scope:
- Replacing the existing focused-input implementation strategy.
- Adding new runtime dependencies.
- Changing LLM refinement/translation prompt semantics.
- Performing live macOS Accessibility/Input Monitoring smoke tests in a real bundled app, unless feasible from the current environment.

## Requirements
- The protocol controller must continue to send the final processed text, including refined and translated output, to the focused-input writer when the input operator is enabled.
- The bundled app must resolve `untype-input-helper` from the app bundle's executable directory when launched as `untype.app`.
- Missing helper failures must remain explicit and diagnosable; no silent fallback may hide a broken bundle.
- Packaging must continue to include `untype-input-helper` alongside `untype` in `Contents/MacOS`.
- Existing privacy requirements must remain intact: processed text must go to the helper over stdin and must not appear in process arguments, persisted settings, or diagnostics.

## Constraints
- Use SwiftPM and the existing Swift/AppKit implementation.
- Do not introduce new runtime dependencies.
- Do not perform version-control operations.
- Maintain the no-fallback configuration rule; this work must not invent default configuration values.
- Keep tests focused and avoid requiring live macOS permission state for automated regression coverage.

## Acceptance Criteria
- A regression test demonstrates that helper path resolution works when the main executable is inside `untype.app/Contents/MacOS/untype`.
- The implementation can be built with `swift build`.
- The focused test suite, or the full `swift test` suite if practical, passes.
- Project design and functional requirement documents record the bundled-app focused-input behavior.
- `Issues - Pending Items.md` records the issue and its resolution.

## Assumptions
- "Refined/translated output" means the protocol-processed text that appears after LLM refinement and/or translation and is passed to clipboard/focused-input operators.
- The active application delivery path is the focused-input operator, not transcript export or clipboard-only delivery.
- The likely bundled-app failure is helper discovery, helper authorization identity, or packaging layout, because recent work changed the bundled executable identity for global hotkeys.

## Open Questions
- Live verification may still require the user to rebuild/install the app bundle, grant Accessibility/Input Monitoring to the new app identity, focus a real target text field, and perform a push-to-talk release.

## Original Request
> when the app is used as a bundled app 
> it does not send the refined/translated output to the active application 
>
> can you investigate and resolve ?
