#!/bin/bash
# Renders the app icon (scripts/make-icon.swift) and packs every size into Resources/Relay.icns.
# Only needed when the icon design changes; the .icns is committed.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift scripts/make-icon.swift "$WORK/icon.png"
SET="$WORK/Relay.iconset"
mkdir "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon.png" --out "$SET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/icon.png" --out "$SET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$SET" -o Resources/Relay.icns
echo "Wrote Resources/Relay.icns"
