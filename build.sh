#!/bin/bash
# Build YariAltTab.app.  Usage:
#   ./build.sh            build into ./build/YariAltTab.app
#   ./build.sh install    also copy to ~/Applications and (re)launch it
set -euo pipefail
cd "$(dirname "$0")"

APP=build/YariAltTab.app
BUNDLE_ID=be.yari.alttab
# Set SIGN_IDENTITY to a real/self-signed certificate name to keep the
# Accessibility permission across rebuilds. Ad-hoc ("-") loses it every build.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/YariAltTab "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    DEST="$HOME/Applications/YariAltTab.app"
    pkill -x YariAltTab || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        # Ad-hoc signature changed, so the old permission grants are stale.
        tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
        tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi
    open "$DEST"
    echo "Installed and launched $DEST"
fi
