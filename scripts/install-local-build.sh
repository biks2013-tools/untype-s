#!/usr/bin/env bash
# Builds untype, signs it with the personal "untype Local Signing" certificate
# and installs it in /Applications, replacing the running copy and relaunching
# it. The certificate's stable signature keeps the macOS Accessibility and
# Input Monitoring grants across rebuilds. Setup and recovery:
# docs/tools/install-local-build.md.
set -euo pipefail

SIGN_IDENTITY="untype Local Signing"
KEYCHAIN="$HOME/Library/Keychains/untype-signing.keychain-db"
KEYCHAIN_PASSWORD_FILE="$HOME/.untype-signing/keychain.pass"
BUNDLE_ID="com.local.untype"
OUTPUT_DIR=".build/local"
APP="/Applications/untype.app"
SKIP_TESTS=""

usage() {
  cat <<'EOF'
Usage: scripts/install-local-build.sh --version <v> --build <n> [--skip-tests]

  --version     CFBundleShortVersionString, e.g. 0.1.0
  --build       CFBundleVersion, e.g. 49.1
  --skip-tests  Do not run the test suite while packaging
EOF
}

VERSION=""
BUILD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --skip-tests) SKIP_TESTS="--skip-tests"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

[[ -n "$VERSION" ]] || { echo "error: --version is required" >&2; exit 1; }
[[ -n "$BUILD" ]] || { echo "error: --build is required" >&2; exit 1; }
[[ -f "$KEYCHAIN" ]] || { echo "error: signing keychain not found: $KEYCHAIN (see docs/tools/install-local-build.md)" >&2; exit 1; }
[[ -f "$KEYCHAIN_PASSWORD_FILE" ]] || { echo "error: keychain password file not found: $KEYCHAIN_PASSWORD_FILE" >&2; exit 1; }

cd "$(dirname "$0")/.."

echo "==> Unlocking the signing keychain"
security unlock-keychain -p "$(cat "$KEYCHAIN_PASSWORD_FILE")" "$KEYCHAIN"

echo "==> Building and signing"
scripts/package-macos-app.sh \
  --bundle-id "$BUNDLE_ID" \
  --version "$VERSION" \
  --build "$BUILD" \
  --sign-identity "$SIGN_IDENTITY" \
  --output-dir "$OUTPUT_DIR" \
  $SKIP_TESTS

echo "==> Quitting the running untype"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  pgrep -f "$APP/Contents/MacOS/untype" >/dev/null || break
  sleep 0.5
done
if pgrep -f "$APP/Contents/MacOS/untype" >/dev/null; then
  echo "error: untype did not quit; quit it and run again" >&2
  exit 1
fi

echo "==> Installing $APP"
rm -rf "$APP"
ditto "$OUTPUT_DIR/untype.app" "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -m1 '^Authority='

echo "==> Launching"
open "$APP"
