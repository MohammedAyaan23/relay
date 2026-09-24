# Relay: voice assistant for macOS (v1 design)

Date: 2026-09-24
Status: approved in conversation, awaiting written-spec review

## 1. Purpose

Relay is a menu-bar app you control by voice. Its main job is hands-free driving of Claude Code while you do
other things. It also handles a few quick Mac actions. It is a personal, learn-as-you-go project.

**Success for v1:** press a hotkey, say "tell Claude to add tests for the parser", press the hotkey again,
and watch Claude Code work in the active project from a floating panel. "Tell Claude to also cover the
empty case" continues the same Claude session. "Open Safari" and "google mechanical keyboards" work as
well.

## 2. Decisions already made

| Topic | Decision | Why |
|---|---|---|
| Language | Swift 6, macOS 26+, Apple Silicon | Spike (`spike/RESULTS.md`): same speed as Rust, far less setup, native Mac APIs |
| Speech-to-text | Apple `SpeechAnalyzer` / `SpeechTranscriber`, on-device | No model to ship; 70–100 ms per short clip |
| Intent routing | Laya decision model through the FluidUse Swift package (Core ML, Neural Engine), no LLM | ~4 ms per decision; the spike routed 11/11 phrases correctly |
| Trigger | Global hotkey toggles listening: press to start, press to stop | Handles long Claude prompts; predictable |
| Claude working dir | One "active project" folder chosen from the menu bar | Simple and predictable |
| Claude output | Floating panel that streams progress, plus a notification when done | Glanceable; lets follow-ups resume the session |
| Claude permissions | `--permission-mode acceptEdits`: file edits and simple file commands (`touch`, `mkdir`, …) are auto-approved; other shell commands only via the project's own allowlist; blocked calls are shown in the panel | Safe; approval from the panel is the next feature |
| Claude sessions | One continuing session per project; reset by voice ("new Claude session") or menu | Behaves like a terminal tab |
| v1 actions | Ask Claude Code, open app, web search | Core goal plus two cheap actions that exercise routing |
| Build | Swift package plus `scripts/make-app.sh` to assemble a signed `.app`; no Xcode | Command Line Tools only on this machine |
| Name | Relay | |

## 3. Out of scope for v1

In rough priority order for later work:

