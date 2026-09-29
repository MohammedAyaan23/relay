#!/bin/bash
# Runs Relay.app's --self-check with this checkout's .build folder hidden, the way it runs on other Macs.
# SwiftPM's Bundle.module falls back to this checkout's absolute .build path, which hides a missing bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Relay.app}"

if [ -e .build-hidden ]; then
    echo ".build-hidden exists from an earlier run. Rename it back to .build first." >&2
    exit 1
fi
restore() {
    if [ -d .build-hidden ]; then mv .build-hidden .build; fi
}
trap restore EXIT
mv .build .build-hidden

if perl -e 'alarm 60; exec @ARGV' "$APP/Contents/MacOS/Relay" --self-check; then
    echo "Portability check: ok"
else
    echo "Portability check failed: Relay crashed or hung without this checkout's .build folder." >&2
    exit 1
fi
