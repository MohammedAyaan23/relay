# Releasing Relay

## Once

1. Create the signing key:

   ```bash
   scripts/make-signing-identity.sh
   ```

   It asks you to choose a password for a separate keychain, `relay-signing`, that holds only Relay's key.
   That keychain stays locked except while `make release` signs (you type the password then), so no other
   program can sign as Relay. The certificate isn't marked trusted on your Mac; codesign doesn't need it.
   If `codesign` ever asks to use the key, click **Allow**, not "Always Allow".
2. **Back it up offline.** Every release must be signed with this key: a new one makes every user grant
   permissions again, and anyone who has it can make programs that get Relay's permissions on users' Macs.
   - Keep a copy of `~/Library/Keychains/relay-signing.keychain-db` (it's encrypted with your keychain
     password) on an encrypted external drive or in an encrypted disk image stored offline.
   - Never put it, or an exported `.p12`, in this repo or in a cloud-synced folder.
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
