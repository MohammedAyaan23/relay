# Relay: installable for end users (design)

Date: 2026-09-29
Status: approved in conversation, awaiting written-spec review
Builds on: v1 and sub-projects A, B, C (merged to `master`)

## 1. Purpose

Anyone with an Apple Silicon Mac on macOS 26 can download Relay, install it, grant permissions, and use it.
They can also learn about new versions later without losing those permissions. The earlier constraints stay:
small and quick, no new models, minimal third-party code, and non-destructive only.

**Success:**
- A DMG from GitHub Releases installs and runs on a Mac that has never seen this checkout, with no crash
  anywhere, including Settings.
- The first launch shows a short welcome that gets the user to a working "open Safari".
- Installing a newer build over an older one keeps the Microphone, Speech, Accessibility and other
  permissions.
- When a newer release exists, the menu says so.

**User decisions made in brainstorming:**
- **Free distribution:** no paid Apple Developer account, so no Developer ID and no notarization. Users
  click **Open Anyway** once.
- **Updates:** GitHub Releases plus a daily update check. There's no automatic install.
- **Onboarding:** a short three-step welcome window.
- **Hotkey:** replace the KeyboardShortcuts package with a built-in Carbon hotkey.

**Why the hotkey change is required:** KeyboardShortcuts calls `NSLocalizedString(…, bundle: .module)`.
SwiftPM's `Bundle.module` looks only at the `.app` root (where `codesign` won't allow a bundle) and at this
checkout's absolute `.build` path. On any other Mac, opening Settings would crash. FluidUse and FluidAudio
use `Bundle.module` only in code paths Relay doesn't call.

## 2. New target: `AppSupport`

A new library target, `AppSupport`, holds the pure, testable logic for this work. It has no dependencies,
and the RelayApp target depends on it. It is tested by `Tests/AppSupportTests`. The UI and system calls stay
in RelayApp.

## 3. Built-in hotkey

### 3.1 `Hotkey` value (AppSupport)

```swift
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32      // Carbon virtual key code, e.g. 49 = Space
    public var modifiers: UInt32    // Carbon modifier mask: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096
    public static let `default` = Hotkey(keyCode: 49, modifiers: 2048)   // ⌥Space
}
```

- **`isValid`:** at least one of ⌘⌥⌃⇧, and the key is not a modifier key itself.
- **`displayText`:**
  - modifier symbols in the order ⌃⌥⇧⌘, then the key name, with no separators
  - the key name is "Space", "Return", "Tab", "Esc", "Delete", "F1"…"F12" or arrows ←→↑↓, or else the
    uppercase letter or digit from a fixed key-code table (ANSI layout)
  - examples: "⌥Space", "⌃⌘R"
  - a key code missing from the table shows as "Key 123"
- **Storage:** JSON under UserDefaults key `hotkey`, read and written through
  `HotkeyStore.load(from:) / save(_:to:)`.
- **Migration:** when `hotkey` is absent, `load` reads the old KeyboardShortcuts value under
  `KeyboardShortcuts_toggleListening`. That value is a JSON string such as
  `{"carbonKeyCode":49,"carbonModifiers":2048}`. If it decodes and `isValid`, `load` saves it under `hotkey`
  and returns it.
- **Fallback:** a missing, corrupt or invalid value gives `.default`.

### 3.2 Registration (RelayApp: `HotkeyCenter`)

- Uses Carbon `RegisterEventHotKey` plus `InstallEventHandler` on the application event target. This needs
  no permission.
- `register(_ hotkey:) -> Bool` unregisters the previous hotkey first. If the new one fails (the OS returns
  an error, for example because another app took it), it re-registers the previous one and returns false.
- The handler calls the existing hotkey action. AppController's current `onKeyUp` logic (haptic,
  `hud.present()`, `hotkeyPressed()`, scheduled hide) moves unchanged onto this handler. It fires on key
  press (`kEventHotKeyPressed`), since Carbon's press event is the reliable one.

### 3.3 Recorder (RelayApp: `HotkeyRecorder` SwiftUI view)

