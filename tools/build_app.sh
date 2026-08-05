#!/usr/bin/env bash
# build_app.sh — assemble a double-clickable Multiterminal.app bundle with the real icon,
# and optionally install it into /Applications so it shows in Launchpad, Spotlight & Finder.
#
# Usage:
#   bash tools/build_app.sh [release|debug]            # build bundle in project root
#   bash tools/build_app.sh install [release|debug]    # build + install into Applications
set -euo pipefail
cd "$(dirname "$0")/.."

# Parse arguments: an optional "install" flag plus an optional config.
INSTALL=0
CONFIG="release"
for arg in "$@"; do
    case "$arg" in
        install) INSTALL=1 ;;
        release|debug) CONFIG="$arg" ;;
    esac
done

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

if [ "$INSTALL" -eq 1 ]; then
    DEST="/Applications"
    # Fall back to the per-user Applications folder if /Applications isn't writable.
    if [ ! -w "$DEST" ]; then
        DEST="$HOME/Applications"
        mkdir -p "$DEST"
        echo ">> /Applications not writable — installing to $DEST"
    fi

    # Replace any previous copy, then move the freshly built bundle into place.
    rm -rf "$DEST/$APP"
    cp -R "$APP" "$DEST/$APP"
    # Re-sign in its final location so macOS trusts the installed copy.
    codesign --force --deep --sign - "$DEST/$APP" >/dev/null 2>&1 || true

    # Register with LaunchServices so the app appears in Spotlight & Launchpad right away.
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    [ -x "$LSREGISTER" ] && "$LSREGISTER" "$DEST/$APP" >/dev/null 2>&1 || true

    # Bump the Dock so Launchpad refreshes its grid.
    killall Dock >/dev/null 2>&1 || true

    echo ">> installed: $DEST/$APP"
    echo "   Open it from Launchpad, Spotlight, or Finder → Applications."
fi
