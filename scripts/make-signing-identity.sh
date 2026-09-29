#!/bin/bash
# One-time setup: creates the free "Relay Self-Signed" code-signing certificate in your login keychain.
# Every release signed with it keeps users' permissions across updates. Back it up (see RELEASING.md).
set -euo pipefail
NAME="Relay Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "\"$NAME\""; then
    echo "Already set up: $NAME"
    exit 0
fi
if security find-certificate -c "$NAME" "$KEYCHAIN" > /dev/null 2>&1; then
    echo "A certificate named \"$NAME\" exists but isn't usable for code signing." >&2
    echo "Open Keychain Access, check it (and its private key), and remove or fix it yourself first." >&2
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

# macOS's own LibreSSL writes a PKCS#12 file that `security import` accepts.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2> /dev/null
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/relay.p12" -passout "pass:$PASS"
security import "$TMP/relay.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
echo "macOS will now ask for your password to trust the certificate for code signing."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
security find-identity -v -p codesigning
