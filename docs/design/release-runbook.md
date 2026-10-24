# untype Release Runbook — rebuild, sign, package, distribute

Step-by-step procedure for producing a new `untype.app` release on this Mac, installing it locally, and handing a notarized disk image to other people. Follow the steps in order; each step ends with a check that must pass before the next one.

Last verified: 2026-09-12 (build 13, `untype-0.1.0.dmg`, release `v0.1.0-b13`, Homebrew cask `0.1.0,13`). Environment at that time: macOS 26 (Darwin 25.6), Xcode 26.6, Swift 6.3.3.

---

## 0. One-time setup (skip if this Mac already released a build)

The release pipeline needs four things on the machine. Check them once; only re-do a step if its check fails.

| # | What | Check | How to (re)create |
|---|------|-------|-------------------|
| 0.1 | Full Xcode (for `notarytool`, `stapler`, `swift`) | `xcode-select -p` prints `/Applications/Xcode.app/Contents/Developer` | Install Xcode from the App Store, then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| 0.2 | Developer ID Application certificate **with its private key** in the login keychain | `security find-identity -v -p codesigning` lists `Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)` under *Valid identities* | Xcode → Settings → Accounts → Apple ID → Manage Certificates → **+** → Developer ID Application. Requires the paid Apple Developer Program and the Account Holder role. Afterwards export a `.p12` backup (Keychain Access → My Certificates → right-click → Export); Apple cannot re-issue the private key. |
| 0.3 | notarytool keychain profile `untype-notary` | `xcrun notarytool history --keychain-profile untype-notary` prints a history (an empty one is fine) with no error | See 0.3 below |
| 0.4 | Project builds and tests pass | `swift build && swift test` is green | Fix the code first; never release from a red tree |

**0.3 Creating the notarytool profile.** It authenticates with an App Store Connect API key.

