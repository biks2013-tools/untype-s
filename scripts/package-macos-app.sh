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
CREATE_DMG=0
DMG_ONLY=0

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
    [--unsigned] \
    [--dmg] \
    [--dmg-only]

Required:
  --bundle-id       Final CFBundleIdentifier. Example: com.example.untype
  --version         CFBundleShortVersionString. Example: 0.1.0
  --build           CFBundleVersion. Example: 1

Signing:
  --sign-identity   Developer ID Application identity for public distribution.
  --notary-profile  notarytool keychain profile. Requires --sign-identity.
  --unsigned        Create an unsigned local app bundle and zip for development only.

Icon:
  --icon            Override the default packaging/macos/AppIcon.icns file.

Disk image:
  --dmg             Also create a drag-to-Applications disk image containing
                    the app, an Applications shortcut, and
                    packaging/macos/INSTALL.txt. With --sign-identity the image
                    is codesigned; with --notary-profile it is notarized and
                    stapled as well.
  --dmg-only        Skip build, tests, bundle creation, app signing and app
                    notarization; only build the disk image from the existing
                    <output-dir>/untype.app (which must already be signed and,
                    for --notary-profile, stapled). Implies --dmg.

Outputs:
  <output-dir>/untype.app
  <output-dir>/untype-<version>.zip
  <output-dir>/untype-<version>-notarized.zip when notarization is enabled
  <output-dir>/untype-<version>.dmg when --dmg or --dmg-only is given
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
    --dmg)
      CREATE_DMG=1
      shift
      ;;
    --dmg-only)
      CREATE_DMG=1
      DMG_ONLY=1
      SKIP_BUILD=1
      SKIP_TESTS=1
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

DEFAULT_ICON_PATH="$PROJECT_ROOT/packaging/macos/AppIcon.icns"
if [[ -z "$ICON_PATH" && -f "$DEFAULT_ICON_PATH" ]]; then
  ICON_PATH="$DEFAULT_ICON_PATH"
fi

require_command swift
require_command ditto
require_command plutil

if [[ -n "$SIGN_IDENTITY" ]]; then
  require_command codesign
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  require_command xcrun
fi

if [[ "$CREATE_DMG" -eq 1 ]]; then
  require_command hdiutil
fi

if [[ "$SKIP_BUILD" -ne 1 ]]; then
  note "Building release products"
  swift build -c release
fi

if [[ "$SKIP_TESTS" -ne 1 ]]; then
  note "Running test suite"
  swift test
fi

STAGE="$PROJECT_ROOT/$OUTPUT_DIR"
APP="$STAGE/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="$CONTENTS/Info.plist"
PKGINFO="$CONTENTS/PkgInfo"
ZIP="$STAGE/$APP_NAME-$VERSION.zip"
FINAL_ZIP="$STAGE/$APP_NAME-$VERSION-notarized.zip"
DMG="$STAGE/$APP_NAME-$VERSION.dmg"

build_dmg() {
  local dmg_stage="$STAGE/dmg-root"
  local install_notes="$PROJECT_ROOT/packaging/macos/INSTALL.txt"

  [[ -d "$APP" ]] || fail "missing app bundle for disk image: $APP"

  note "Creating disk image at $DMG"
  rm -rf "$dmg_stage" "$DMG"
  mkdir -p "$dmg_stage"
  ditto "$APP" "$dmg_stage/$APP_NAME.app"
  ln -s /Applications "$dmg_stage/Applications"
  if [[ -f "$install_notes" ]]; then
    cp "$install_notes" "$dmg_stage/INSTALL.txt"
  fi

  hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$dmg_stage" -ov -format UDZO -quiet "$DMG"
  rm -rf "$dmg_stage"

  if [[ -n "$SIGN_IDENTITY" ]]; then
    note "Signing disk image"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --verbose=2 "$DMG"
  fi

  if [[ -n "$NOTARY_PROFILE" ]]; then
    note "Submitting disk image for notarization"
    xcrun notarytool submit "$DMG" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait

    note "Stapling disk image"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"

    note "Assessing disk image with Gatekeeper"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
  fi
}

if [[ "$DMG_ONLY" -ne 1 ]]; then
BIN_DIR="$(swift build -c release --show-bin-path)"
UNTYPE_BINARY="$BIN_DIR/untype"
HELPER_BINARY="$BIN_DIR/untype-input-helper"
ENTITLEMENTS="$PROJECT_ROOT/packaging/macos/untype.entitlements"

[[ -x "$UNTYPE_BINARY" ]] || fail "missing release binary: $UNTYPE_BINARY"
[[ -x "$HELPER_BINARY" ]] || fail "missing release helper binary: $HELPER_BINARY"
[[ -f "$ENTITLEMENTS" ]] || fail "missing entitlements file: $ENTITLEMENTS"


note "Creating app bundle at $APP"
rm -rf "$APP" "$ZIP" "$FINAL_ZIP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$UNTYPE_BINARY" "$MACOS/untype"
cp "$HELPER_BINARY" "$MACOS/untype-input-helper"
chmod +x "$MACOS/untype" "$MACOS/untype-input-helper"

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
  <string>untype</string>
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
printf 'APPL????' > "$PKGINFO"

if command -v xattr >/dev/null 2>&1; then
  note "Removing removable extended attributes"
  xattr -cr "$APP"
fi

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
ditto -c -k --keepParent --norsrc "$APP" "$ZIP"

if [[ -n "$NOTARY_PROFILE" ]]; then
  note "Submitting archive for notarization"
  xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  note "Stapling notarization ticket"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"

  note "Creating final notarized archive"
  ditto -c -k --keepParent --norsrc "$APP" "$FINAL_ZIP"

  note "Assessing with Gatekeeper"
  spctl --assess --type execute --verbose=4 "$APP"
fi

fi

if [[ "$CREATE_DMG" -eq 1 ]]; then
  build_dmg
fi

cat <<EOF

Packaged app:
  $APP

Archive:
  $ZIP
EOF

if [[ -n "$NOTARY_PROFILE" && "$DMG_ONLY" -ne 1 ]]; then
  cat <<EOF

Notarized archive:
  $FINAL_ZIP
EOF
fi

if [[ "$CREATE_DMG" -eq 1 ]]; then
  cat <<EOF

Disk image:
  $DMG
EOF
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  cat <<'EOF'

Warning:
  This app is unsigned. Use --sign-identity and --notary-profile before public distribution.
EOF
fi
