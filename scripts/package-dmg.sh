#!/bin/bash
# Build MacShelf and package it as a styled compressed DMG for GitHub Releases.
#
# Usage:
#   scripts/package-dmg.sh

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacShelf"
APP_PATH="build/${APP_NAME}.app"
DIST_DIR="dist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Sources/MacShelf/Resources/Info.plist)"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
RW_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}.rw.dmg"
BACKGROUND_SVG="assets/dmg-background.svg"
BACKGROUND_RENDER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.background.XXXXXX")"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.mount.XXXXXX")"
DEVICE=""

cleanup() {
    if [ -n "${DEVICE}" ]; then
        hdiutil detach "${DEVICE}" -quiet 2>/dev/null || true
    fi
    rm -rf "$BACKGROUND_RENDER_DIR" "$STAGING_DIR" "$MOUNT_DIR" "$RW_DMG"
}
trap cleanup EXIT

render_background() {
    qlmanage -t -s 1320 -o "$BACKGROUND_RENDER_DIR" "$BACKGROUND_SVG" >/dev/null 2>&1
    sips -z 420 660 "$BACKGROUND_RENDER_DIR/dmg-background.svg.png" --out "$STAGING_DIR/.background/background.png" >/dev/null
}

echo ">> Building ${APP_NAME}.app..."
scripts/build.sh

echo ">> Preparing DMG contents..."
mkdir -p "$DIST_DIR" "$STAGING_DIR/.background"
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"
render_background

echo ">> Creating writable DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR")"
DEVICE="$(printf "%s\n" "$ATTACH_OUTPUT" | awk "/Apple_HFS|Apple_APFS/ {print \$1; exit}")"
if [ -z "$DEVICE" ]; then
    DEVICE="$(printf "%s\n" "$ATTACH_OUTPUT" | awk "/^\/dev\// {print \$1; exit}")"
fi

if [ -z "$DEVICE" ]; then
    echo "Unable to find mounted DMG device" >&2
    exit 1
fi

echo ">> Styling Finder window..."
osascript <<APPLESCRIPT >/dev/null
set mountPath to "$MOUNT_DIR"

tell application "Finder"
    set dmgFolder to POSIX file mountPath as alias
    open dmgFolder
    delay 1
    set theWindow to container window of dmgFolder
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {120, 120, 780, 540}
    set theOptions to icon view options of theWindow
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 128
    set background picture of theOptions to POSIX file (mountPath & "/.background/background.png")
    set position of item "${APP_NAME}.app" of dmgFolder to {160, 230}
    set position of item "Applications" of dmgFolder to {500, 230}
    update dmgFolder without registering applications
    delay 1
    close theWindow
end tell
APPLESCRIPT

sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

rm -f "$DMG_PATH"
echo ">> Creating ${DMG_PATH}..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
hdiutil internet-enable -no "$DMG_PATH" >/dev/null 2>&1 || true

echo ">> Done: ${DMG_PATH}"
