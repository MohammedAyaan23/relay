#!/bin/bash
# Builds a signed, portability-checked Relay DMG for GitHub Releases. See RELEASING.md.
# The app is built from a clean export of the committed sources in a temporary folder, so a release contains
# exactly what's committed and no path from this Mac. The signing keychain is unlocked only for signing.
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
if [ -n "$(git status --porcelain)" ]; then
    echo "Commit or stash your changes first: releases are built from the committed sources only." >&2
    git status --short >&2
    exit 1
fi
DMG="dist/Relay-$VERSION$SUFFIX.dmg"
if [ -e "$DMG" ]; then
    echo "$DMG already exists. Bump VERSION, or move the old DMG away yourself." >&2
    exit 1
fi

# Everything temporary lives here; the keychain is locked again and the search list restored on any exit.
WORK="$(mktemp -d /tmp/relay-release.XXXXXX)"
ORIGINAL_KEYCHAINS=()
cleanup() {
    rm -rf "$WORK"
    if [ ${#ORIGINAL_KEYCHAINS[@]} -gt 0 ]; then
        security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"
        security lock-keychain "$KEYCHAIN"
    fi
}
trap cleanup EXIT

# 1. Build from the committed sources, in a folder with no personal path in it.
mkdir "$WORK/src"
git archive HEAD | tar -x -C "$WORK/src"
(cd "$WORK/src" && RELAY_VERSION="$VERSION" RELAY_BUILD_NUMBER="$(git -C "$OLDPWD" rev-list --count HEAD)" \
    RELAY_SIGN_IDENTITY=- scripts/make-app.sh)
rm -rf build/Relay.app
mkdir -p build
ditto "$WORK/src/build/Relay.app" build/Relay.app
rm -rf "$WORK/src" # its .build is gone too, so the portability check below is like another Mac's
if strings build/Relay.app/Contents/MacOS/Relay | grep -qF "$HOME"; then
    echo "The app contains a path from your home folder; refusing to release it." >&2
    exit 1
fi

# 2. Sign the app and the DMG with the release key.
if [ -n "$KEYCHAIN" ]; then
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; ORIGINAL_KEYCHAINS+=("${line#\"}")
    done < <(security list-keychains -d user)
    echo "Enter the password for Relay's signing keychain:"
    security unlock-keychain "$KEYCHAIN"
    # codesign only finds keychains on the search list.
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KEYCHAIN"
fi
scripts/sign-app.sh build/Relay.app "$IDENTITY" "$KEYCHAIN"
scripts/check-portable.sh build/Relay.app

STAGE="$WORK/stage"
mkdir "$STAGE"
ditto build/Relay.app "$STAGE/Relay.app"
ln -s /Applications "$STAGE/Applications"
cp "Resources/First launch.txt" "$STAGE/"
# Built inside the temp folder and moved into dist/ only when complete, so a failure leaves no partial DMG.
hdiutil create -volname "Relay" -srcfolder "$STAGE" -format UDZO -quiet "$WORK/Relay.dmg"
codesign --sign "$IDENTITY" ${KEYCHAIN:+--keychain "$KEYCHAIN"} "$WORK/Relay.dmg"
codesign --verify "$WORK/Relay.dmg"
mkdir -p dist
mv "$WORK/Relay.dmg" "$DMG"
echo "Built $DMG"
shasum -a 256 "$DMG"
