#!/usr/bin/env bash
# build_icon.sh — generate the AppIcon.icns (and a small preview PNG) for Multiterminal.
# Requires: swift, sips, iconutil (all present on a default macOS install).
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="assets/icon-master.png"
ICONSET="assets/AppIcon.iconset"
ICNS="assets/AppIcon.icns"

mkdir -p assets
echo ">> rendering master icon..."
swift tools/make_icon.swift "$MASTER"

rm -rf "$ICONSET"; mkdir -p "$ICONSET"

# Standard macOS icon sizes (points x scale -> pixels).
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_512x512.png"   >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_256x256.png"   >/dev/null
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_256x256@2x.png"
sips -z 128 128   "$MASTER" --out "$ICONSET/icon_128x128.png"   >/dev/null
cp "$ICONSET/icon_128x128.png" "$ICONSET/icon_128x128@2x.png"
sips -z 64 64     "$MASTER" --out "$ICONSET/icon_32x32@2x.png"  >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_32x32.png"     >/dev/null
cp "$ICONSET/icon_32x32.png" "$ICONSET/icon_16x16@2x.png"
sips -z 16 16     "$MASTER" --out "$ICONSET/icon_16x16.png"     >/dev/null

echo ">> building .icns..."
iconutil -c icns "$ICONSET" -o "$ICNS"
echo ">> wrote $ICNS ($(du -h "$ICNS" | cut -f1))"