1. Approving Claude tool calls from the panel (via Claude Code's `--permission-prompt-tool` hook, with Relay acting as a small local tool server)
2. Codex (`codex exec --json`)
3. Letting Laya decide whether a command continues the current Claude session or starts a new one
4. Session mode (keep listening for command after command) and spoken override of the active project
5. Spoken replies (text-to-speech summaries)
6. Creating files and folders, and typing or dictating into the frontmost app
7. GLiNER2 entity extraction (only if rule-based extraction proves too weak)
8. Session history and a background-helper (XPC) split

## 4. Architecture

### 4.1 Flow for one command

```
hotkey ─▶ Listening ─ hotkey ─▶ Transcribing ─▶ Routing ─▶ Extracting ─▶ Acting ─▶ Done | Error ─▶ Idle
```

### 4.2 Modules (Swift package targets)

| Target | Responsibility | Depends on |
|---|---|---|
| `Capture` | Start/stop mic recording with `AVAudioEngine`; return the recorded audio (a temporary audio file) | AVFoundation |
| `Transcription` | Audio file → text via `SpeechAnalyzer`; make sure the speech model is installed (`AssetInventory`) | Speech |
| `Routing` | Laya yes/no gate, then a Laya choice question; returns an `Intent` plus probabilities | FluidUse |
| `Extraction` | Rule-based extraction of each intent's details (app name, search query, Claude prompt) | none |
| `Actions` | `AppLauncher`, `WebSearcher`, `ClaudeRunner` (process, stream parser, session store) | Foundation, AppKit |
| `AssistantCore` | The state machine that coordinates everything; publishes state for the UI | all of the above |
| `RelayApp` | SwiftUI menu-bar app: hotkey, floating panel, project picker, settings | AssistantCore, KeyboardShortcuts |

Everything except `RelayApp` has no UI. `AssistantCore` depends on protocols (`Transcribing`, `Routing`,
`ActionPerforming`, …), not concrete types, so tests can inject fakes.

### 4.3 Routing

The spike showed that a catch-all "none" option in the choice question absorbs real commands (6/11 correct).
Relay therefore routes in three steps:

0. **Session-reset rule (no model):** a short transcript (at most 8 words) that mentions Claude plus a
   reset word ("new", "fresh", "reset", "restart", "clear") and either a session word ("session",
   "conversation", "chat") or "reset"/"restart" is `new_claude_session`. Measured during implementation:
   as a fourth Laya option, a session-reset choice pulled in unrelated commands (11/14 at best across four
   wordings), so it's handled as a fixed phrase instead.
1. **Gate:** a yes/no question.
   - Instructions: "Is the user giving the computer an instruction to perform an action?"
   - Meaning of false: "just talking, not asking the computer to do anything"
   - Meaning of true: "asking the computer to open, search, or hand a task to Claude"
   - If P(true) < `gateThreshold` (initially 0.5), result: not a command.
2. **Choice:** "Which action should the voice assistant take for this spoken command?", with these options
   and descriptions:
   - `open_app`: "launch or switch to an application on the Mac"
   - `web_search`: "search the internet or look something up in the browser"
   - `ask_claude`: "send a coding task or question to Claude Code"
   - If the top probability < `choiceThreshold` (initially **0.35**: with three options chance is 0.33, and
     correct web searches in the phrase set won with 0.37–0.44), result: ambiguous. The top two options are
     returned so the panel can show them.

Other details:
- Only the 128-token Laya bucket is loaded (~640 MB, CPU + Neural Engine). Long Claude prompts may be cut
  off at the end. This is acceptable because the intent is carried by how a command starts. `stateWasTruncated`
  is logged.
- Both thresholds are settings values, and are verified against the labelled phrase set during implementation.
- The option wording above is the starting point; changes must keep or improve the routing test score.

### 4.4 Extraction rules

Transcripts are lowercased, punctuation is removed, and whitespace is collapsed before matching.

- **`open_app`:**
  - The app index lists `.app` bundles in `/Applications`, `/System/Applications`,
    `/System/Applications/Utilities` and `~/Applications`, one level deep, refreshed at launch.
  - Pick the app whose normalized name appears in the transcript, preferring the longest match
    ("visual studio code" over "code").
  - If nothing matches, strip lead-in words ("open", "launch", "fire up", "start", "switch to") and
    fuzzy-match the remainder by edit distance. If the closest match is still too far, fail with the
    three closest names.
- **`web_search`:**
  - Strip the longest matching lead-in from: "search the web for", "search for", "search", "google",
    "look up", "find".
  - The remainder is the query. If it is empty, fail.
  - The URL is `https://www.google.com/search?q=<percent-encoded query>`, opened in the default browser
    with `NSWorkspace`.
- **`ask_claude`:**
  - Strip a leading "ask claude (to)" or "tell claude (to)", or "claude," if present.
  - The rest is the prompt, sent word for word as transcribed (original casing and punctuation, not
    the normalized text).
- **`new_claude_session`:** no details to extract.

### 4.5 ClaudeRunner

- **Finding the executable:**
  - At launch, run `/bin/zsh -lc 'command -v claude'` once and cache the result, because apps launched from
    the Dock or menu bar don't inherit the shell `PATH`.
  - A path override in settings takes precedence.
- **Command:**
  - `claude -p <prompt> --output-format stream-json --verbose --permission-mode acceptEdits [--resume <id>]`
  - The working directory is the active project, and stdin is `/dev/null`.
- **Parsing:** each line of stdout is decoded into a `ClaudeEvent`:
  - `system` init (carries `session_id`)
  - `assistantText(String)`
  - `toolUse(name, summary)`: summary is e.g. the file path for Edit/Write/Read, or the command for Bash
  - `toolResult(isError)`
  - `result(text, sessionID, durationMs, costUSD, isError, deniedTools)`: `deniedTools` comes from the result's
    `permission_denials` list, e.g. "Bash: python3 …". The panel shows them as "Blocked: …".

  Verified against Claude Code 2.1.281 (2026-09-24). The real stream also contains `system` `hook_*` and
  `thinking_tokens` lines, `thinking` content blocks and `rate_limit_event` lines; all are skipped.

  Anything else becomes `.unknown` and is logged. A line that isn't valid JSON is logged and skipped;
  neither ends the job.
- **Sessions:**
  - `~/Library/Application Support/Relay/sessions.json` maps the project's absolute path to the latest
    `session_id`.
  - It is written on every `result` event.
  - It is cleared by `new_claude_session` or by the menu item.
- **Running jobs:**
  - At most one Claude job at a time. An `ask_claude` command while one is running fails with "Claude is
    still working. Stop it first." `open_app` and `web_search` still run.
  - **Stop** sends SIGINT, then SIGTERM after 3 s if the process is still running.
- **Errors:**
  - A non-zero exit or a `result` with `isError` shows the last 20 lines of stderr.
  - The saved session ID is cleared only if stderr says the session can't be found or resumed.

### 4.6 UI (`RelayApp` target)

- **Menu-bar-only app:** `LSUIElement = true`, so there is no Dock icon.
- **Menu-bar icon** reflects the state: idle, listening, or working.
- **Menu items:**
  - active project (shows the folder name; choosing it opens a folder picker)
  - new Claude session
  - show panel
  - settings
  - quit
- **Floating panel:**
  - A non-activating `NSPanel` hosting SwiftUI, so it floats above other windows without taking keyboard focus.
  - Opens on hotkey or from the menu.
  - Content, top to bottom:
    1. state line
    2. transcript
    3. chosen intent and probability
    4. for Claude: a scrolling event list (text, one-line tool calls) and a final result line with duration and cost
    5. a Stop button while Claude runs
  - Open app and web search show a one-line result.
- **Notification:** a macOS notification when a Claude job finishes (`UserNotifications`).
- **Settings:**
  - hotkey (default ⌥Space, set with the `KeyboardShortcuts` recorder)
  - `claude` path override
  - gate and choice thresholds

### 4.7 Setup on first launch

1. Request Microphone and Speech Recognition permission. `Info.plist` includes the usage descriptions.
2. Make sure Apple's speech model is installed, and download Laya (~640 MB) into the FluidUse cache, showing
   progress in the panel. The hotkey shows "Getting ready…" until both are loaded.
3. If there's no active project, Claude commands answer "No active project. Pick one from the menu."

## 5. Error handling

Every failure shows a plain-language message in the panel and returns to Idle. Nothing fails silently.

| Situation | Behavior |
|---|---|
| Mic or speech permission denied | Message plus a button that opens the right System Settings pane |
| Empty transcript | "Didn't catch anything." |
| Gate below threshold | "Didn't sound like a command: '<transcript>'". No action |
| Choice below threshold | Show the top two guesses. No action |
| App not found | "No app matching '<name>'", plus the three closest names |
| Empty search query | "What should I search for?" |
| `claude` not found | Message pointing to the path override in settings |
| Claude exits with an error | End of stderr; session kept unless it is reported invalid |
| Unknown or invalid stream line | Logged, skipped; job continues |
| Hotkey during Transcribing, Routing or Extracting | Ignored |
| Hotkey during a Claude job | Starts a new recording (the job keeps running in the panel) |

**Decision log:** each routed command appends one JSON line to
`~/Library/Application Support/Relay/decisions.jsonl`, with:
- timestamp
- transcript
- gate P(true)
- choice probabilities
- chosen intent
- extracted details
- whether the state was truncated
- outcome

This log is the source for growing the routing test set.

## 6. Project layout

```
Package.swift                  macOS 26, Swift 6; FluidUse pinned to a commit; KeyboardShortcuts
Sources/{Capture,Transcription,Routing,Extraction,Actions,AssistantCore,RelayApp}/
Tests/{ExtractionTests,ActionsTests,AssistantCoreTests,RoutingTests,TranscriptionTests}/
Tests/ActionsTests/Fixtures/   recorded stream-json output, fake `claude` script
Tests/RoutingTests/phrases.json labelled phrases (see §7)
Resources/Info.plist
scripts/make-app.sh            swift build -c release, then assemble Relay.app, then `codesign -s -` (local signature)
Makefile                       build | test | test-routing | app | run
```

FluidUse is pinned to a commit because its README says `0.2.1`, but the latest tag is `v0.2.0`.

**Resource bundles:** SwiftPM's generated resource lookup checks the `.app` root folder (which `codesign`
rejects) and then this checkout's `.build` folder. `Relay.app` therefore works when built from this checkout,
which is fine for a personal app. The Laya code path doesn't load FluidUse's bundle at all.

