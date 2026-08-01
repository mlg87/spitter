#!/usr/bin/env bash
# make_icon.sh — build Spitter.icns from assets/icon-1024.png
#
# WHY: iconutil requires a precisely named iconset directory with specific
# dimensions. We generate all required sizes from the 1024×1024 source
# using sips (bundled with macOS — no ImageMagick required).
# Called automatically by build.sh when Spitter.icns is missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/assets/icon-1024.png"
ICONSET="$SCRIPT_DIR/Spitter.iconset"
ICNS="$SCRIPT_DIR/Spitter.icns"

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: icon source not found at $SRC" >&2
    exit 1
fi

echo "Building iconset from $SRC …"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Generate all required iconset sizes (macOS icon spec)
sips -z 16   16   "$SRC" --out "$ICONSET/icon_16x16.png"    >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_32x32.png"    >/dev/null
sips -z 64   64   "$SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128  128  "$SRC" --out "$ICONSET/icon_128x128.png"  >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_256x256.png"  >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_512x512.png"  >/dev/null
sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET"

echo "Created $ICNS"
