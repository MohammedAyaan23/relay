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

# Code injection: with the Hardened Runtime on, macOS ignores DYLD_INSERT_LIBRARIES, so another program
# can't load its code into Relay and borrow Relay's permissions (microphone, Accessibility, ...).
PROBE="$(mktemp -d)"
trap 'rm -rf "$PROBE"; restore' EXIT
cat > "$PROBE/probe.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
__attribute__((constructor)) static void probe(void) {
    FILE *f = fopen(getenv("RELAY_PROBE_MARKER"), "w");
    if (f) fclose(f);
}
EOF
clang -dynamiclib -o "$PROBE/probe.dylib" "$PROBE/probe.c"
# Started directly: macOS strips DYLD_* variables when launching protected tools such as perl.
RELAY_PROBE_MARKER="$PROBE/loaded" DYLD_INSERT_LIBRARIES="$PROBE/probe.dylib" \
    "$APP/Contents/MacOS/Relay" --self-check > /dev/null 2>&1 &
RELAY_PID=$!
for _ in $(seq 60); do kill -0 "$RELAY_PID" 2> /dev/null || break; sleep 1; done
kill "$RELAY_PID" 2> /dev/null || true
if [ -e "$PROBE/loaded" ]; then
    echo "Injection check failed: an injected library ran inside Relay. Sign with --options runtime." >&2
    exit 1
fi
echo "Injection check: ok"
