#!/usr/bin/env bash
# build_app.sh — assemble a double-clickable Multiterminal.app bundle with the real icon.
# Usage: bash tools/build_app.sh [release|debug]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="Multiterminal.app"
BIN=".build/$([ "$CONFIG" = "debug" ] && echo debug || echo release)/multiterminal"

echo ">> building ($CONFIG)..."
swift build -c "$CONFIG"

echo ">> assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/multiterminal"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/multiterminal"

# Ad-hoc codesign so macOS treats it as a proper local app (no quarantine prompts locally).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo ">> done: $APP"
ls -R "$APP" | head -20