- It shows the current `displayText` and a **Record** button.
- While recording, a local `NSEvent` key-down monitor takes the next key:
  - **Esc** without modifiers cancels.
  - A key with no ⌘⌥⌃⇧ shows "Add ⌘, ⌥, ⌃ or ⇧" and keeps recording.
  - A valid combination calls `HotkeyCenter.register`. On success it saves and shows the new text. On
    failure it shows **"That shortcut is taken, so try another"** and keeps the old hotkey.
- While recording, the global hotkey is unregistered so the key press reaches the recorder, and it is
  restored afterwards.
- Settings and the welcome window use the same view.

### 3.4 Removal

KeyboardShortcuts is removed from `Package.swift`, `Package.resolved`, `Preferences.swift`, `SettingsView.swift`
and `AppController.swift`. The `missingShortcut` panel logic becomes "the hotkey failed to register at
launch", with the message "⌥Space is taken by another app. Choose a different shortcut in Settings."

## 4. Signing, packaging and the portability check

### 4.1 One-time signing identity: `scripts/make-signing-identity.sh`

- If the keychain already has the certificate "Relay Self-Signed", the script stops with "already set up".
- Otherwise it:
  1. uses `openssl` to make an RSA-2048 key and a self-signed certificate (CN "Relay Self-Signed",
     10-year validity, `extendedKeyUsage = codeSigning`, `keyUsage = digitalSignature`, not a CA)
  2. exports them as a PKCS#12 file into a temporary directory
  3. imports that file into the login keychain with `-T /usr/bin/codesign`
  4. trusts the certificate for code signing with `security add-trusted-cert -p codeSign`, which asks for
     the user's password once
  5. deletes the temporary files and prints `security find-identity -v -p codesigning`
- **Why:** the designated requirement of a self-signed build is tied to this certificate. TCC keeps
  permissions for every build signed with it.
- The private key never leaves the keychain afterwards. RELEASING.md says to back it up (export from Keychain
  Access) because losing it means users re-grant permissions once.

### 4.2 `make release` (`scripts/make-release.sh`)

1. **Signing check:** stops if `security find-identity -v -p codesigning` lacks "Relay Self-Signed", printing
   "Run scripts/make-signing-identity.sh first".
2. **Version:** reads `VERSION` (one line, `MAJOR.MINOR.PATCH`) and stops if the format is wrong.
3. **Build:** `scripts/make-app.sh` runs with `RELAY_VERSION` and `RELAY_SIGN_IDENTITY` set.
   - `make-app.sh` copies the Info.plist and sets `CFBundleShortVersionString` to the version and
     `CFBundleVersion` to `git rev-list --count HEAD`, both through `plutil -replace`.
   - It builds `swift build -c release --arch arm64 --product Relay`.
   - It signs with the given identity. Without one it keeps the current ad-hoc `-` signature, so `make app`
     is unchanged for development.
4. **Portability check:**
   - `.build` is renamed to `.build-hidden`, and a `trap` always renames it back.
   - `build/Relay.app/Contents/MacOS/Relay --self-check` runs with a 60 s timeout and must exit with 0.
5. **DMG:** a staging folder holds `Relay.app`, an `Applications` symlink and `First launch.txt`. The DMG is
   made with `hdiutil create -volname "Relay" -srcfolder <staging> -format UDZO dist/Relay-<version>.dmg`.
   An existing DMG of the same name makes the script stop rather than overwrite it.
6. **Output:** prints the DMG path and its `shasum -a 256`.

**`First launch.txt`:**
- Drag Relay onto Applications, then open it from Applications.
- macOS says it can't verify the developer. Open System Settings → Privacy & Security, scroll down, and
  click **Open Anyway** next to Relay. This is needed once.
- Relay appears in the menu bar. The welcome window explains the rest.
- Requirements: Apple Silicon, macOS 26. Claude Code is optional.

### 4.3 `--self-check` (RelayApp)

- When the arguments contain `--self-check`, Relay skips the normal launch: no hotkey, no `prepare()`, no
  menu extra and no permission prompts.
- It builds each SwiftUI root view Relay shows (Settings, the welcome window's three steps, the panel and the
  HUD) inside an `NSHostingView` and lays each one out once.
