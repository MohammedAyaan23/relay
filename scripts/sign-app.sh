#!/bin/bash
# Signs Relay.app with the Hardened Runtime and Relay's entitlements.
# Usage: scripts/sign-app.sh <app> <identity> [keychain]   ("-" = local ad-hoc signature)
# Hardened Runtime: macOS refuses injected libraries and debuggers, so no other program can borrow
# Relay's permissions. The entitlements allow only the microphone and Apple events.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"
IDENTITY="$2"
KEYCHAIN_ARGS=()
if [ -n "${3:-}" ]; then KEYCHAIN_ARGS=(--keychain "$3"); fi
codesign --force --options runtime --entitlements Resources/Relay.entitlements \
    ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
