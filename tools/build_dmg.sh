#!/usr/bin/env bash
# build_dmg.sh — build a distributable Multiterminal.dmg for the website.
#
# No Apple Developer ID or notarization required: visitors drag the app into
# Applications, then right-click → Open once to clear Gatekeeper.
#
# Produces: website/downloads/Multiterminal.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Multiterminal.app"
DMG="Multiterminal.dmg"
OUT_DIR="website/downloads"

echo ">> building app (release)..."
sh tools/build_app.sh release

echo ">> staging DMG contents..."
STAGE="$(mktemp -d)/Multiterminal"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"

echo ">> creating $OUT_DIR/$DMG ..."
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/$DMG"
hdiutil create \
    -volname "Multiterminal" \
    -srcfolder "$STAGE" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    "$OUT_DIR/$DMG"

echo ">> done:"
du -h "$OUT_DIR/$DMG"