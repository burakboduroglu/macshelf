#!/bin/bash
# Build, bundle and ad-hoc-sign MacShelf as a launchable .app.
#
# Usage:
#   scripts/build.sh           # build + bundle
#   scripts/build.sh --run     # also relaunch the app

set -euo pipefail

cd "$(dirname "$0")/.."

PLUGINS_PLATFORM="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
PLUGINS_TOOLCHAIN="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins"

echo ">> Compiling..."
xcrun swift build --product MacShelf --disable-sandbox \
    -Xswiftc -plugin-path -Xswiftc "$PLUGINS_PLATFORM" \
    -Xswiftc -plugin-path -Xswiftc "$PLUGINS_TOOLCHAIN" \
    -Xswiftc -disable-sandbox

BIN=".build/arm64-apple-macosx/debug/MacShelf"
APP="build/MacShelf.app"

echo ">> Packaging $APP..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacShelf"

cp Sources/MacShelf/Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable MacShelf" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.macshelf.app" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName MacShelf" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName MacShelf" "$APP/Contents/Info.plist"

# Carry over generated SwiftPM resource bundles so SwiftUI/Xcassets work.
for bundle in .build/arm64-apple-macosx/debug/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

echo ">> Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP" >/dev/null

echo ">> Done: $APP"

if [ "${1:-}" = "--run" ]; then
    echo ">> Relaunching..."
    pkill -x MacShelf 2>/dev/null || true
    sleep 0.5
    open "$APP"
fi
