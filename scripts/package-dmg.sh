#!/bin/bash
# Build MacShelf and package it as a compressed DMG for GitHub Releases.
#
# Usage:
#   scripts/package-dmg.sh

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacShelf"
APP_PATH="build/${APP_NAME}.app"
DIST_DIR="dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/MacShelf/Resources/Info.plist)"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo ">> Building ${APP_NAME}.app..."
scripts/build.sh

echo ">> Preparing DMG contents..."
mkdir -p "$DIST_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo ">> Creating ${DMG_PATH}..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo ">> Done: ${DMG_PATH}"
