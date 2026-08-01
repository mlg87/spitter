#!/usr/bin/env bash
# install.sh — install Spitter with zero Gatekeeper friction.
#
# WHY this exists: releases are ad-hoc signed (no Apple Developer Program, so no
# notarization). Gatekeeper only blocks apps carrying the com.apple.quarantine
# xattr, which browsers set on downloads — curl and tar never set it. Ad-hoc
# signing satisfies Apple Silicon's signed-code requirement, so an app installed
# this way launches with no prompts.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mlg87/spitter/main/install.sh | bash
#
# Optional env vars:
#   SPITTER_TARBALL — path to a local Spitter-*.tar.gz; skips the
#                     download (used to test this script against a local build).

set -euo pipefail

APP_NAME="Spitter"
REPO="mlg87/spitter"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "${SPITTER_TARBALL:-}" ]]; then
    TARBALL="$SPITTER_TARBALL"
else
    # version.txt on main is maintained by release-please and always equals the
    # latest released version — no JSON parsing (macOS 13/14 ship no jq).
    VERSION="$(curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/version.txt" | tr -d '[:space:]')"
    TARBALL="${TMP_DIR}/${APP_NAME}.tar.gz"
    URL="https://github.com/${REPO}/releases/download/v${VERSION}/${APP_NAME}-${VERSION}.tar.gz"
    echo "==> Downloading ${APP_NAME} v${VERSION} …"
    # Race window: right after a release-PR merge, version.txt is bumped before
    # the tarball finishes uploading — fail loudly rather than half-install.
    curl -fsSL -o "$TARBALL" "$URL" || {
        echo "ERROR: download failed: $URL" >&2
        echo "The release may still be building — check https://github.com/${REPO}/releases" >&2
        exit 1
    }
fi

# /Applications is admin-group writable; fall back for standard (non-admin) users.
DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
    DEST="${HOME}/Applications"
    mkdir -p "$DEST"
fi

tar -xzf "$TARBALL" -C "$TMP_DIR" "${APP_NAME}.app"

# Quit any running instance so the replaced bundle relaunches cleanly.
pkill -x "$APP_NAME" 2>/dev/null || true

rm -rf "${DEST:?}/${APP_NAME}.app"
mv "${TMP_DIR}/${APP_NAME}.app" "${DEST}/"

# Defensive only — curl/tar never set quarantine; harmless if absent.
xattr -dr com.apple.quarantine "${DEST}/${APP_NAME}.app" 2>/dev/null || true

open "${DEST}/${APP_NAME}.app"
echo "==> Installed ${DEST}/${APP_NAME}.app and launched it."
echo "    First run: grant Microphone, Speech Recognition, and Accessibility when prompted."
echo "    Then hold Fn, speak, and release — see the README for changing the hotkey."
echo ""
echo "    Upgrading? macOS ties the Accessibility grant to the app's signature, which changes with"
echo "    every release. If the hotkey stops working, remove Spitter from System Settings →"
echo "    Privacy & Security → Accessibility and add it back."
