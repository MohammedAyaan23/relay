#!/bin/bash
# Builds build/Relay.app from this checkout: release build, bundle layout, Info.plist, local signature.
#
# SwiftPM resource bundles are looked up at the .app root, which codesign rejects, and then in this
# checkout's .build folder. Relay must not call Bundle.module; `make check-portable` proves it doesn't.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Relay
BIN="$(swift build -c release --show-bin-path)"
APP="build/Relay.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/Relay" "$APP/Contents/MacOS/Relay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Optional signed helper shortcuts (see docs/shortcuts-setup.md).
if compgen -G "Resources/Shortcuts/*.shortcut" > /dev/null; then
    mkdir -p "$APP/Contents/Resources/Shortcuts"
    cp Resources/Shortcuts/*.shortcut "$APP/Contents/Resources/Shortcuts/"
fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
