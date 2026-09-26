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
- [ ] `~/Library/Application Support/Relay/decisions.jsonl` has one line per command
