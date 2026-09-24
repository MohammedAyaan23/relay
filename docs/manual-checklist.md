# Relay manual checklist

Run after `make run`. Note: every rebuild changes the local signature, so macOS may ask for
microphone/speech permission again after rebuilding.

- [ ] First launch: the panel appears, the microphone and speech recognition prompts appear, and the panel ends on "Ready."
- [ ] The menu-bar icon shows (waveform), and there's no Dock icon
- [ ] Menu → Choose Active Project… → pick a scratch git repo; the menu shows "Project: <name>"
- [ ] With another app in front (e.g. TextEdit), press ⌥Space: the icon becomes a mic and the panel says "Listening…"; TextEdit keeps keyboard focus
- [ ] Say "open Safari", press ⌥Space: Safari opens; the panel shows the transcript, "command 0.xx · open_app 0.xx" and "Opened Safari."
- [ ] Say "google mechanical keyboards": the default browser opens a Google search
- [ ] Say "I had a great lunch today": "Didn't sound like a command: …"; nothing opens
- [ ] Say "tell Claude to create a file called hello.txt containing hi": the Claude section streams tool calls; you get a notification; the file exists in the project
- [ ] Say "tell Claude to also add a second line saying bye": it continues the same session (hello.txt gets the line)
- [ ] Say "tell Claude to run python3 -c 'print(1)'": the result mentions "Blocked: Bash: …"
- [ ] Start a long Claude task, press Stop: the panel shows "Stopped Claude."
- [ ] Say "start a new Claude session": "Started a new Claude session for <name>."
- [ ] Settings…: change the hotkey; the new hotkey works and the old one doesn't
- [ ] Quit while Claude is running: Relay quits and no `claude` process is left (`pgrep -fl "claude -p"`)
- [ ] `~/Library/Application Support/Relay/decisions.jsonl` has one line per command
