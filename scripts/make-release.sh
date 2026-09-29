#!/bin/bash
# Builds a signed, portability-checked Relay DMG for GitHub Releases. See RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Relay Self-Signed"
IDENTITY="${RELAY_SIGN_IDENTITY:-$NAME}"
SUFFIX=""

if [ "$IDENTITY" = "-" ]; then
    echo "WARNING: ad-hoc signed test build. Permissions won't survive updates; don't publish this DMG." >&2
    SUFFIX="-adhoc"
elif ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "No \"$IDENTITY\" code-signing certificate. Run scripts/make-signing-identity.sh first." >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must look like 1.2.3 (found \"$VERSION\")." >&2
    exit 1
fi
DMG="dist/Relay-$VERSION$SUFFIX.dmg"
if [ -e "$DMG" ]; then
    echo "$DMG already exists. Bump VERSION, or move the old DMG away yourself." >&2
    exit 1
fi

RELAY_VERSION="$VERSION" RELAY_SIGN_IDENTITY="$IDENTITY" scripts/make-app.sh
scripts/check-portable.sh build/Relay.app

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto build/Relay.app "$STAGE/Relay.app"
ln -s /Applications "$STAGE/Applications"
cp "Resources/First launch.txt" "$STAGE/"
mkdir -p dist
hdiutil create -volname "Relay" -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
echo "Built $DMG"
shasum -a 256 "$DMG"
