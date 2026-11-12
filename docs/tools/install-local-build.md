# install-local-build

`scripts/install-local-build.sh` builds untype, signs it with the personal **untype Local Signing** certificate, installs it as `/Applications/untype.app` (replacing the running copy) and relaunches it. It is the way to run a development build on a Mac that does not hold the project's Developer ID certificate.

## Why a personal certificate

macOS ties the Accessibility and Input Monitoring grants to the app's signature (its designated requirement). An unsigned or ad-hoc build gets a new signature on every build and silently loses the grants. A build signed with one long-lived certificate keeps the same designated requirement (`identifier "com.local.untype" and certificate leaf = H"<sha1>"`), so the grants survive every rebuild.

The certificate is self-signed, trusted only on this Mac, and valid for 10 years. It is for local use only: builds signed with it cannot be distributed (that needs the Developer ID procedure in `docs/design/deployment-guide.md`).

## Usage

```
scripts/install-local-build.sh --version <v> --build <n> [--skip-tests]
```

| Option | Meaning |
|---|---|
| `--version` | `CFBundleShortVersionString`, e.g. `0.1.0` (required) |
| `--build` | `CFBundleVersion`, e.g. `49.2` (required) |
| `--skip-tests` | Skip the test suite during packaging |

Output: `.build/local/untype.app` and `.build/local/untype-<version>.zip`, plus the installed `/Applications/untype.app`.

## One-time setup (already done on this Mac)

| Item | Location |
|---|---|
| Signing identity | `untype Local Signing`, in its own keychain `~/Library/Keychains/untype-signing.keychain-db` (added to the user keychain search list) |
| Keychain password | `~/.untype-signing/keychain.pass` (mode 600); the script unlocks the keychain with it, so signing never prompts |
| Certificate (public part) | `~/.untype-signing/untype-local-signing.pem` |
| Trust | user trust setting for code signing (`security add-trusted-cert -r trustRoot -p codeSign`) |

The key lives in a dedicated keychain, not the login keychain, because the login keychain password can differ from the Mac login password and then `codesign` blocks on a prompt it cannot satisfy. The key's partition list allows `codesign` (`security set-key-partition-list -S apple-tool:,apple:,codesign:`).

Verify: `security find-identity -v -p codesigning` lists `"untype Local Signing"`.

## After switching between this build and an official release

The signer differs, so the grants must be given again once:

```
tccutil reset Accessibility com.local.untype
tccutil reset ListenEvent com.local.untype
```

then relaunch untype and switch it on under System Settings → Privacy & Security → Accessibility and Input Monitoring. The last official build is kept at `~/untype-backup/untype.app`.

## Verification after an install

Push-to-talk into a focused text field; the newest record in `~/.tool-agents/untype/release-latency.jsonl` must show `focused_input.ok=true`.