## 7. Testing

The framework is Swift Testing. It runs under Command Line Tools with extra framework-path flags
(`-F`/`-rpath` to `/Library/Developer/CommandLineTools/Library/Developer/{Frameworks,usr/lib}`), which the
Makefile adds. This was confirmed working on 2026-09-24.

- **ExtractionTests:** lead-in stripping for each intent, and app matching against an injected fake app
  index (longest match, fuzzy fallback, no match).
- **ActionsTests:**
  - the stream parser against recorded fixtures, including unknown and invalid lines
  - `ClaudeRunner` against a fake `claude` shell script: argument construction, `--resume` on the second
    call, clearing the session, refusing a second concurrent job, stop
  - app launching and URL opening through a replaceable interface
- **AssistantCoreTests:** every state transition, and every row of the §5 table, with fake speech, routing
  and actions.
- **RoutingTests (opt-in, `make test-routing`):** loads the real model and reports accuracy on
  `phrases.json`. The initial set is:
  - the spike's phrases, except the file-creation one (not a v1 intent)
  - at least three `new_claude_session` phrasings
  - at least two non-commands

  The accuracy measured on the first implementation becomes the committed baseline, and the test fails if
  accuracy drops below it.
- **Manual checklist (tested by hand):**
  - permission prompts on first launch
  - the hotkey works while another app is in front
  - record → stop → correct transcript
  - panel stays on top without taking focus
  - notification on Claude finishing
  - Stop interrupts Claude
