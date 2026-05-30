# Plan 032: Manual Permission Popup Option

Refined request: `~/aiwork/coding-platform/untype-s/docs/reference/refined-request-manual-permission-popup-option.md`
Codebase scan: `~/aiwork/coding-platform/untype-s/docs/reference/codebase-scan-manual-permission-popup-option.md`
Investigation: skipped; the existing app already has one permission-management popup (`UntypeOnboardingView`) and the work is a localized UI activation path.
Technical research: skipped; no new API or dependency is introduced.

## Objective
Add an explicit native UI option that opens the existing permission/setup popup on demand.

## Files To Modify
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
  - Add a helper in `UntypeRootView` to present `UntypeOnboardingView` manually.
  - Add a button in the Permissions inspector group to invoke the helper.
- `docs/design/project-design.md`
  - Document the manual permission setup activation path.
- `docs/design/project-functions.md`
  - Register the feature slice.
- `Issues - Pending Items.md`
  - Document the completed issue and dependency-vetting outcome.

## Steps
1. Add `presentPermissionSetup()` to refresh credentials/permission status and set `showOnboarding = true`.
2. Add an “Open Permission Setup” button in the Permissions inspector group.
3. Keep automatic onboarding unchanged, including the 24-hour skip suppression.
4. Update project documentation.
5. Run `swift build` and `swift test`.

## Acceptance Criteria
- The right inspector Permissions group exposes a permission setup option.
- Clicking the option opens the existing onboarding/permission sheet.
- The option works even if automatic onboarding was skipped recently.
- Existing automatic onboarding behavior remains unchanged.
- `swift build` and `swift test` pass.
