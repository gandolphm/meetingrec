# meetingrec

Record a meeting on your Mac. Claude Code then turns the recording into
Obsidian notes, with to-dos, decisions and follow-ups. Transcription runs locally with
Whisper; no meeting bot joins the call.

There are three parts:

| Part | What it does | Where |
| --- | --- | --- |
| **Recorder** | Records a virtual meeting as two tracks: your mic (`mic.wav`) and everyone else (`system.wav`). Start and stop it from the menu bar or the terminal. | `bin/meetingrec`, `hammerspoon/init.lua` |
| **scribe** | Your **personal** notes: TL;DR, your to-dos (at most five), decisions and questions to ask. | `scribe/` (an Obsidian vault) |
| **teamnotes** | **Team-facing** notes: third person, action items for everyone grouped by owner, and a plain-Markdown copy you can paste into Slack or email. | `teamnotes/` (a second Obsidian vault) |

```
meetingrec/
├── bin/meetingrec              # the recorder CLI
├── bin/clock-check, drift-check  # diagnostics for track timing (rarely needed)
├── hammerspoon/init.lua        # menu-bar start/stop button
├── config.example.sh           # copy to ~/.config/meetingrec/config.sh
├── scribe/                     # Obsidian vault #1 — personal notes
│   ├── input/                  #   recordings land here
│   ├── meeting-notes/          #   notes are written here
│   ├── transcripts/            #   only used if you ask to keep a transcript
│   ├── Tasks.md                #   to-do dashboard
│   └── .claude/skills/meeting-notes/
└── teamnotes/                  # Obsidian vault #2 — team notes
    ├── input/  meeting-notes/  share/
    ├── Action Items.md         #   everyone's open items, by owner
    └── .claude/skills/team-notes/
```

Recordings, transcripts and notes are git-ignored, so nothing you record gets committed.

> **Always tell people you're recording.** No bot appears in the participant list, so
> nobody knows unless you say so.

---

## Requirements

- A Mac with **Apple silicon**, running **macOS 14.2 or later**. System-audio capture uses
  Core Audio taps, which first shipped in 14.2.
- A **Claude Code** subscription or API access.
- About 1 GB of disk space for the Whisper model and build tools.

---

## Setup

Allow about 20 minutes. Do the steps in order.

### 1. Install the command-line tools

Open **Terminal** and run each block.

**Xcode Command Line Tools** (provides git, Swift and python3):
```bash
xcode-select --install
```
If it says they're already installed, move on.

**Homebrew**, if you don't have it ([brew.sh](https://brew.sh)):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
At the end, the installer prints two lines that start with `echo` or `eval`. Run them so
`brew` is on your PATH. Then close Terminal and open it again.

**ffmpeg and Whisper:**
```bash
brew install ffmpeg whisper.cpp
```

**The Whisper model** (`small.en`, about 470 MB):
```bash
mkdir -p ~/.whisper-models
curl -L -o ~/.whisper-models/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
```

