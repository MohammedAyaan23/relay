#!/bin/bash
# Builds build/Relay.app from this checkout: release build, bundle layout, Info.plist, local signature.
#
# SwiftPM resource bundles are looked up at the .app root, which codesign rejects, and then in this
# checkout's .build folder. Relay must not call Bundle.module; `make check-portable` proves it doesn't.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${RELAY_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITY="${RELAY_SIGN_IDENTITY:--}" # "-" = local ad-hoc signature (development)

swift build -c release --arch arm64 --product Relay
BIN="$(swift build -c release --arch arm64 --show-bin-path)"
APP="build/Relay.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/Relay" "$APP/Contents/MacOS/Relay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/Relay.icns "$APP/Contents/Resources/Relay.icns"
# Optional signed helper shortcuts (see docs/shortcuts-setup.md).
if compgen -G "Resources/Shortcuts/*.shortcut" > /dev/null; then
    mkdir -p "$APP/Contents/Resources/Shortcuts"
    cp Resources/Shortcuts/*.shortcut "$APP/Contents/Resources/Shortcuts/"
fi
# Hardened Runtime: macOS then refuses injected libraries and debuggers, so no other program can borrow
# Relay's permissions. The entitlements allow only the microphone and Apple events.
KEYCHAIN_ARGS=()
if [ -n "${RELAY_SIGN_KEYCHAIN:-}" ]; then KEYCHAIN_ARGS=(--keychain "$RELAY_SIGN_KEYCHAIN"); fi
codesign --force --options runtime --entitlements Resources/Relay.entitlements ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
