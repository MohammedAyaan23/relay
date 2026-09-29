#!/bin/bash
# Tests make-signing-identity.sh against a fake `security` command, so no real keychain is touched.
# Case: an earlier run imported the certificate but the trust step was cancelled.
set -euo pipefail
cd "$(dirname "$0")/../.."
FAKE="$(mktemp -d)"
trap 'rm -rf "$FAKE"' EXIT

cat > "$FAKE/security" <<'SH'
#!/bin/bash
state="$(dirname "$0")/trusted"
case "$1" in
    find-identity)
        if [ -e "$state" ]; then echo '  1) ABC "Relay Self-Signed"'; echo '     1 valid identities found'
        else echo '     0 valid identities found'; fi ;;
    find-certificate)
        if [[ " $* " == *" -p "* ]]; then printf -- '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n'; fi ;;
    add-trusted-cert) touch "$state" ;;
    import) echo "unexpected import: the certificate already exists" >&2; exit 1 ;;
    *) echo "unexpected: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$FAKE/security"

if ! output="$(PATH="$FAKE:$PATH" scripts/make-signing-identity.sh 2>&1)"; then
    echo "FAIL: the script stopped instead of finishing the trust step:"; echo "$output"; exit 1
fi
[ -e "$FAKE/trusted" ] || { echo "FAIL: add-trusted-cert was not run"; exit 1; }
echo "PASS: an imported but untrusted certificate gets trusted on a re-run"
