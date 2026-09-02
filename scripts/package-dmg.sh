#!/bin/bash
# Build MacShelf and package it as a compressed DMG for GitHub Releases.
#
# Usage:
#   scripts/package-dmg.sh
#
# The Finder styling pass (background picture, icon positions) drives Finder
# over AppleScript, so it needs a session Finder will answer on. It is attempted
# by default and given STYLE_TIMEOUT seconds; if Finder never answers, the DMG
# ships with the default window layout instead of hanging the build. Set
# MACSHELF_DMG_STYLE=0 to skip the pass outright.

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

STYLE_DMG="${MACSHELF_DMG_STYLE:-1}"
STYLE_TIMEOUT="${MACSHELF_DMG_STYLE_TIMEOUT:-90}"

cleanup() {
    if [ -n "${DEVICE}" ]; then
        hdiutil detach "${DEVICE}" -quiet 2>/dev/null || true
    fi
    rm -rf "$BACKGROUND_RENDER_DIR" "$STAGING_DIR" "$MOUNT_DIR" "$RW_DMG"
}
trap cleanup EXIT

# QuickLook is what rasterises the SVG, and it is not guaranteed to be there.
# Returning non-zero drops the styling pass rather than failing the build.
render_background() {
    qlmanage -t -s 1320 -o "$BACKGROUND_RENDER_DIR" "$BACKGROUND_SVG" >/dev/null 2>&1 || true
    if [ ! -f "$BACKGROUND_RENDER_DIR/dmg-background.svg.png" ]; then
        return 1
    fi
    sips -z 420 660 "$BACKGROUND_RENDER_DIR/dmg-background.svg.png" --out "$STAGING_DIR/.background/background.png" >/dev/null
}

# Finder can sit unresponsive forever on a machine with no usable session, so
# the AppleScript runs in the background under a watchdog rather than inline.
style_window() {
    style_applescript &
    local pid=$!
    local waited=0

    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$STYLE_TIMEOUT" ]; then
            pkill -9 -P "$pid" 2>/dev/null || true
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done

    wait "$pid"
}

style_applescript() {
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
}

echo ">> Building ${APP_NAME}.app..."
scripts/build.sh

echo ">> Preparing DMG contents..."
mkdir -p "$DIST_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"
if [ "$STYLE_DMG" = "1" ]; then
    mkdir -p "$STAGING_DIR/.background"
    if ! render_background; then
        echo ">> Could not render the DMG background; skipping the styling pass." >&2
        STYLE_DMG=0
    fi
fi

echo ">> Creating writable DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG" >/dev/null

if [ "$STYLE_DMG" = "1" ]; then
    ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR")"
    DEVICE="$(printf "%s\n" "$ATTACH_OUTPUT" | awk "/Apple_HFS|Apple_APFS/ {print \$1; exit}")"
    if [ -z "$DEVICE" ]; then
        DEVICE="$(printf "%s\n" "$ATTACH_OUTPUT" | awk "/^\/dev\// {print \$1; exit}")"
    fi

    if [ -z "$DEVICE" ]; then
        echo "Unable to find mounted DMG device" >&2
        exit 1
    fi

    echo ">> Styling Finder window (up to ${STYLE_TIMEOUT}s)..."
    if ! style_window; then
        echo ">> Finder did not style the window; shipping the default layout." >&2
    fi

    sync
    hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force -quiet
    DEVICE=""
else
    echo ">> Skipping Finder styling (MACSHELF_DMG_STYLE=0)."
fi

rm -f "$DMG_PATH"
echo ">> Creating ${DMG_PATH}..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
hdiutil internet-enable -no "$DMG_PATH" >/dev/null 2>&1 || true

# The Homebrew cask pins this checksum, so write it where the release step and
# a human running the script both see it.
(cd "$DIST_DIR" && shasum -a 256 "${APP_NAME}-${VERSION}.dmg" | tee "${APP_NAME}-${VERSION}.dmg.sha256")

echo ">> Done: ${DMG_PATH}"