**Claude Code:**
```bash
curl -fsSL https://claude.ai/install.sh | bash
```
Then run `claude` once and sign in. See the
[Claude Code docs](https://docs.claude.com/en/docs/claude-code/overview) for other ways
to install it.

### 2. Clone this repo

Clone it wherever you like. Nothing in the tool depends on where it lives. Commands in
this guide that start with `bin/`, `scribe/` or `teamnotes/` are run **from the repo
folder** (the one containing this README). `<repo>` means that folder's full path.

```bash
git clone https://github.com/gandolphm/meetingrec.git   # creates a folder called meetingrec
cd meetingrec
chmod +x bin/*
pwd                            # this is your <repo> path; note it down
```

### 3. Install audiotee (system-audio capture)

[audiotee](https://github.com/makeusabrew/audiotee) is a small open-source tool. It
captures the audio your Mac is playing, which during a call is everyone else's voice.
Build it from source and pin it to the commit this tool was tested with:

```bash
mkdir -p ~/src ~/bin
git clone https://github.com/makeusabrew/audiotee.git ~/src/audiotee
git -C ~/src/audiotee checkout 56ac954
cd ~/src/audiotee && swift build -c release && cd -
cp ~/src/audiotee/.build/release/audiotee ~/bin/audiotee
```

The build takes a minute or two. Check that the binary is in place:
```bash
ls -l ~/bin/audiotee
```

### 4. Configure the recorder

```bash
mkdir -p ~/.config/meetingrec
cp config.example.sh ~/.config/meetingrec/config.sh
```

The defaults work if you followed steps 2 and 3 exactly. If you put audiotee somewhere
else, edit `AUDIOTEE_BIN` in `~/.config/meetingrec/config.sh`.

### 5. Do a test recording and grant permissions

macOS asks for permission the first time each app records audio. Do a short test run from
Terminal so you can answer the prompts now, not at the start of a real call:

```bash
bin/meetingrec start "test"
```

Allow the **Microphone** and **System Audio Recording** prompts. Play a YouTube video and
talk for 15 seconds, then run:

```bash
bin/meetingrec stop
```

`stop` reports what it captured. If it prints a **WARNING** that a track is silent, a
permission is missing. Fix it in **System Settings → Privacy & Security**:
- **Microphone** → turn on Terminal.
- **Screen & System Audio Recording** → in the *System Audio Recording Only* list, add
  and turn on Terminal.

Then quit and reopen Terminal and try again.

Delete the test session afterwards:
```bash
rm -rf scribe/input/*_test
```

### 6. Install Hammerspoon (menu-bar button)

[Hammerspoon](https://www.hammerspoon.org) is a free macOS automation app. Here it adds a
small **○** button to your menu bar that starts and stops recordings. It's optional, since
the terminal commands work too, but it's much easier mid-meeting.

1. **Install it:**
   ```bash
   brew install --cask hammerspoon
   ```
   You can also download it from [hammerspoon.org](https://www.hammerspoon.org) and drag
   it into Applications.
2. **Open Hammerspoon** from Applications. It asks for **Accessibility** access. You can
   **decline**: this config doesn't use it.
3. **Open its preferences** (click the Hammerspoon icon in the menu bar → *Preferences*)
   and tick **Launch Hammerspoon at login**.
4. **Install the config.** Run this **from the repo folder**. It copies the config and
   fills in where you cloned the repo:
   ```bash
   mkdir -p ~/.hammerspoon
   sed "s|^local REPO = .*|local REPO = \"$PWD\"|" hammerspoon/init.lua > ~/.hammerspoon/init.lua
   ```
   If you already have your own `~/.hammerspoon/init.lua`, don't overwrite it. Write to
   `~/.hammerspoon/meetingrec.lua` instead (same command, different last path), then add
   this line to your `init.lua`:
   ```lua
   require("meetingrec")
   ```
   If you ever move the repo, run the command again.
5. **Reload:** Hammerspoon menu-bar icon → *Reload Config*. A **○** appears in the menu bar.
6. **Grant Hammerspoon its own permissions.** macOS gives permissions to the app that
   launches the recording, so Terminal's permissions don't carry over. Start a test
   recording from the ○ menu, then allow the prompts. If no prompts appear, add
   **Hammerspoon** under **Microphone** and **System Audio Recording Only** in System
   Settings (see setup step 5).

If the button misbehaves, check `~/.hammerspoon/meetingrec.log`.

### 7. Set up Obsidian

1. **Install Obsidian** from [obsidian.md](https://obsidian.md). It's free. You need
   version 1.9 or later for Bases.
2. **Open the vaults.** Obsidian → *Open folder as vault* → choose `<repo>/scribe`. Do the
   same for `<repo>/teamnotes` if you'll write team notes. Each is a separate vault.
   (In the file picker, Cmd+Shift+G lets you paste the path.)
3. **Enable Bases** (in each vault): *Settings → Core plugins → Bases* → on. This powers
   `index.base`, a sortable table of all your meetings.
4. **Install the Tasks plugin** (in each vault): *Settings → Community plugins → Turn on
   community plugins → Browse* → search **Tasks** (by Clare Macrae and Ilyas Landikov) →
   *Install* → *Enable*. This makes the to-do checkboxes work and powers `Tasks.md` and
   `Action Items.md`.
5. *Optional:* the **Day Planner** community plugin shows to-dos on a daily timeline. The
   skill adds `⏳` scheduled dates when a meeting says when you'll do something, and Day
   Planner picks those up.

`index.base` in `scribe/` is created automatically the first time you write a note.

### 8. Personalise the names tables and team profile

Open `scribe/.claude/skills/meeting-notes/reference/names.md` and fill in the **Me** row
with your name and the ways Whisper tends to mishear it. The skill uses it to know which
to-dos are yours.

Both name tables hold the people, companies and terms Whisper gets wrong (e.g. an accented
name, or a company name that sounds like ordinary words). One is `names.md` above, the other
is in `teamnotes/CLAUDE.md`. Replace the example rows with your own, and add a row whenever
you notice a new mishearing.

If you'll write team notes, fill in `teamnotes/.claude/skills/team-notes/profiles/team.md`
with your team's name and roster.

> These files end up holding colleagues', customers' and partners' names. If your clone
> has a public remote, don't push them.

---

## Usage

### Record a virtual meeting

**From the menu bar:** click **○** → *Start recording…*, and type a title if you like. The
button shows **● 12m** while recording. Click it → *Stop* when the call ends.

**From the terminal:**
```bash
bin/meetingrec start "Acme check-in"   # title is optional
bin/meetingrec status
bin/meetingrec stop
```

**Wear headphones** if you can. On speakers your mic also picks up the other side, and
some lines get attributed to you. If you're on speakers, use *Start (mic only — on
speakers)* or `meetingrec start --mic-only`. That records just one track, and the skill
works out who said what from context.

Each recording is a folder in `scribe/input/`, like
`2026-10-01T14-00_acme-check-in/`, containing `mic.wav`, `system.wav` and
`session.json`.

### Write your personal notes (scribe)

```bash
cd <repo>/scribe
claude
```
Then type **`scribe`**, or "write up notes from this meeting".

The skill:
1. finds the newest recording in `input/`;
2. asks a few quick questions (title, attendees, type), using the names to help Whisper;
3. transcribes locally with Whisper, about 90 seconds for a 30-minute call;
4. writes `meeting-notes/<Title>.md` and tells you the path;
5. deletes the recording. Say **"keep the transcript"** to move it to `transcripts/`
   instead.

Open the note in Obsidian. To-dos are tagged `#work` and appear in `Tasks.md`.

You can also drop an audio file (`.m4a`, `.mp3`, `.wav`, `.mp4`) or a transcript (`.txt`,
`.srt`, `.vtt`) into `scribe/input/`, or paste a transcript straight into the chat.

### Write team notes (teamnotes)

For a meeting whose notes go to the whole team:

1. Put the recording in `teamnotes/input/`. That can be a phone recording of an
   in-person meeting, a transcript, or a `meetingrec` session folder moved over from
   `scribe/input/`.
2. Run:
   ```bash
   cd <repo>/teamnotes
   claude
   ```
   Then type **"team notes"**.
3. Pick the **team** profile (or **other**). Mark who was present, and confirm the action-item owners
   before anything is written.
4. You get two files:
   - `meeting-notes/<Team> — YYYY-MM-DD.md` for Obsidian.
   - `share/<Team> — YYYY-MM-DD.md`, plain Markdown to paste into Slack, email or a
     Google Doc.

`Action Items.md` shows everyone's open items, grouped by owner.

---

## Customising

- **Team roster:** edit `teamnotes/.claude/skills/team-notes/profiles/team.md` when people
  join or leave. Every note's attendee and absent lists come from it.
- **Another recurring group** (e.g. a partner working group): copy `profiles/other.md` to a
  new file and fill it in. No other changes are needed.
- **Whisper model:** `small.en` is the default. For poor audio, ask the skill to re-run
  with `medium.en`, after downloading `ggml-medium.en.bin` the same way as in step 1.
- **New dashboard context:** to-dos are tagged with the note's `context` (default
  `work`). If you start using another context, add a `tags include <context>` block to
  `scribe/Tasks.md`.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `NO_ENGINE` | `brew install whisper.cpp` |
| `MODEL_NOT_FOUND` | Run the `curl` command it prints (see step 1). |
| `NO_FFMPEG` | `brew install ffmpeg` |
| `audiotee not found or not executable` | Redo step 3, or fix `AUDIOTEE_BIN` in `~/.config/meetingrec/config.sh`. |
| "system track produced no audio" / silent-track warning | System Audio Recording permission is missing for whatever started the recording (Terminal or Hammerspoon). See steps 5 and 6. |
| Skill says the inbox is empty | Check `ls scribe/input`. If you set `OUTPUT_ROOT` in your config, it must point to `scribe/input`. |
| `meeting-notes` skill not found | Start `claude` from inside `scribe/` (or `teamnotes/` for team notes). |
| ○ button missing or frozen | Hammerspoon → *Reload Config*. If that fails, quit and reopen Hammerspoon. Check `~/.hammerspoon/meetingrec.log`. |
| Tasks dashboard is empty | Install and enable the Tasks plugin in *that* vault (setup step 7). |

Each recording's measurements (track levels, timing offsets, warnings) are also appended
to `~/.local/state/meetingrec/metrics.jsonl`.

---

## License

MIT — see [LICENSE](LICENSE).
