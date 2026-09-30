#!/bin/bash
# Builds a signed, portability-checked Relay DMG for GitHub Releases. See RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Relay Signing"
KEYCHAIN="$HOME/Library/Keychains/relay-signing.keychain-db"
IDENTITY="${RELAY_SIGN_IDENTITY:-$NAME}"
SUFFIX=""

if [ "$IDENTITY" = "-" ]; then
    echo "WARNING: ad-hoc signed test build. Permissions won't survive updates; don't publish this DMG." >&2
    SUFFIX="-adhoc"
    KEYCHAIN=""
elif [ ! -e "$KEYCHAIN" ] || ! security find-identity -p codesigning "$KEYCHAIN" | grep -qF "\"$IDENTITY\""; then
    echo "No \"$IDENTITY\" key in $KEYCHAIN. Run scripts/make-signing-identity.sh first." >&2
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

if [ -n "$KEYCHAIN" ]; then
    # Unlock the signing keychain only for the build, and put it on the search list (codesign needs that),
    # then lock it and restore the search list whatever happens.
    ORIGINAL_KEYCHAINS=()
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; ORIGINAL_KEYCHAINS+=("${line#\"}")
    done < <(security list-keychains -d user)
    relock() {
        security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"
        security lock-keychain "$KEYCHAIN"
    }
    trap relock EXIT
    echo "Enter the password for Relay's signing keychain:"
    security unlock-keychain "$KEYCHAIN"
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KEYCHAIN"
fi
RELAY_VERSION="$VERSION" RELAY_SIGN_IDENTITY="$IDENTITY" RELAY_SIGN_KEYCHAIN="$KEYCHAIN" scripts/make-app.sh
if [ -n "$KEYCHAIN" ]; then
    relock
    trap - EXIT
fi
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
