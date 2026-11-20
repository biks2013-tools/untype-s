# Plan 079 - untype looks for new versions and offers to install them

Date: 2026-11-20. Status: implemented; the look, the download and the checks ran against the real release; the swap of the running app and the restart have not run yet (they need a release newer than the installed build).

## Request

Automatic update: untype checks from time to time whether a new version exists and proposes to install it.

## What the user gets

- A little after it starts (30 s) and every six hours, untype asks GitHub for its latest release. When that is a newer build, a small window offers it: the build, what changed (the "Changes in build N" part of the release notes), and **Install and restart**, **Later**, **Skip this version**, **Release page**.
- The offer is shown once per build and start of untype, without taking the keyboard from the app in use, and never while a meeting is recorded or a dictation runs: it waits (looked at again every 15 minutes).
- While a newer build waits, the menu-bar dropdown says so ("Build N is available — update…").
- Settings → General → Updates: **Look for new versions automatically** (on until switched off), the state, **Check now**.
- Install: the release's notarized zip is downloaded, checked, put in the place of the running app, and untype starts again. Settings, keys and permissions stay. It is refused while a meeting is recorded or a dictation runs.

## How

`UntypeUpdater.swift` (macOS only), no new dependency:

- `UntypeRelease`: GitHub's `releases/latest` of `biks2013-tools/untype-s` (public, no key), the tag `v<version>-b<build>`, the assets `*-notarized.zip` and `SHA256SUMS`. The request carries a generic client name and nothing about the user or the Mac.
- `UntypeUpdatePolicy`: when a look is due, whether a release is newer (by build number), whether to offer it now.
- `UntypeUpdateInstaller.prepare`: downloads the zip next to the installed app (same volume), checks its SHA-256 against the release's `SHA256SUMS`, unpacks it with `ditto`, checks the unpacked app's code signature (all architectures, nested code, strict) against **the running app's own designated requirement**, and that its build is the release's and newer. The signature check is what makes it safe: only an app signed with the same Developer ID as the same app is accepted, which is also why macOS keeps the permissions.
- `swapScript` / `startSwap`: a shell script that outlives untype: it waits for the process to end, moves the installed app aside, moves the new one in, removes the old one (or puts it back when the move fails), and opens the app. It writes to `~/.tool-agents/untype/update.log`.
- `UntypeUpdateModel`, `UntypeUpdateWindowController` / `UntypeUpdateView`, `UntypeUpdateSettingsRows`, the dropdown row. The switch and the skipped build are in the app's defaults (`untype.updates.automatic`, `untype.updates.skippedBuild`).
- The Homebrew cask now says `auto_updates true`: Homebrew then leaves updating to the app (`brew upgrade` skips it unless `--greedy`), and does not fight a build the app installed itself.

## Verified

- 553/553 tests, 8 new: reading GitHub's answer, the checksum, the policy, the swap script run on stand-in folders (success, and the old app back after a failed move), the signature check on the installed untype (accepted for its own identity, refused for another developer, another identifier, a folder that is no app).
- Live (`UNTYPE_UPDATE_LIVE_TEST=1`): release b88 found on GitHub, downloaded, its checksum and signature accepted, unpacked with both executables; the same download refused as not newer.

## Not verified

- The swap of the running app and the restart, and that the permissions stay afterwards (expected: the signature identity is the same). It can only be seen with a published build newer than the installed one: the release after this build is the first test.
- The offer window, the dropdown row and the Settings rows on screen.

## Limits

- The app must be writable by the user (as installed from the disk image or by Homebrew for that user); otherwise the offer says to replace it by hand.
- A build older than this one has no updater: it is updated by hand or by Homebrew once more.
- The download is the whole app (about 56 MB); no partial updates.
- GitHub allows 60 looks an hour per address without a key; untype makes four a day.