- It checks that `HotkeyStore.load` works and that the Info.plist version is readable.
- It prints "self-check ok" and exits with 0. Any crash makes the check fail, which is the point.

## 5. Versioning and the update check

### 5.1 Version

- `VERSION` at the repo root starts at `0.1.0` and is the only source of truth.
- The bottom of Settings shows "Relay 0.1.0 (build N)", read from the bundle.

### 5.2 Release location

- `Sources/RelayApp/ReleaseInfo.swift` holds `static let repository = ""`, in the form `owner/name`.
- While it's empty, the update check is off and hidden. The repo has no GitHub remote yet, so the user sets
  it before the first release.

### 5.3 Logic (AppSupport)

- **`AppVersion`:**
  - parses "0.2.0" or "v0.2.0" into numeric parts
  - compares part by part, treating missing parts as 0 (`0.10.0` > `0.9.2`, `1.0` == `1.0.0`)
  - returns nil for junk such as "latest", "" or "1.x"
- **`UpdateSchedule.isDue(lastCheck: Date?, now: Date) -> Bool`:** true when there's no last check or at
  least 24 h have passed.
- **`ReleaseFeed` protocol:** `func latest() async throws -> ReleaseSummary`, where `ReleaseSummary` holds
  `tag`, `url`, `draft` and `prerelease`.
- **`GitHubReleaseFeed`:**
  - `GET https://api.github.com/repos/<repo>/releases/latest` with headers `Accept: application/vnd.github+json`
    and `User-Agent: Relay`
  - a 10 s timeout and no authentication
  - decodes `tag_name`, `html_url`, `draft` and `prerelease`
- **`UpdateChecker.check(current:feed:) async -> UpdateResult`:** returns `.upToDate`,
  `.available(version, url)` or `.failed`.
  - Drafts, pre-releases, unparseable tags and any thrown error give `.failed` or `.upToDate`, never a crash
    or an alert.
  - It sends only the request above: no identifiers and no analytics.

### 5.4 App behaviour (RelayApp)

- **Automatic check:**
  - 10 s after launch, and then every hour, Relay asks `isDue`. When it's due, it checks and saves the check
    time under UserDefaults key `lastUpdateCheck`.
  - This happens only if `repository` is set and the `checkForUpdates` setting (default on) is on.
- **Menu:**
  - `.available` adds a menu item **"Update available: v0.2.0…"** that opens the release page.
  - `.upToDate` and `.failed` leave the menu unchanged, and the last known "available" result stays until a
    later check says up to date.
- **Settings:**
  - a "Check for updates automatically" switch
  - a **Check now** button showing "You're up to date", "Update available: v0.2.0" (as a link) or "Couldn't
    check. Try again later."
- **Updating:** the user downloads the new DMG and drags Relay into Applications, replacing the old copy.
  The same certificate keeps permissions.

## 6. Welcome window

### 6.1 Logic (AppSupport: `WelcomeFlow`)

- Steps: `.meet`, `.setup` and `.tryIt`, with `next()` and `back()` that clamp at the ends.
- `shouldShowOnLaunch(defaults)` is true until `markSeen` sets UserDefaults key `welcomeSeen`.
- `PermissionRow.State` is `.granted`, `.notAsked` or `.denied`, and maps to button text:
  - `.granted` shows a ✓ with no button
  - `.notAsked` shows **Allow**
  - `.denied` shows **Open Settings**

### 6.2 Window (RelayApp: `WelcomeWindow`)

- It opens on first launch, before or alongside `prepare()`. It is a normal titled window of about 480×360,
  and Relay activates so the window comes to the front.
- The menu has a **"Welcome…"** item to reopen it.
- Closing the window at any step counts as seen.

**Step 1, Meet Relay:**
- "Relay does things on your Mac when you ask out loud."
- The `HotkeyRecorder` from 3.3 lets the user change the shortcut.
- "Relay lives in the menu bar, look for its icon at the top right."

**Step 2, Set up:**
- **Microphone** and **Speech Recognition** rows show live status from `AVCaptureDevice.authorizationStatus`
  and `SFSpeechRecognizer.authorizationStatus()`, refreshed every second while the window is open.
  - **Allow** requests the permission.
  - **Open Settings** opens the matching Privacy pane (the existing `openPrivacySettings` anchors).
