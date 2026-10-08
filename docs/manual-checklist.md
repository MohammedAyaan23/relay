# Relay manual checklist

Run after `make run`. Note: every rebuild changes the local signature, so macOS may ask for
microphone/speech permission again after rebuilding.

- [ ] First launch: the glass pill appears at the bottom centre showing "Getting ready…", the microphone and speech recognition prompts appear, and the pill shows "Ready." then fades out
- [ ] The menu-bar icon shows (waveform), and there's no Dock icon
- [ ] Menu → Choose Active Project… → pick a scratch git repo; the menu shows "Project: <name>"
- [ ] With another app in front (e.g. TextEdit), press ⌥Space: the pill springs in with a pulsing red dot and waveform bars that move with your voice; the icon becomes a mic; TextEdit keeps keyboard focus; clicks pass through the pill
- [ ] Say "open Safari", press ⌥Space: the pill shimmers "Transcribing…" / "Thinking…", then shows a green ✓ "Opened Safari." for ~2.5s and fades; Safari opens; the panel does NOT pop up
- [ ] Say "google mechanical keyboards": the default browser opens a Google search
- [ ] Say "I had a great lunch today": the pill shows an ⓘ "Didn't sound like a command: …"; nothing opens
- [ ] Say "tell Claude to create a file called hello.txt containing hi": the panel opens by itself and streams tool calls; you get a notification; the file exists in the project
- [ ] Say "tell Claude to also add a second line saying bye": it continues the same session (hello.txt gets the line)
- [ ] Say "tell Claude to run python3 -c 'print(1)'": the result mentions "Blocked: Bash: …"
- [ ] Start a long Claude task, press Stop: the panel shows "Stopped Claude."
- [ ] Say "start a new Claude session": "Started a new Claude session for <name>."
- [ ] Settings…: click the hotkey, press ⌃⌘R: the new hotkey works and ⌥Space doesn't
- [ ] Settings…: click the hotkey, press R alone: "Add ⌘, ⌥, ⌃ or ⇧"; press Esc: recording stops and the old hotkey still works
- [ ] Settings…: click the hotkey, press a shortcut another app holds (e.g. ⌘Space if Spotlight uses it): "That shortcut is taken, so try another" or it registers but never fires — either way, set it back and the old one works
- [ ] Settings…: click the hotkey, then close Settings without pressing anything: the hotkey still works
- [ ] After updating from a build that used KeyboardShortcuts: the hotkey you had before still works
- [ ] Quit while Claude is running: Relay quits and no `claude` process is left (`pgrep -fl "claude -p"`)
- [ ] Say "open photoshop" (not installed): the pill shows an orange ⚠ "No app matching …"
- [ ] Press ⌥Space twice quickly several times: the pill never gets stuck on screen
- [ ] Goo: while listening, coloured blobs drift and merge like a lava lamp; talking louder swells and spreads them; silence settles them
- [ ] Goo: after the second press the blobs gather and orbit ("Transcribing…"/"Thinking…"), then collapse into one coloured droplet with the result icon
- [ ] The pill lands with a squash-and-stretch bounce and drips down when it leaves
- [ ] System Settings → Accessibility → Display → Reduce motion ON: the goo holds still and the pill only fades in/out
- [ ] "Set volume to 40 percent": the volume changes; the pill shows "Volume 40%" with the level bar filling to 40%
- [ ] "Turn the volume up" / "it's too loud" / "mute" / "unmute" each work and show the new level
- [ ] "Brightness to 70 percent" (first time): the panel shows the Relay Brightness setup steps; after building the shortcut, the command sets 70%
- [ ] "A bit brighter" / "dim the display": Relay asks for Accessibility once; after allowing, brightness steps up/down
- [ ] "Switch to dark mode" / "switch to light mode": Relay asks for Automation (System Events) once; appearance switches
- [ ] "Turn on do not disturb" / "turn off do not disturb": after building the Focus shortcuts, the Focus icon in Control Center changes
- [ ] "Lock my Mac": the screen locks immediately
- [ ] "Keyboard light to 30 percent" / "keyboard brighter" / "dim the keyboard" / "turn the keyboard light off": the MacBook keyboard backlight changes, with no permission prompt; the pill shows the new level
- [ ] "Pause" / "next song" / "previous track" control Music, and also a playing YouTube tab
- [ ] "Take a screenshot": Relay asks for Screen Recording once (you may need to reopen Relay); the file appears in your screenshot folder and the pill names the folder
- [ ] After denying a permission and then allowing it in System Settings, the same spoken command works without relaunching (except Screen Recording, which macOS may require a relaunch for)
- [ ] Open the screenshot you just took: Relay's pill and panel are NOT in the image
- [ ] "Turn the volume up 10 percent" raises it by 10 (not to 10%); "turn it up to 80" sets 80%
- [ ] With a USB headset/DAC as output: "volume up" works; "mute" silences it (falls back to 0% if the device has no mute)
- [ ] "Open sound settings" / "open lock screen settings" do NOT change volume or lock the Mac; "show my notifications" does NOT turn on Do Not Disturb
- [ ] After rebuilding Relay, if lock/media/brightness keys stop working: remove and re-add Relay under Privacy & Security → Accessibility (each build has a new ad-hoc signature)
- [ ] "Tell Claude to mute the tests" goes to Claude, and "search for sound effects" opens a web search
- [ ] With TextEdit open and unsaved: "quit TextEdit" shows TextEdit's save prompt (nothing is lost)
- [ ] "Hide this app" hides the app in front; "quit Slack" when Slack isn't running says so and lists running apps
- [ ] "Minimize this window" / "make this full screen" / "close the tab" act on the app in front (Safari tab closes)
- [ ] "Make a new folder called invoices": appears on the Desktop; saying it again creates "invoices 2"
- [ ] With a Finder window in front: "make a new folder called drafts" asks for Finder control once, then creates it in that window's folder
- [ ] "Create a text file called todo in documents" creates ~/Documents/todo.txt
- [ ] "Open the <name of a file you have>" with one match opens it; with several, the panel lists them and clicking one opens it
- [ ] "Find my <file>" reveals it in Finder; "show the downloads folder in finder" opens Downloads
- [ ] "Screenshot this window" captures only the front window (no pill in the image)
- [ ] "Screenshot an area": drag a region → saved; try again and press Esc → "Screenshot cancelled"
- [ ] "Copy a screenshot", then paste into Notes: the image appears
- [ ] "Take a screenshot and show it" opens the new screenshot in Preview
- [ ] "Find my <file that lives in iCloud Drive>" finds it; the panel shows its folder as "iCloud Drive/…"
- [ ] Click a file in the panel's list, then say "close this window": the app in front closes its window (not Relay's panel)
- [ ] "Screenshot an area", press Esc: the pill says "Screenshot cancelled" (not an error)
- [ ] First "make a new folder called x" with Finder in front: the pill keeps animating while the Finder permission prompt is up
- [ ] "How close is the moon" / "where is Taiwan" do NOT close a window or search files; "close the Safari window" while another app is in front says "Safari isn't in front."
- [ ] Copy some text, then with TextEdit in front say "type see you soon.": "see you soon." appears; paste again afterwards and your original copied text comes back
- [ ] "Type" into a browser text field (e.g. a search box) works the same
- [ ] "Note that the car needs servicing": Relay asks to control Notes once; a note called "Relay" gets a dated line at the top; a second note goes above the first
- [ ] Make your own note titled "Relay" (with an image in it), then say "note that test": your note is untouched; Relay creates its own "Relay" note with the "Voice notes from Relay" line
- [ ] Delete Relay's note, then say "note that again": a fresh Relay note is created (nothing is written into Recently Deleted)
- [ ] "Type" into a slow web app (e.g. a busy chat tab): the dictated text is pasted, not your previous clipboard
- [ ] "Remind me to buy milk": Relay asks for Reminders once; the reminder appears in your default list with no alert
- [ ] "Remind me in 2 minutes to stretch": the reminder alerts about 2 minutes later
- [ ] "Set a pasta timer for 1 minute": the panel shows it counting down; a notification with sound arrives when it ends
- [ ] Start a 2-minute timer, quit Relay, wait: the notification still arrives
- [ ] Start two timers; "how long is left on the timer" lists both; "cancel the pasta timer" removes only that one; the panel's ✕ cancels the other
- [ ] `~/Library/Application Support/Relay/decisions.jsonl` has one line per command

