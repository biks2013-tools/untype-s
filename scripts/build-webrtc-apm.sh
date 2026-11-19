#!/usr/bin/env bash
# Builds Vendor/UntypeAEC/UntypeAEC.xcframework: WebRTC's audio processing
# module (echo cancellation) as a static library behind the C interface in
# Vendor/UntypeAEC/shim. Needed only to rebuild the committed framework
# (a new library version, a change to the shim); `swift build` does not run it.
#
#   scripts/build-webrtc-apm.sh
#
# Needs: meson (or MESON=/path/to/meson), ninja, Xcode command line tools,
# and the network (the library's source archive and abseil, both checked
# against pinned checksums). Builds for this Mac's architecture.
set -euo pipefail

VERSION="2.1"
URL="https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-${VERSION}.tar.xz"
SHA256="ae9302824b2038d394f10213cab05312c564a038434269f11dbf68f511f9f9fe"
DEPLOYMENT_TARGET="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/UntypeAEC"
WORK="$ROOT/.build/untype-aec"
MESON="${MESON:-meson}"

note() { printf '==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v "$MESON" >/dev/null || fail "meson not found (pip install meson, or set MESON=/path/to/meson)"
command -v ninja >/dev/null || fail "ninja not found (brew install ninja)"
command -v xcodebuild >/dev/null || fail "xcodebuild not found"

rm -rf "$WORK"
mkdir -p "$WORK/source"

note "Downloading webrtc-audio-processing $VERSION"
curl -sSfL -o "$WORK/source.tar.xz" "$URL"
ACTUAL="$(shasum -a 256 "$WORK/source.tar.xz" | awk '{print $1}')"
[ "$ACTUAL" = "$SHA256" ] || fail "checksum of the source archive is $ACTUAL, expected $SHA256"
tar -xf "$WORK/source.tar.xz" -C "$WORK/source" --strip-components 1

note "Building the static library"
export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
(
  cd "$WORK/source"
  "$MESON" setup "$WORK/build" --prefix="$WORK/install" --default-library=static \
    --buildtype=release --wrap-mode=forcefallback -Dcpp_args=-fvisibility=hidden >"$WORK/meson-setup.log" 2>&1 \
    || { tail -30 "$WORK/meson-setup.log" >&2; fail "meson setup failed"; }
)
"$MESON" compile -C "$WORK/build" >"$WORK/meson-compile.log" 2>&1 \
  || { tail -30 "$WORK/meson-compile.log" >&2; fail "the library did not compile"; }
"$MESON" install -C "$WORK/build" >"$WORK/meson-install.log" 2>&1 \
  || { tail -30 "$WORK/meson-install.log" >&2; fail "meson install failed"; }

note "Compiling the C interface"
clang++ -std=c++17 -O2 -fno-exceptions -fno-rtti -mmacosx-version-min="$DEPLOYMENT_TARGET" \
  -DWEBRTC_LIBRARY_IMPL -DWEBRTC_POSIX -DWEBRTC_MAC \
  -I"$VENDOR/shim" -I"$WORK/install/include/webrtc-audio-processing-2" -I"$WORK/install/include" \
  -c "$VENDOR/shim/untype_aec.cc" -o "$WORK/untype_aec.o"

note "Joining the libraries"
LIBRARIES=()
while IFS= read -r library; do
  LIBRARIES+=("$library")
done < <(find "$WORK/build" -name '*.a' -not -path '*/examples/*' | sort)
[ "${#LIBRARIES[@]}" -gt 0 ] || fail "no static libraries were built"
libtool -static -no_warning_for_no_symbols -o "$WORK/libUntypeAEC.a" "$WORK/untype_aec.o" "${LIBRARIES[@]}" 2>"$WORK/libtool.log" \
  || { cat "$WORK/libtool.log" >&2; fail "libtool failed"; }

note "Making the XCFramework"
mkdir -p "$WORK/headers"
cp "$VENDOR/shim/untype_aec.h" "$WORK/headers/"
cat >"$WORK/headers/module.modulemap" <<'EOF'
module UntypeAEC {
    header "untype_aec.h"
    link "c++"
    export *
}
EOF
rm -rf "$VENDOR/UntypeAEC.xcframework"
xcodebuild -create-xcframework -library "$WORK/libUntypeAEC.a" -headers "$WORK/headers" \
  -output "$VENDOR/UntypeAEC.xcframework" >"$WORK/xcframework.log" 2>&1 \
  || { cat "$WORK/xcframework.log" >&2; fail "the XCFramework could not be made"; }

note "Copying the licences"
mkdir -p "$VENDOR/licenses"
cp "$WORK/source/COPYING" "$VENDOR/licenses/webrtc-audio-processing-COPYING.txt"
ABSEIL_LICENSE="$(find "$WORK/source/subprojects" -maxdepth 2 -name LICENSE | head -1)"
[ -n "$ABSEIL_LICENSE" ] || fail "abseil's licence was not found"
cp "$ABSEIL_LICENSE" "$VENDOR/licenses/abseil-cpp-LICENSE.txt"

ARCHS="$(lipo -archs "$WORK/libUntypeAEC.a")"
SIZE="$(du -sh "$VENDOR/UntypeAEC.xcframework" | awk '{print $1}')"
note "Done: Vendor/UntypeAEC/UntypeAEC.xcframework ($ARCHS, $SIZE)"