- A **Laya model** row shows `assistant.message` while `phase == .preparing` (the existing download
  progress text), "Ready ✓" when idle, and the error with a **Try again** button (which calls `prepare()`)
  if `prepareFailed`.
- **Continue** is always enabled. A missing item shows "Relay can't listen until this is allowed."

**Step 3, Try it:**
- "Press ⌥Space (the current hotkey), say 'open Safari', then press it again."
- Examples: "search the web for pasta recipes", "set volume to 30", "remind me to call mum at 5pm".
- **Optional:**
  - **Claude Code:** "found" when Relay's existing Claude lookup succeeds, otherwise "not found" with a link
    to Claude Code's install page.
  - **Accessibility:** "asked the first time you use typing or window commands".
  - **Brightness and Focus:** a link to the Shortcuts bridge section of the README.
- **Done** closes the window.

## 7. Docs

- **README.md (new):**
  - what Relay is
  - requirements
  - install (DMG, drag, Open Anyway, with the exact System Settings path)
  - the permissions and why each is needed
  - updating
  - a list of example commands by area
  - the Shortcuts bridge setup (moved or linked from the existing text)
  - building from source (`make app`)
  - **Uninstall:**
    1. Quit Relay and drag it to the Trash.
    2. Optionally remove its files:
       - `~/Library/Application Support/Relay`
       - `~/Library/Application Support/FluidUse/Models/laya-coreml`
       - `defaults delete dev.relay.Relay`
       - `tccutil reset All dev.relay.Relay`
    3. Relay's note in Apple Notes and any reminders it made are the user's to keep or delete.
- **RELEASING.md (new):**
  1. Run `scripts/make-signing-identity.sh` once, and back up the certificate.
  2. Set `ReleaseInfo.repository`.
  3. Bump `VERSION` and commit.
  4. Run `make release`.
  5. Run `gh release create v<version> dist/Relay-<version>.dmg --notes …`, with the checksum in the notes.
  6. Tag format is `vX.Y.Z`.

## 8. Testing

**Unit tests (`Tests/AppSupportTests`):**
- **`Hotkey`:**
  - `displayText` for ⌥Space, ⌃⌘R, ⇧F5 and an unknown key code
  - `isValid` rejects no modifier and a modifier key alone
  - the order ⌃⌥⇧⌘
- **`HotkeyStore`:**
  - save and load round trip
  - migration from `KeyboardShortcuts_toggleListening`, which then writes `hotkey`
  - a corrupt JSON value or an invalid combination gives `.default`
  - an existing `hotkey` wins over the old key
- **`AppVersion`:** parsing with and without "v", comparing different lengths, junk giving nil, and
  `0.10.0` > `0.9.2`.
- **`UpdateSchedule`:** nil last check, 23 h, and 24 h.
- **`UpdateChecker`:**
  - newer gives available, equal or older gives up to date
  - pre-release, draft and junk tags are ignored
  - a thrown error gives failed
  - decoding a saved sample GitHub JSON through a fake `ReleaseFeed`
- **`WelcomeFlow`:** clamped next and back, and seen or unseen through a test `UserDefaults` suite.

**Build checks:** `make test` stays green, `make test-routing` stays at 64/64, and `make release` runs the
portability self-check with `.build` hidden.

**Manual checklist (added to `docs/manual-checklist.md`):**
- **Fresh user:** in a new macOS user account, install from the DMG, go through Open Anyway and the welcome
  steps, grant permissions, then press the hotkey and say "open Safari".
- **Hotkey:**
  - change it in Settings and use it
  - choose a shortcut another app holds, and see the "taken" message with the old hotkey kept
  - the migrated shortcut from the old build still works
- **Permissions:** install a second build (bump `VERSION`) over the first, and confirm Microphone, Speech and
  Accessibility are still granted.
- **Updates:** set `repository` to a repo with a newer test release. Confirm "Check now" shows it and the menu
  item appears, and that turning the switch off stops the automatic check.

## 9. Out of scope

- Developer ID signing, notarization and Homebrew casks.
- Sparkle or any in-app installer.
- Intel Macs and macOS versions before 26.
- Localisation.
