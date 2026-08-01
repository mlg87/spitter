#!/usr/bin/env bash
# build.sh — assemble Spitter.app from SPM release builds.
#
# WHY two single-arch builds + lipo instead of one multi-arch build:
# `swift build --arch arm64 --arch x86_64` requires xcbuild / full Xcode;
# it fails under Command Line Tools only (CLT). The two-invocation+lipo
# approach works with CLT alone and produces an identical universal binary.
#
# Optional env vars:
#   CODESIGN_IDENTITY  — code signing identity (default: ad-hoc "-")
#   ARCHS              — space-separated arch list (default: "arm64 x86_64")
#                        Set to "arm64" on CLT machines where x86_64 build fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="$(cat version.txt)"
APP_NAME="Spitter"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ARCHS="${ARCHS:-arm64 x86_64}"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

echo "==> Building Spitter v${VERSION}"

# -- Icon --
if [[ ! -f "${APP_NAME}.icns" ]]; then
    echo "--> Generating icon …"
    ./make_icon.sh
fi

# -- Compile each arch --
BINARY_PATHS=()
for ARCH in $ARCHS; do
    echo "--> swift build -c release --arch ${ARCH}"
    swift build -c release --arch "$ARCH" 2>&1
    BINARY_PATHS+=(".build/${ARCH}-apple-macosx/release/${APP_NAME}")
done

# -- Assemble app bundle --
echo "--> Assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Produce universal binary (or copy single-arch if only one arch built)
if [[ ${#BINARY_PATHS[@]} -eq 1 ]]; then
    cp "${BINARY_PATHS[0]}" "${MACOS}/${APP_NAME}"
else
    lipo -create "${BINARY_PATHS[@]}" -output "${MACOS}/${APP_NAME}"
fi

# Info.plist with version stamped in
cp Info.plist "${CONTENTS}/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString ${VERSION}" \
    -c "Set :CFBundleVersion ${VERSION}" \
    "${CONTENTS}/Info.plist"

# App type signature
printf 'APPL????' > "${CONTENTS}/PkgInfo"

# Icon
if [[ -f "${APP_NAME}.icns" ]]; then
    cp "${APP_NAME}.icns" "${RESOURCES}/${APP_NAME}.icns"
fi

chmod 755 "${MACOS}/${APP_NAME}"

# -- Remove signing detritus (reference's hard-won lesson) --
# Extended attributes and dot-files cause codesign to fail or produce an invalid
# bundle on subsequent re-runs, so we always clean before signing.
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -name "._*" -delete 2>/dev/null || true
find "$APP_DIR" -name ".DS_Store" -delete 2>/dev/null || true

# -- Code sign --
if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    # Hardened runtime only makes sense with a real identity (required for notarization).
    codesign --force --deep --sign "$CODESIGN_IDENTITY" --options runtime --timestamp "$APP_DIR"
else
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

codesign --verify --verbose=2 "$APP_DIR" || {
    echo "ERROR: codesign verification failed" >&2
    exit 1
}

echo ""
echo "==> Built: ${APP_DIR}"
echo "    Version: ${VERSION}"
if [[ ${#BINARY_PATHS[@]} -gt 1 ]]; then
    echo "    Architectures: $(lipo -archs "${MACOS}/${APP_NAME}")"
fi
