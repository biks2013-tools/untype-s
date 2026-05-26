# Plan 022: Quick Close

Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-quick-close.md`
Investigation: skipped - localized policy/config change using existing runtime patterns.
Technical research: skipped - no new external technology.
Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-quick-close.md`

## Objective
Add a configurable `Quick Close` push-to-talk release policy that can submit the latest current-turn partial transcript immediately when provider finalization is predictably slower than the desired release latency.

## Files to Modify
- `Sources/UntypeCore/TranscriptionSessionRuntime.swift` - add the release-time Quick Close branch and diagnostics.
- `Sources/UntypeCore/ResolvedConfig.swift` and `Sources/UntypeCore/ConfigResolver.swift` - add shared CLI/env config.
- `Sources/UntypeCore/UntypeRuntimeFactory.swift` - pass the resolved policy into runtime options.
- `Sources/UntypeCore/UntypeUISettings.swift` - persist the non-secret UI setting and include it in session arguments.
- `Sources/UntypeCore/NativeUntypeUILauncher.swift` - expose the setting in the Push to Talk inspector.
- `Tests/UntypeCoreTests/*` - cover runtime, config, and UI settings behavior.
- `docs/design/project-design.md`, `docs/design/project-functions.md`, `Issues - Pending Items.md`, and `test_scripts/ui-mode-smoke.md` - document behavior and verification.

## Approach
1. Keep the default disabled so existing finalization-wait behavior remains unchanged.
2. Add `--quick-close` / `--no-quick-close` and `UNTYPE_QUICK_CLOSE` for shared runtime configuration.
3. Add a non-secret persisted UI toggle named `Quick Close`.
4. In runtime release handling, if Quick Close is enabled and no final text is already pending, submit the latest partial immediately. If no partial exists, emit a no-text warning.
5. Suppress late provider partial/final callbacks after Quick Close partial submission so the ending provider session cannot add stale output.

## Verification
- `swift build`
- `swift test`
- Manual UI smoke: enable Quick Close, record a push-to-talk turn that only produces partial Soniox text, and verify processed output appears without waiting for the 1.5s timeout.
