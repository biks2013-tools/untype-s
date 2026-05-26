#!/usr/bin/env bash
set -euo pipefail

APP_NAME="untype"
PRODUCT_NAME="untype"
BUNDLE_ID=""
VERSION=""
BUILD_NUMBER=""
OUTPUT_DIR=".build/deploy"
SIGN_IDENTITY=""
NOTARY_PROFILE=""
ICON_PATH=""
SKIP_TESTS=0
SKIP_BUILD=0
CREATE_UNSIGNED=0

usage() {
  cat <<'EOF'
Usage:
  scripts/package-macos-app.sh \
    --bundle-id com.example.untype \
    --version 0.1.0 \
    --build 1 \
    [--sign-identity "Developer ID Application: Name (TEAMID)"] \
    [--notary-profile untype-notary] \
    [--output-dir .build/deploy] \
    [--icon path/to/AppIcon.icns] \
    [--skip-tests] \
    [--skip-build] \
    [--unsigned]

Required:
  --bundle-id       Final CFBundleIdentifier. Example: com.example.untype
  --version         CFBundleShortVersionString. Example: 0.1.0
  --build           CFBundleVersion. Example: 1

Signing:
  --sign-identity   Developer ID Application identity for public distribution.
  --notary-profile  notarytool keychain profile. Requires --sign-identity.
  --unsigned        Create an unsigned local app bundle and zip for development only.

Outputs:
  <output-dir>/untype.app
  <output-dir>/untype-<version>.zip
  <output-dir>/untype-<version>-notarized.zip when notarization is enabled
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --sign-identity)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --icon)
      ICON_PATH="${2:-}"
      shift 2
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --unsigned)
      CREATE_UNSIGNED=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$BUNDLE_ID" ]] || fail "--bundle-id is required"
[[ -n "$VERSION" ]] || fail "--version is required"
[[ -n "$BUILD_NUMBER" ]] || fail "--build is required"

if [[ -n "$NOTARY_PROFILE" && -z "$SIGN_IDENTITY" ]]; then
  fail "--notary-profile requires --sign-identity"
fi

if [[ -z "$SIGN_IDENTITY" && "$CREATE_UNSIGNED" -ne 1 ]]; then
  fail "provide --sign-identity for a deployable app, or pass --unsigned for local packaging only"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

require_command swift
require_command ditto
require_command plutil

if [[ -n "$SIGN_IDENTITY" ]]; then
  require_command codesign
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  require_command xcrun
fi

if [[ "$SKIP_BUILD" -ne 1 ]]; then
  note "Building release products"
  swift build -c release
fi

if [[ "$SKIP_TESTS" -ne 1 ]]; then
  note "Running test suite"
  swift test
fi

BIN_DIR="$(swift build -c release --show-bin-path)"
UNTYPE_BINARY="$BIN_DIR/untype"
HELPER_BINARY="$BIN_DIR/untype-input-helper"
ENTITLEMENTS="$PROJECT_ROOT/packaging/macos/untype.entitlements"

[[ -x "$UNTYPE_BINARY" ]] || fail "missing release binary: $UNTYPE_BINARY"
[[ -x "$HELPER_BINARY" ]] || fail "missing release helper binary: $HELPER_BINARY"
[[ -f "$ENTITLEMENTS" ]] || fail "missing entitlements file: $ENTITLEMENTS"

STAGE="$PROJECT_ROOT/$OUTPUT_DIR"
APP="$STAGE/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="$CONTENTS/Info.plist"
ZIP="$STAGE/$APP_NAME-$VERSION.zip"
FINAL_ZIP="$STAGE/$APP_NAME-$VERSION-notarized.zip"

note "Creating app bundle at $APP"
rm -rf "$APP" "$ZIP" "$FINAL_ZIP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$UNTYPE_BINARY" "$MACOS/untype"
cp "$HELPER_BINARY" "$MACOS/untype-input-helper"
chmod +x "$MACOS/untype" "$MACOS/untype-input-helper"

LAUNCHER_SOURCE="$STAGE/untype-launcher.swift"
cat > "$LAUNCHER_SOURCE" <<'SWIFT'
import Darwin
import Foundation

let launcherPath = CommandLine.arguments[0]
let executableURL = URL(fileURLWithPath: launcherPath)
    .deletingLastPathComponent()
    .appendingPathComponent("untype")
let executablePath = executableURL.path
let launchArguments = ["untype", "ui"] + Array(CommandLine.arguments.dropFirst())

var cArguments = launchArguments.map { strdup($0) }
cArguments.append(nil)
defer {
    for argument in cArguments where argument != nil {
        free(argument)
    }
}

execv(executablePath, &cArguments)
let message = "failed to launch untype ui: \(String(cString: strerror(errno)))\n"
message.withCString { pointer in
    _ = fputs(pointer, stderr)
}
exit(127)
SWIFT

note "Compiling double-click UI launcher"
swiftc -O "$LAUNCHER_SOURCE" -o "$MACOS/untype-launcher"
chmod +x "$MACOS/untype-launcher"

if [[ -n "$ICON_PATH" ]]; then
  [[ -f "$ICON_PATH" ]] || fail "icon file does not exist: $ICON_PATH"
  cp "$ICON_PATH" "$RESOURCES/AppIcon.icns"
fi

cat > "$INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleExecutable</key>
  <string>untype-launcher</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>untype records microphone audio only while you start listening or hold the push-to-talk hotkey, then sends it to the configured transcription provider.</string>
EOF

if [[ -n "$ICON_PATH" ]]; then
  cat >> "$INFO_PLIST" <<'EOF'
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
EOF
fi

cat >> "$INFO_PLIST" <<'EOF'
</dict>
</plist>
EOF

plutil -lint "$INFO_PLIST" >/dev/null

if [[ -n "$SIGN_IDENTITY" ]]; then
  note "Signing nested executables"
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$MACOS/untype-input-helper"

  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$MACOS/untype"

  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$MACOS/untype-launcher"

  note "Signing app bundle"
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP"

  note "Verifying code signature"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  note "Skipping code signing; unsigned output is for local testing only"
fi

note "Creating notarization archive"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "$NOTARY_PROFILE" ]]; then
  note "Submitting archive for notarization"
  xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  note "Stapling notarization ticket"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"

  note "Creating final notarized archive"
  ditto -c -k --keepParent "$APP" "$FINAL_ZIP"

  note "Assessing with Gatekeeper"
  spctl --assess --type execute --verbose=4 "$APP"
fi

cat <<EOF

Packaged app:
  $APP

Archive:
  $ZIP
EOF

if [[ -n "$NOTARY_PROFILE" ]]; then
  cat <<EOF

Notarized archive:
  $FINAL_ZIP
EOF
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  cat <<'EOF'

Warning:
  This app is unsigned. Use --sign-identity and --notary-profile before public distribution.
EOF
fi
