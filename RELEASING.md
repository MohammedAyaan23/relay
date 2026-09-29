# Releasing Relay

## Once

1. Create the signing certificate:

   ```bash
   scripts/make-signing-identity.sh
   ```

   It asks for your password once. The first release may also ask whether `codesign` can use the key:
   choose **Always Allow**.
2. **Back it up.** In Keychain Access, find "Relay Self-Signed" under My Certificates, right-click →
   Export, and save the `.p12` somewhere safe. Every release must be signed with this certificate: a new one
   makes every user grant permissions again.
3. Set the repository in `Sources/RelayApp/ReleaseInfo.swift`, e.g. `static let repository = "you/relay"`.
   While it's empty the update check is off.

## Each release

1. Put the new version in `VERSION` (e.g. `0.2.0`) and commit.
2. Build:

   ```bash
   make release
   ```

   This signs Relay, runs the portability self-check with `.build` hidden, and writes
   `dist/Relay-<version>.dmg` plus its SHA-256. It refuses to overwrite an existing DMG.
3. Publish (tags are `vX.Y.Z`):

   ```bash
   gh release create v0.2.0 dist/Relay-0.2.0.dmg --title "Relay 0.2.0" --notes "What's new… SHA-256: <checksum>"
   ```

For a local test of the pipeline without the certificate: `RELAY_SIGN_IDENTITY=- scripts/make-release.sh`
(writes a `-adhoc` DMG; don't publish it).
