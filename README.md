# Relay

Relay is a small menu-bar voice assistant for the Mac. Press a hotkey (⌥Space by default), say what you want,
and press it again. Speech is turned into text on your Mac, and Relay opens apps, searches the web, controls
volume and media, handles windows and files, types for you, adds notes, reminders and timers, and can drive
[Claude Code](https://claude.com/product/claude-code). It never deletes, overwrites or force-quits anything.

## Requirements

- A Mac with Apple Silicon and macOS 26 or later
- About 700 MB free for the speech-routing model, downloaded once on first launch
- Optional: Claude Code, for "tell Claude to…" commands

## Install

1. Download `Relay-<version>.dmg` from the latest GitHub release and open it.
2. Drag **Relay** onto **Applications**, then open Relay from Applications.
3. macOS says it can't verify the developer, because Relay is free and not signed by Apple. Open
   **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Relay. This is
   needed once.
4. A welcome window walks you through the hotkey, permissions and a first command.

## Permissions

| Permission | Why | When it's asked |
|---|---|---|
| Microphone | to hear you, only between your two hotkey presses | first launch |
| Speech Recognition | to turn speech into text on this Mac | first launch |
| Accessibility | typing, window commands, brightness and media keys | first time you use one |
| Automation | dark mode (System Events), Finder folders, Apple Notes | first time you use one |
| Screen Recording | screenshots | first screenshot |
| Reminders | adding reminders | first reminder |

## Updating

Relay checks GitHub once a day and shows **Update available** in its menu when a new version is out (turn
this off in Settings). Download the new DMG and drag Relay into Applications, replacing the old one. Your
permissions stay.

## Things to say

- **Apps and web:** "open Safari", "quit TextEdit", "hide this app", "google mechanical keyboards"
- **Mac:** "set volume to 40 percent", "mute", "switch to dark mode", "lock my Mac", "keyboard light to 30 percent", "next song"
- **Windows and files:** "minimize this window", "close the tab", "make a new folder called invoices", "find my tax return"
- **Screenshots:** "take a screenshot", "screenshot this window", "screenshot an area", "copy a screenshot"
- **Typing and capture:** "type see you soon.", "note that the car needs servicing", "remind me to call mum at 5pm", "set a pasta timer for 9 minutes"
- **Claude Code:** choose a project from the menu, then "tell Claude to add a README", "start a new Claude session"

## Brightness and Focus

macOS has no public API for screen brightness or Do Not Disturb, so Relay uses three small shortcuts you build
once in the Shortcuts app. Relay shows the steps the first time you ask; they're also in
[docs/shortcuts-setup.md](docs/shortcuts-setup.md).

## Uninstall

1. Quit Relay (menu → Quit Relay) and drag it from Applications to the Trash.
2. Optionally remove its data and permissions:

   ```bash
   rm -r ~/Library/Application\ Support/Relay
   rm -r ~/Library/Application\ Support/FluidUse/Models/laya-coreml
   defaults delete dev.relay.Relay
   tccutil reset All dev.relay.Relay
   ```

3. Relay's "Relay" note in Apple Notes and any reminders it added are yours to keep or delete.

## Building from source

Needs the Command Line Tools (`xcode-select --install`).

```bash
make app     # build/Relay.app, locally signed
make run     # build and open it
make test    # unit tests
```

Releases are described in [RELEASING.md](RELEASING.md).