## Installing (end users)

- [ ] `make release` (with the certificate set up) builds `dist/Relay-<version>.dmg` and prints "Portability check: ok"
- [ ] In a new macOS user account: open the DMG, drag Relay to Applications, open it, click Open Anyway in Privacy & Security, and Relay starts
- [ ] The welcome window appears once: step 1 shows the hotkey recorder; step 2 shows Microphone/Speech rows (Allow works, ✓ appears) and the Laya download progress then "Ready ✓"; step 3 shows whether Claude Code was found
- [ ] Close the welcome window at step 1, relaunch: it doesn't come back; menu → Welcome… opens it at step 1
- [ ] Bump VERSION, `make release`, install the new DMG over the old app: Microphone, Speech and Accessibility are still granted (no prompts)
- [ ] With `ReleaseInfo.repository` set to a repo whose latest release is newer: Settings → Check now shows "Update available: v…", and the menu shows "Update available: v…" which opens the release page
- [ ] Turn off "Check for updates automatically": no check happens on the next launch (Settings → Check now still works)
- [ ] Settings shows "Relay <version> (build N)" at the bottom

## Security fixes (v0.1.1)

- [ ] Hardened Runtime build: the hotkey records (microphone works), "switch to dark mode" works (Apple events), "make a new folder called x" with Finder in front works, and "keyboard light to 30 percent" works
- [ ] Say just "quit": Relay asks "Quit which app?" and nothing quits; "quit this app" quits the front app
- [ ] A Claude job finishing or failing shows a notification that names only the project (no reply or error text)
- [ ] Quit Relay during a long Claude job: no `claude` process is left (`pgrep -fl "claude -p"`)
- [ ] Dictate into a Terminal window: the text is pasted on one line and nothing runs
