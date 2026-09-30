#!/bin/bash
# Tests make-signing-identity.sh and make-release.sh's signing checks against a fake `security` command,
# so no real keychain is touched. HOME points at a temp folder, so the signing keychain path is fake too.
set -euo pipefail
cd "$(dirname "$0")/../.."
FAKE="$(mktemp -d)"
trap 'rm -rf "$FAKE"' EXIT
export HOME="$FAKE/home"
mkdir -p "$HOME/Library/Keychains"
KEYCHAIN="$HOME/Library/Keychains/relay-signing.keychain-db"
LOG="$FAKE/calls"

cat > "$FAKE/security" <<'SH'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/calls"
keychain="$HOME/Library/Keychains/relay-signing.keychain-db"
case "$1" in
    create-keychain) touch "${@: -1}" ;;
    import) if [[ "$*" == *" -t priv "* ]]; then touch "$keychain.key"; fi ;;
    find-identity)
        if [ -e "$keychain.key" ]; then echo '  1) ABC "Relay Signing" (CSSMERR_TP_NOT_TRUSTED)'; fi ;;
    set-keychain-settings|set-key-partition-list|lock-keychain|unlock-keychain|find-certificate) ;;
    *) echo "unexpected: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$FAKE/security"
fail() { echo "FAIL: $1"; cat "$LOG" 2> /dev/null; exit 1; }

# 1. make-release refuses to start without the signing keychain.
if output="$(PATH="$FAKE:$PATH" scripts/make-release.sh 2>&1)"; then fail "make-release ran without a signing keychain"; fi
[[ "$output" == *"Run scripts/make-signing-identity.sh first"* ]] || fail "unexpected make-release message: $output"

# 2. A fresh setup creates the dedicated keychain, imports the key and certificate, and locks it again.
PATH="$FAKE:$PATH" scripts/make-signing-identity.sh > /dev/null 2>&1 || fail "setup failed"
[ -e "$KEYCHAIN" ] || fail "no dedicated keychain created"
grep -q "^import .* -k $KEYCHAIN -t priv -T /usr/bin/codesign" "$LOG" || fail "the key wasn't imported into the dedicated keychain"
grep -q "^set-key-partition-list -S apple-tool:,apple:,codesign: -s $KEYCHAIN" "$LOG" \
    || fail "codesign wasn't given access to the key (errSecInternalComponent when signing)"
grep -q -- "-k " <(grep "^set-key-partition-list" "$LOG") && fail "the keychain password was passed on the command line"
grep -q "^lock-keychain $KEYCHAIN" "$LOG" || fail "the keychain was left unlocked"
grep -qE "^(create-keychain|import|set-).*login.keychain" "$LOG" && fail "the key went into the login keychain"
grep -q "add-trusted-cert" "$LOG" && fail "the certificate was trusted (not needed)"

# 3. Running it again changes nothing.
: > "$LOG"
PATH="$FAKE:$PATH" scripts/make-signing-identity.sh > /dev/null 2>&1 || fail "second run failed"
grep -qE "^(create-keychain|import)" "$LOG" && fail "second run created or imported again"

echo "PASS: signing key lives in its own locked keychain; make-release requires it"
