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
- [ ] Settings…: change the hotkey; the new hotkey works and the old one doesn't
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
- [ ] "Pause" / "next song" / "previous track" control Music, and also a playing YouTube tab
- [ ] "Take a screenshot": Relay asks for Screen Recording once (you may need to reopen Relay); the file appears in your screenshot folder and the pill names the folder
- [ ] After denying a permission and then allowing it in System Settings, the same spoken command works without relaunching (except Screen Recording, which macOS may require a relaunch for)
- [ ] Open the screenshot you just took: Relay's pill and panel are NOT in the image
- [ ] "Turn the volume up 10 percent" raises it by 10 (not to 10%); "turn it up to 80" sets 80%
- [ ] With a USB headset/DAC as output: "volume up" works; "mute" silences it (falls back to 0% if the device has no mute)
- [ ] "Open sound settings" / "open lock screen settings" do NOT change volume or lock the Mac; "show my notifications" does NOT turn on Do Not Disturb
- [ ] After rebuilding Relay, if lock/media/brightness keys stop working: remove and re-add Relay under Privacy & Security → Accessibility (each build has a new ad-hoc signature)
- [ ] "Tell Claude to mute the tests" goes to Claude, and "search for sound effects" opens a web search
- [ ] `~/Library/Application Support/Relay/decisions.jsonl` has one line per command
