# Plan 053 — Show the running version and build; say why a sentence was not captured

## Request
A way to see which build of untype is installed and running. (Raised while checking plan-052, which did not seem to work.)

## Decisions
- **Where.** `UntypeAppVersion` reads `CFBundleShortVersionString` and `CFBundleVersion` of the running bundle. Shown as "untype 0.1.0 · build N" at the bottom of the menu-bar dropdown and at the bottom of the Settings sidebar, and written to the event log at launch. A binary outside an app bundle shows "not an app bundle".
- **Plan-052 follow-up.** The build 50 log of the user's attempts (app `M365Mail`) has no "sentence … captured" line, so the capture returned nothing, silently. `SentenceAnchor.capture` now returns the reason, which is logged at the press ("sentence around the cursor not captured: …", with the control's role, no text). The capture is also tried when the control reports no readable selection (before: skipped).

## Checks
- Unit tests: `UntypeAppVersionTests` (2). Suite 345/345.
- Not checked: how the two labels look in the app.
