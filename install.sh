#!/bin/bash
# Builds Mint and installs it in /Applications. Reopens it afterward if it was open.

set -euo pipefail

cd "$(dirname "$0")"

# Spotlight skips folders ending in .noindex, so the build copy stays out of searches.
BUILD_DIR="build.noindex"
BUILT_APP="$BUILD_DIR/Build/Products/Release/Mint.app"
INSTALLED_APP="/Applications/Mint.app"

is_running() {
    pgrep -f "$INSTALLED_APP/Contents/MacOS/Mint" > /dev/null
}

echo "Building Mint…"
xcodebuild \
    -project Mint.xcodeproj \
    -scheme Mint \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    -quiet \
    build

was_running=false
if is_running; then
    was_running=true
    echo "Quitting Mint…"
    osascript -e "tell application \"$INSTALLED_APP\" to quit" || true
    for _ in {1..20}; do
        is_running || break
        sleep 0.5
    done
    if is_running; then
        echo "Mint is still open. Quit it and run ./install.sh again." >&2
        exit 1
    fi
fi

echo "Installing to $INSTALLED_APP…"
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"
# A fresh modification date makes macOS pick up icon changes.
touch "$INSTALLED_APP"

if $was_running; then
    open "$INSTALLED_APP"
fi

echo "Done. Mint is in your Applications folder."
