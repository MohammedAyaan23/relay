#!/bin/bash
# One-time setup: creates Relay's free self-made code-signing key in its own keychain, protected by a
# password you choose. The keychain stays locked except while `make release` signs, so no other program
# can sign as Relay. Every release signed with it keeps users' permissions across updates.
# The certificate is never marked trusted on this Mac: codesign doesn't need that. Back it up (RELEASING.md).
set -euo pipefail
NAME="Relay Signing"
KEYCHAIN="$HOME/Library/Keychains/relay-signing.keychain-db"

if [ -e "$KEYCHAIN" ]; then
    if security find-identity -p codesigning "$KEYCHAIN" | grep -qF "\"$NAME\""; then
        echo "Already set up: \"$NAME\" in $KEYCHAIN"
        exit 0
    fi
    echo "$KEYCHAIN exists but has no \"$NAME\" key. Check it in Keychain Access before running this again." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2> /dev/null

echo "Choose a password for Relay's signing keychain. You'll type it for each release, and it can't be"
echo "recovered, so save it in a password manager now."
security create-keychain "$KEYCHAIN"
# Lock again after 5 minutes idle and when the Mac sleeps.
security set-keychain-settings -l -u -t 300 "$KEYCHAIN"
security import "$TMP/key.pem" -k "$KEYCHAIN" -t priv -T /usr/bin/codesign > /dev/null
security import "$TMP/cert.pem" -k "$KEYCHAIN" > /dev/null
# Let codesign use the key once the keychain is unlocked. Without this, signing fails with
# errSecInternalComponent. macOS asks for the keychain password (not passed on the command line).
echo "Enter the same keychain password once more, to let codesign use the key:"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" > /dev/null
security lock-keychain "$KEYCHAIN"

if ! security find-identity -p codesigning "$KEYCHAIN" | grep -qF "\"$NAME\""; then
    echo "\"$NAME\" wasn't created properly. Check $KEYCHAIN in Keychain Access." >&2
    exit 1
fi
echo "Ready: \"$NAME\" is in $KEYCHAIN (locked). Back it up as RELEASING.md describes."

if security find-certificate -c "Relay Self-Signed" "$HOME/Library/Keychains/login.keychain-db" > /dev/null 2>&1; then
    echo
    echo "The old \"Relay Self-Signed\" key is still in your login keychain, where any program can sign with it."
    echo "Once you no longer need it, remove it and its trust setting with:"
    echo "  security delete-identity -c \"Relay Self-Signed\" -t ~/Library/Keychains/login.keychain-db"
fi