1. App Store Connect → Users and Access → Integrations → App Store Connect API (https://appstoreconnect.apple.com/access/integrations/api). If the page shows *Request Access*, click it and accept the terms (individual accounts are approved instantly).
2. Copy the **Issuer ID** shown at the top of the page.
3. **Generate API Key** → name `untype-notary`, access **Developer** → Generate. Note the **Key ID**.
4. **Download** the `AuthKey_<KEYID>.p8` file. Apple allows exactly one download; keep a backup outside this Mac.
5. Store it and register the profile:

   ```sh
   mkdir -p ~/.tool-agents/untype && chmod 700 ~/.tool-agents/untype
   mv ~/Downloads/AuthKey_<KEYID>.p8 ~/.tool-agents/untype/
   chmod 600 ~/.tool-agents/untype/AuthKey_<KEYID>.p8
   xcrun notarytool store-credentials untype-notary \
     --key ~/.tool-agents/untype/AuthKey_<KEYID>.p8 \
     --key-id <KEYID> \
     --issuer <ISSUER-ID>
   ```

   Expected output ends with `Success. Credentials validated.`

Current values on this Mac (2026-09-12): Key ID `8X27HG66C4`, Issuer ID `4100965f-7ed7-4a45-bd2c-3f7ffab3f1ab`, key file `~/.tool-agents/untype/AuthKey_8X27HG66C4.p8`. Never commit the `.p8`.

**Setting up a second Mac:** import the `.p12` (double-click, enter its export password), repeat 0.3 with the same `.p8` (or a new key), install Xcode, clone the repo. Signing identity and notary profile names are then identical, so every command below works unchanged.

---

## 1. Decide the version numbers

Two numbers go into the app:

- **Version** (`CFBundleShortVersionString`), e.g. `0.1.0`. Bump it when users should notice a new release.
- **Build** (`CFBundleVersion`), an integer that must go up on **every** packaging run, even for the same version.

Find the last build number that was installed:

```sh
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" /Applications/untype.app/Contents/Info.plist
```

Use that number + 1 for `--build` below. Record the pair you chose; it appears in the file names and in the issue register entry (step 8).

Check: you have a version string and a build number higher than the installed one.

---

## 2. Make sure the tree is what you want to ship

```sh
cd ~/aiwork/tools/untype-s
git status --short
```

Every listed change will be compiled into the release. If something unfinished is in the tree, stash it or finish it first. Do not commit or push unless the project owner asked for it.

Check: `git status --short` shows only changes you intend to ship (or nothing).

---

## 3. Build, test, sign, notarize, and create the disk image

One command does the whole pipeline. It builds release binaries, runs the full test suite, assembles `untype.app`, signs the helper, the main binary and the bundle with hardened runtime and the microphone entitlement, submits the app to Apple for notarization, staples the ticket, checks Gatekeeper, then repeats sign → notarize → staple → check for the disk image.

```sh
scripts/package-macos-app.sh \
  --bundle-id com.local.untype \
  --version 0.1.0 \
  --build <N> \
  --sign-identity "Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)" \
  --notary-profile untype-notary \
  --dmg
```

Expect 5–10 minutes: the build takes about a minute, the tests seconds, and each notarization submission usually 2–5 minutes (the script prints `Current status: In Progress...` while waiting).

The output must contain, in this order:

```
==> Running test suite
✔ Test run with 229 tests in 0 suites passed
==> Verifying code signature
.../untype.app: valid on disk
.../untype.app: satisfies its Designated Requirement
==> Submitting archive for notarization
  status: Accepted
==> Stapling notarization ticket
The staple and validate action worked!
==> Assessing with Gatekeeper
.../untype.app: accepted
source=Notarized Developer ID
==> Creating disk image at .../untype-0.1.0.dmg
==> Submitting disk image for notarization
  status: Accepted
==> Stapling disk image
==> Assessing disk image with Gatekeeper
.../untype-0.1.0.dmg: accepted
source=Notarized Developer ID
```

(The test count grows over time; what matters is `passed` with 0 failures.)

Useful variants:

| Situation | Add |
|-----------|-----|
| Tests already ran on this exact tree a moment ago | `--skip-tests` |
| Only the disk image is needed again from the existing signed, stapled `.build/deploy/untype.app` | replace `--dmg` with `--dmg-only` (implies skip build/tests, no app re-notarization) |
| Local-only experiment, not for other people | drop `--notary-profile` and `--dmg` (the app is then signed but not notarized; Gatekeeper on other Macs would refuse it) |

Check: the four lines `status: Accepted` (twice), `accepted` and `source=Notarized Developer ID` (twice each) are present, and the script exits 0.

If notarization is **rejected** (`status: Invalid`), get the reasons with:

```sh
xcrun notarytool log <submission-id> --keychain-profile untype-notary
```

(the id is printed in the `id:` line of the submission output). Typical causes: a binary not signed with hardened runtime, a missing secure timestamp, or an expired certificate. Fix, bump the build number, rerun step 3.

---

## 4. Verify the artifacts independently

Do not trust the script's own summary blindly; re-check the files it produced.

```sh
cd ~/aiwork/tools/untype-s/.build/deploy
ls -la untype.app untype-0.1.0.dmg untype-0.1.0-notarized.zip

# App: identity, hardened runtime, chain to Developer ID CA
codesign -dvv untype.app 2>&1 | grep -E "Authority|TeamIdentifier|flags"
codesign --verify --deep --strict --verbose=2 untype.app
xcrun stapler validate untype.app
spctl --assess --type execute --verbose=4 untype.app

# Disk image
codesign --verify --verbose=2 untype-0.1.0.dmg
xcrun stapler validate untype-0.1.0.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 untype-0.1.0.dmg

# What is inside the image (build number must match step 1)
M=$(hdiutil attach -readonly -nobrowse -noautoopen untype-0.1.0.dmg | grep -o "/Volumes/.*")
ls -la "$M"
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$M/untype.app/Contents/Info.plist"
spctl --assess --type execute --verbose=4 "$M/untype.app"
hdiutil detach "$M"

# Fingerprint to publish next to the download
shasum -a 256 untype-0.1.0.dmg
```

Check: `Authority=Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)`, `flags=0x10000(runtime)`, every `spctl` line says `accepted` with `source=Notarized Developer ID`, every `stapler validate` says `The validate action worked!`, the image contains `untype.app`, `Applications` (symlink) and `INSTALL.txt`, and the build number inside the image is the one from step 1.

---

## 5. Install the new build on this Mac

Replacing the app while it runs is unreliable, so quit it first. Keep the previous bundle in case you need to roll back.

```sh
cd ~/aiwork/tools/untype-s
osascript -e 'tell application "untype" to quit'
mv /Applications/untype.app ".build/deploy/untype.app.build<PREVIOUS>-backup"
ditto .build/deploy/untype.app /Applications/untype.app
codesign --verify --deep --strict /Applications/untype.app && echo INSTALLED-OK
spctl --assess --type execute --verbose=4 /Applications/untype.app
open -a /Applications/untype.app
```

**Permissions.** macOS ties the Accessibility and Input Monitoring grants to the app's signing identity. As long as every build is signed with the same Developer ID certificate, the grants survive upgrades and nothing more is needed. The grants are lost only when the identity changes — after renewing the certificate, after switching from the Apple Development certificate, or after an ad-hoc/unsigned build. In that case:

```sh
tccutil reset Accessibility com.local.untype
```

then relaunch, add `/Applications/untype.app` again under System Settings → Privacy & Security → **Accessibility**, and check **Input Monitoring** too (remove a stale `untype` entry and re-add the app if the hotkey does not fire). Never reset Input Monitoring when only Accessibility is broken; that disables push-to-talk.

Check: `INSTALLED-OK` printed, Gatekeeper says `accepted`, the app is running (`pgrep -x untype`).

---

## 6. Smoke-test the two guarded features

These cannot be automated; do them by hand every release.

1. **Push-to-talk:** with any app in front, hold the configured hotkey, speak a sentence, release. The recording overlay must appear on press and the finalizing overlay on release.
2. **Focused-input delivery:** put the cursor in a text field (TextEdit or Notes is enough; also try an Outlook mail body if that is part of your workflow), do the same hold/speak/release. The processed text must appear at the cursor.
3. **Confirm in the log** that delivery succeeded (the log exists when release latency logging is enabled in the settings):

   ```sh
   tail -1 ~/.tool-agents/untype/release-latency.jsonl | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r.get("outcome"), r.get("focused_input"))'
   ```

   Expected: `delivered_to_focused_input {'attempted': True, 'ok': True}`. If you see `focused_input_failed` with `code: accessibility_not_trusted`, the permission grant was lost; redo the permissions part of step 5.

Longer checklists: `test_scripts/ui-mode-smoke.md`, `test_scripts/focused-input-smoke.md`.

Check: both features work and the newest log record shows `ok: true`.

---

## 7. Distribute

Share **only** `.build/deploy/untype-0.1.0.dmg` (rename it with the build number if several builds of the same version circulate, e.g. `untype-0.1.0-b13.dmg`; renaming does not affect the signature). Publish the SHA-256 from step 4 next to the download.

Give recipients these instructions (they are also inside the image as `INSTALL.txt`):

1. Open the `.dmg`, drag **untype** onto **Applications**. No Gatekeeper warning appears because the app is notarized. macOS 14 or newer.
2. Launch untype from Applications and follow the welcome screen's **How to enable Microphone, Accessibility and Input Monitoring** guide: start listening once and allow the Microphone, add untype under **Accessibility**, and under **Input Monitoring** only if the hotkey does not fire while another app is in front; quit and relaunch after changing permissions.
3. On the welcome screen click **Set keys…** and enter at least one speech-to-text key (Soniox or ElevenLabs), plus the Azure OpenAI or Google entries only for LLM refinement; the app stores them in `~/.tool-agents/untype/.env`, readable only by the user. The file can also be edited by hand: the first session start creates it as a fully commented template. Missing required values are reported, never defaulted.
4. Upgrading later: replace the app in Applications; permissions and settings are kept.

Do **not** share the `.zip` files or a bare `untype.app` copied from `/Applications`; they lack the install notes, and a bare copy can lose the stapled ticket if it travels through tools that strip extended attributes.

Check: the recipient can open the image, install, and get past the onboarding checklist without contacting you.

---

## 7b. Publish a public download link (GitHub Release)

The repository `biks2013-tools/untype-s` is public, so a GitHub Release gives a permanent, login-free download URL. Requires `gh auth status` to show an account with write access to the biks2013-tools organization (BikS2013). Do this only after steps 4–6 passed.

1. Make sure the source the build came from is committed and pushed (`git status --short` clean for `Sources/`, `prompts/`, `scripts/`, `packaging/`).
2. Write the checksums file and release notes: download list, SHA-256, macOS 14 requirement, a "Learn more" pointer to the technical deck at https://biks2013-tools.github.io/untype-s/ (published from the `deck` branch by GitHub Pages), the three install steps, what changed:

   ```sh
   cd .build/deploy && shasum -a 256 untype-<version>.dmg untype-<version>-notarized.zip > SHA256SUMS && cd ../..
   ```

3. Tag the commit with version **and** build number, push, and create the release with the three assets:

   ```sh
   git tag -a v<version>-b<N> -m "untype <version> build <N> (notarized Developer ID release)" HEAD
   git push origin main
   git push origin v<version>-b<N>
   gh release create v<version>-b<N> --repo biks2013-tools/untype-s \
     --title "untype <version> (build <N>)" \
     --notes-file <notes.md> \
     ".build/deploy/untype-<version>.dmg#untype-<version>.dmg (disk image, recommended)" \
     ".build/deploy/untype-<version>-notarized.zip#untype-<version>-notarized.zip" \
     ".build/deploy/SHA256SUMS#SHA256SUMS"
   ```

4. Verify the link works without a login and serves the same bytes:

   ```sh
   curl -sL -o /tmp/dl.dmg https://github.com/biks2013-tools/untype-s/releases/download/v<version>-b<N>/untype-<version>.dmg
   shasum -a 256 /tmp/dl.dmg      # must equal the SHA-256 from step 4
   ```

Links to hand out:

- Release page: `https://github.com/biks2013-tools/untype-s/releases/tag/v<version>-b<N>`
- Direct download: `https://github.com/biks2013-tools/untype-s/releases/download/v<version>-b<N>/untype-<version>.dmg`
- Always-newest: `https://github.com/biks2013-tools/untype-s/releases/latest/download/untype-<version>.dmg` (works while the file name stays the same across releases)

First release created this way: `v0.1.0-b8` on 2026-09-12.

Check: `gh release view v<version>-b<N> --repo biks2013-tools/untype-s` lists the three assets, `isDraft=false`, and the curl-downloaded checksum matches.

---

## 7c. Update the Homebrew tap

Homebrew users install with `brew tap biks2013-tools/untype && brew install --cask untype` from the tap repository `biks2013-tools/homebrew-untype`. That repository is maintained from this one, in the folder `homebrew-tap/` (originally a git subtree; remote `homebrew-tap`); the cask is generated here and published to the tap, never committed in the tap directly. The cask points at one GitHub release asset, so it must be regenerated after every published release:

```sh
scripts/update-homebrew-cask.sh \
  --version <version> --build <N> \
  --sha256 <SHA-256 of untype-<version>.dmg from step 4> \
  --push
git push origin main
```

The script rewrites `homebrew-tap/Casks/untype.rb` (version `"<version>,<N>"`, URL of `v<version>-b<N>/untype-<version>.dmg`, checksum, livecheck on the release tag), commits it on the current branch, and publishes the committed `homebrew-tap/` tree to the tap as one fast-forward commit on top of the tap's head (`git commit-tree` + `git push`), which is what updates the tap that Homebrew clones; it then re-fetches and checks the tap equals `homebrew-tap/`. It refuses — naming the files — if the tap holds content `homebrew-tap/` never had (a direct commit there): bring it over with `git fetch homebrew-tap main && git archive FETCH_HEAD | tar -x -C homebrew-tap`, review, commit, and run `scripts/update-homebrew-cask.sh --push-only`. `git subtree push` is not used: two subtree trailers in this repository name the same mainline commit (`a6d3c5e`, from the 2026 folder rename) and `git subtree split` aborts on them ("cache for … already exists"). The final `git push origin main` publishes the same commit in this repository. On a fresh clone add the remote once: `git remote add homebrew-tap https://github.com/biks2013-tools/homebrew-untype.git`. Then verify with Homebrew itself:

```sh
git -C "$(brew --repo biks2013-tools/untype)" pull -q origin main   # Homebrew keeps its own clone of the tap
brew style biks2013-tools/untype/untype                              # "no offenses detected"
brew audit --cask --online --strict biks2013-tools/untype/untype     # no output = pass
brew livecheck --cask biks2013-tools/untype/untype                   # "<version>,<N> ==> <version>,<N>"
```

Do not run `brew install --cask untype` on the development Mac while untype is running: the cask's `uninstall quit:` stanza quits the app by bundle id, and the install would collide with `/Applications/untype.app`. To test an install here use a scratch folder: `brew install --cask --appdir="$(mktemp -d)" biks2013-tools/untype/untype`, then `brew uninstall --cask untype` and relaunch the app.

Check: `brew info --cask biks2013-tools/untype/untype` shows the new `<version>,<N>` and no deprecation warning.

---

## 8. Record the release

The project keeps a ledger. Add, in `Issues - Pending Items.md` under *Completed Items*, one entry with: date, version + build, the command used, test count, `status: Accepted` for app and image, the SHA-256, and anything unusual (skipped tests, permission re-grant, rejected submission and its fix). Update `docs/design/deployment-guide.md` if the procedure itself changed. Do not run git commands unless asked.

---

## 9. Maintenance calendar

| Item | Expires / action | Consequence if missed |
|------|------------------|-----------------------|
| Developer ID Application certificate `GEORGIOS MARINOS (9F9H8NCAUB)` | **2027-02-01**. Renew in Xcode → Manage Certificates a few weeks before; export a new `.p12`. | Signing fails; existing installs keep working. The new certificate changes the identity: one permission re-grant on every Mac (step 5). |
| Apple Development certificate `4LF448TU3N` | 2027-08-15 (only used for local-only builds) | None for releases |
| App Store Connect API key `untype-notary` (`8X27HG66C4`) | Does not expire. Revoke and re-create on the App Store Connect page if the `.p8` leaks; then redo 0.3. | Notarization fails with an authentication error |
| Apple Developer Program membership | Yearly renewal in the Apple Developer account | Certificates are revoked; notarization stops; already-notarized builds keep opening |
| Bundle identifier `com.local.untype` | Change to a real reverse-DNS identifier (e.g. `com.<yourdomain>.untype`) before a wide release, in **one** deliberate build, and tell users to re-grant permissions once | Every existing user loses Accessibility/Input Monitoring grants on that upgrade |

---

## 10. Troubleshooting quick reference

| Symptom | Cause | Fix |
|---------|-------|-----|
| `error: provide --sign-identity for a deployable app` | Flag missing | Add `--sign-identity "Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)"` |
| `codesign: no identity found` / identity not listed by `security find-identity -v` | Certificate installed without its private key, or expired | Import the `.p12` backup, or create a new certificate (0.2) |
| A macOS dialog asks to allow `codesign` to use the key | First use of an imported key | Click **Always Allow** once |
| `No Keychain password item found for profile: untype-notary` | Profile missing on this Mac | Redo 0.3 |
| `status: Invalid` | Apple rejected the submission | `xcrun notarytool log <id> --keychain-profile untype-notary`, fix, bump build, rerun |
| `spctl` says `rejected` for an app that notarized fine | Ticket not stapled, or bundle copied in a way that dropped it | `xcrun stapler staple untype.app`, then re-run `spctl` |
| Push-to-talk hotkey does nothing after install | Input Monitoring grant tied to an older identity | Remove the stale entry under Input Monitoring, add `/Applications/untype.app`, relaunch |
| Text is not inserted; log shows `accessibility_not_trusted` | Accessibility grant lost | `tccutil reset Accessibility com.local.untype`, relaunch, re-add under Accessibility |
| Build 5 or earlier behaviour wanted back | Roll back | Quit, `ditto .build/deploy/untype.app.build<N>-backup /Applications/untype.app`, relaunch (a re-grant is needed if that build used another identity) |
