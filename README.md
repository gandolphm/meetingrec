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

Recordings, transcripts and notes are git-ignored, so nothing you record gets committed. So
are your name tables and team roster (see [step 8](#8-your-name-tables-and-team-profile)).

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

There are two ways to install. Both end up with the same result.

- **[Quick install](#quick-install-recommended):** paste one command, then answer a few
  prompts. About 20 minutes, mostly waiting.
- **[Manual install](#manual-install):** run each step yourself. Use this if you'd rather
  not run a script from the internet, or you want to see exactly what gets downloaded.

Either way, finish with [Finish setup](#finish-setup-both-ways): Obsidian.

In the expected outputs below, `you` stands for your Mac username, and dates, times,
sizes and version numbers will differ.

### Quick install (recommended)

Open **Terminal** (press Cmd+Space, type *Terminal*, press Enter), paste this line and
press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/gandolphm/meetingrec/main/install.sh | bash
```

The script goes through these steps and skips any that are already done:

| Step | Downloaded from |
| --- | --- |
| Xcode Command Line Tools (git, Swift, python3) | Apple, via `xcode-select --install` |
| Homebrew, if you don't have it | [brew.sh](https://brew.sh) |
| ffmpeg, whisper.cpp, Hammerspoon | Homebrew |
| meetingrec, cloned to `~/meetingrec` | this GitHub repo |
| Whisper `small.en` model (465 MB), checked against its SHA-256 | [Hugging Face](https://huggingface.co/ggerganov/whisper.cpp) |
| audiotee at the pinned commit, prebuilt and checked against its SHA-256 | this repo's [releases](https://github.com/gandolphm/meetingrec/releases), built by a [GitHub Action](.github/workflows/build-audiotee.yml) from [audiotee's source](https://github.com/makeusabrew/audiotee) |
| Claude Code | [claude.ai](https://docs.claude.com/en/docs/claude-code/overview) |

It also writes `~/.config/meetingrec/config.sh` and the Hammerspoon config, starts
Hammerspoon, and adds Homebrew to your PATH in `~/.zprofile`. It doesn't change anything
else. You can [read the script](install.sh) first, or download it, look at it, then run
it:
```bash
curl -fsSL https://raw.githubusercontent.com/gandolphm/meetingrec/main/install.sh -o install.sh
less install.sh      # press q to quit
bash install.sh
```

**What you'll be asked to do while it runs:**

- **Install the command line developer tools.** If a window asks, click *Install* and
  agree. The script waits until it finishes.
- **Your Mac password.** Homebrew asks for it. Nothing appears while you type. That's
  normal; press Enter when you've finished typing it.
- **Accessibility access for Hammerspoon.** You can click *Deny*. meetingrec doesn't use
  it.
- **A test recording.** The script tells you to click the **○** in the menu bar, start a
  recording called `test`, click **Allow** on the Microphone and System Audio Recording
  prompts, play a video while you talk for 15 seconds, then stop it. Then press Enter in
  Terminal and the script checks that both tracks captured audio.

You should see something like this (each line starting with ✓ is a finished step):

```text
==> Checking this Mac
  ✓ macOS 15.1 on Apple silicon

==> Xcode Command Line Tools (git, Swift, python3)
  ✓ already installed

==> Homebrew (package manager)
  ✓ already installed

==> ffmpeg and whisper.cpp
  ! installing ffmpeg (a few minutes)…
  ✓ ffmpeg installed
  ! installing whisper-cpp (a few minutes)…
  ✓ whisper-cpp installed

==> Hammerspoon (menu-bar button)
  ✓ installed

==> meetingrec
  ✓ downloaded to /Users/you/meetingrec

==> Whisper model (small.en, 465 MB)
######################################################################## 100.0%
  ✓ downloaded and verified

==> audiotee (system-audio capture)
  ✓ downloaded commit 56ac954 (verified) → /Users/you/bin/audiotee

==> Recorder config
  ✓ created /Users/you/.config/meetingrec/config.sh

==> Your name tables and team profile
  ✓ created. Claude fills them in the first time you write up a meeting

==> Claude Code
  ✓ installed

==> Menu-bar button config
  ✓ wrote /Users/you/.hammerspoon/init.lua
  ✓ started Hammerspoon. A ○ should appear in your menu bar
  ! If Hammerspoon asks for Accessibility access, you can click Deny. It isn't needed.

==> Test recording (gives the menu-bar button its permissions)
  ...
  Press Enter when you've clicked Stop (or type s to skip):
  ✓ both tracks recorded audio. Test recording deleted

Done. meetingrec is installed in /Users/you/meetingrec
```

**If a step fails**, the script stops with a red **✗** and a message that says what went
wrong. Fix that, then paste the same command again. Steps that already finished are
skipped.

**If the test says a track is silent**, a permission is missing. Open **System Settings →
Privacy & Security** and:
- **Microphone** → turn on Hammerspoon.
- **Screen & System Audio Recording** → in the *System Audio Recording Only* list, add and
  turn on Hammerspoon.

Quit Hammerspoon (click its icon in the menu bar → *Quit Hammerspoon*), then run the
install command again to repeat the test.

**Then sign in to Claude Code.** Open a **new** Terminal window, so it picks up the new
PATH, and run:
```bash
claude
```
Expected: Claude Code starts and asks you to choose a theme, then to log in. Follow the
prompts. When you reach the `>` prompt, type `/exit`.

Then go to [Finish setup](#finish-setup-both-ways).

<details>
<summary>Options</summary>

- Install somewhere other than `~/meetingrec`:
  `curl -fsSL …/install.sh | MEETINGREC_DIR=~/Documents/meetingrec bash`
- Skip the menu-bar button (you'll use `bin/meetingrec` from Terminal):
  `curl -fsSL …/install.sh | NO_HAMMERSPOON=1 bash`
- Build audiotee on your Mac instead of downloading the prebuilt copy (takes a minute or
  two longer): `curl -fsSL …/install.sh | AUDIOTEE_FROM_SOURCE=1 bash`. The installer also
  does this by itself if the download fails or doesn't match its SHA-256.
- Already cloned the repo? Run `./install.sh` from inside it. That copy is used instead of
  a fresh clone.

</details>

---

### Manual install

Do the steps in order. Every command runs in **Terminal**.

#### 1. Install the command-line tools

**Xcode Command Line Tools** (provides git, Swift and python3):
```bash
xcode-select --install
```
Expected, if they're not installed yet:
```text
xcode-select: note: install requested for command line developer tools
```
A window then opens. Click *Install*, agree, and wait for it to finish (5–15 minutes).
If instead you get a message saying the command line tools are already installed, move on.

**Homebrew**, if you don't have it ([brew.sh](https://brew.sh)):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
It asks for your Mac password, then shows what it will install and asks you to press
Enter. It ends with:
```text
==> Installation successful!
...
==> Next steps:
- Run these commands in your terminal to add Homebrew to your PATH:
    echo >> /Users/you/.zprofile
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/you/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
```
Run the lines it prints under *Next steps*. They print nothing. Then close Terminal and
open it again. To check:
```bash
brew --version
```
Expected:
```text
Homebrew 4.6.0
```

**ffmpeg and Whisper:**
```bash
brew install ffmpeg whisper.cpp
```
This prints a lot and takes a few minutes. It ends with lines like:
```text
==> Summary
🍺  /opt/homebrew/Cellar/whisper-cpp/1.8.0: 45 files, 12MB
```
To check:
```bash
which ffmpeg whisper-cli
```
Expected:
```text
/opt/homebrew/bin/ffmpeg
/opt/homebrew/bin/whisper-cli
```

**The Whisper model** (`small.en`, 465 MB):
```bash
mkdir -p ~/.whisper-models
curl -L -o ~/.whisper-models/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
```
`mkdir` prints nothing. `curl` shows a progress table while it downloads. When it
finishes, the `% Total` column reads `100` and the size is `465M`. To check the file isn't
damaged:
```bash
shasum -a 256 ~/.whisper-models/ggml-small.en.bin
```
Expected:
```text
c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d  /Users/you/.whisper-models/ggml-small.en.bin
```
If the long number is different, delete the file and download it again.

**Claude Code:**
```bash
curl -fsSL https://claude.ai/install.sh | bash
```
Expected: it ends by saying Claude Code was installed successfully. If it also tells you
to add `~/.local/bin` to your PATH, run the command it shows. Then open a new Terminal
window and run:
```bash
claude
```
Expected: Claude Code starts and asks you to choose a theme, then to log in. Follow the
prompts. When you reach the `>` prompt, type `/exit`. See the
[Claude Code docs](https://docs.claude.com/en/docs/claude-code/overview) for other ways to
install it.

#### 2. Clone this repo

Clone it wherever you like. Nothing in the tool depends on where it lives. Commands in
this guide that start with `bin/`, `scribe/` or `teamnotes/` are run **from the repo
folder** (the one containing this README). `<repo>` means that folder's full path.

```bash
git clone https://github.com/gandolphm/meetingrec.git   # creates a folder called meetingrec
cd meetingrec
chmod +x bin/*
pwd                            # this is your <repo> path; note it down
```
Expected (`cd` and `chmod` print nothing):
```text
Cloning into 'meetingrec'...
remote: Enumerating objects: ...
Receiving objects: 100% ..., done.
Resolving deltas: 100% ..., done.
/Users/you/meetingrec
```

#### 3. Install audiotee (system-audio capture)

[audiotee](https://github.com/makeusabrew/audiotee) is a small open-source tool. It
captures the audio your Mac is playing, which during a call is everyone else's voice.
Use the commit this tool was tested with, `56ac954`. Either download the copy this repo
publishes (**A**) or build it yourself (**B**). Both give you the same program.

**A. Download it.** It's built from audiotee's source by a
[GitHub Action](.github/workflows/build-audiotee.yml) in this repo:
```bash
mkdir -p ~/bin
curl -fL --progress-bar -o ~/bin/audiotee https://github.com/gandolphm/meetingrec/releases/download/audiotee-56ac954/audiotee
chmod +x ~/bin/audiotee
shasum -a 256 ~/bin/audiotee
grep AUDIOTEE_SHA256 config.example.sh
```
Expected: a download progress bar, then the same 64-character code twice:
```text
######################################################################## 100.0%
<64-character code>  /Users/you/bin/audiotee
AUDIOTEE_SHA256="<the same 64-character code>"
```
If the two codes differ, the download is damaged: delete it with `rm ~/bin/audiotee` and
use **B** instead.

**B. Build it from source:**

```bash
mkdir -p ~/src ~/bin
git clone https://github.com/makeusabrew/audiotee.git ~/src/audiotee
git -C ~/src/audiotee checkout 56ac954
cd ~/src/audiotee && swift build -c release && cd -
cp ~/src/audiotee/.build/release/audiotee ~/bin/audiotee
```
The build takes a minute or two. Expected (`mkdir` and `cp` print nothing):
```text
Cloning into '/Users/you/src/audiotee'...
...
Note: switching to '56ac954'.
...
HEAD is now at 56ac954 ...
Building for production...
...
Build complete! (52.31s)
/Users/you/meetingrec
```
The last line is `cd -` taking you back to the repo folder.

Check that the binary is in place:
```bash
ls -l ~/bin/audiotee
```
Expected (the `x`s in `-rwxr-xr-x` mean it can run):
```text
-rwxr-xr-x  1 you  staff  412496 Oct 26 14:02 /Users/you/bin/audiotee
```

#### 4. Configure the recorder

```bash
mkdir -p ~/.config/meetingrec
cp config.example.sh ~/.config/meetingrec/config.sh
```
Expected: no output.

The defaults work if you followed steps 2 and 3 exactly. If you put audiotee somewhere
else, edit `AUDIOTEE_BIN` in `~/.config/meetingrec/config.sh`.

#### 5. Do a test recording and grant permissions

macOS asks for permission the first time each app records audio. Do a short test run from
Terminal so you can answer the prompts now, not at the start of a real call:

```bash
bin/meetingrec start "test"
```
Allow the **Microphone** and **System Audio Recording** prompts. Expected:
```text
recording: /Users/you/meetingrec/scribe/input/2026-10-26T14-05_test
  tracks: mic,system
  mic:    MacBook Pro Microphone
  output: MacBook Pro Speakers (do not change it mid-call)
```
The `mic` and `output` lines show your own devices, e.g. your headphones.

Play a YouTube video and talk for 15 seconds, then run:

```bash
bin/meetingrec stop
```
`stop` reports what it captured. Expected:
```text
stopped after 0m18s
  /Users/you/meetingrec/scribe/input/2026-10-26T14-05_test
  -rw-r--r--  1 you  staff  576044 Oct 26 14:05 /Users/you/meetingrec/scribe/input/2026-10-26T14-05_test/mic.wav
  -rw-r--r--  1 you  staff  450604 Oct 26 14:05 /Users/you/meetingrec/scribe/input/2026-10-26T14-05_test/system.wav
  format-check: audiotee metadata OK (ok|16000|1|16|...)
  format-check: system OK (32000 B/s)
  format-check: mic OK (32000 B/s)
```
The `B/s` numbers can be a little off 32000. The `format-check` lines can be in a different
order.

If it prints a line starting with **WARNING** saying a track is silent, a permission is
missing. Fix it in **System Settings → Privacy & Security**:
- **Microphone** → turn on Terminal.
- **Screen & System Audio Recording** → in the *System Audio Recording Only* list, add
  and turn on Terminal.

Then quit and reopen Terminal and try again.

Delete the test session afterwards:
```bash
rm -rf scribe/input/*_test
```
Expected: no output.

#### 6. Install Hammerspoon (menu-bar button)

[Hammerspoon](https://www.hammerspoon.org) is a free macOS automation app. Here it adds a
small **○** button to your menu bar that starts and stops recordings. It's optional, since
the terminal commands work too, but it's much easier mid-meeting.

1. **Install it:**
   ```bash
   brew install --cask hammerspoon
   ```
   Expected, at the end:
   ```text
   🍺  hammerspoon was successfully installed!
   ```
   You can also download it from [hammerspoon.org](https://www.hammerspoon.org) and drag
   it into Applications.
2. **Install the config.** Run this **from the repo folder**. It copies the config and
   fills in where you cloned the repo:
   ```bash
   mkdir -p ~/.hammerspoon
   sed "s|^local REPO = .*|local REPO = \"$PWD\"|" hammerspoon/init.lua > ~/.hammerspoon/init.lua
   ```
   Expected: no output. To check the path was filled in:
   ```bash
   grep '^local REPO' ~/.hammerspoon/init.lua
   ```
   Expected (your repo path from step 2):
   ```text
   local REPO = "/Users/you/meetingrec"
   ```
   If you already have your own `~/.hammerspoon/init.lua`, don't overwrite it. Write to
   `~/.hammerspoon/meetingrec.lua` instead (same command, different last path), then add
   this line to your `init.lua`:
   ```lua
   require("meetingrec")
   ```
   If you ever move the repo, run the command again.
3. **Open Hammerspoon** from Applications. It asks for **Accessibility** access. You can
   **decline**: this config doesn't use it. A **○** appears in the menu bar. The config
   also turns on *Launch Hammerspoon at login*, so it comes back after a restart.
   If Hammerspoon was already running, click its menu-bar icon → *Reload Config*.
4. **Grant Hammerspoon its own permissions.** macOS gives permissions to the app that
   launches the recording, so Terminal's permissions don't carry over. Start a test
   recording from the ○ menu, then allow the prompts. Stop it from the menu after 15
   seconds. If a notification says *check this recording*, a permission is missing: add
   **Hammerspoon** under **Microphone** and **System Audio Recording Only** in System
   Settings (see step 5). Delete the test session afterwards, as in step 5.

If the button misbehaves, check `~/.hammerspoon/meetingrec.log`.

---

### Finish setup (both ways)

#### 7. Set up Obsidian

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

#### 8. Your name tables and team profile

Claude sets these up the first time you use each skill.

- **Your name.** The first time you write up a meeting with `scribe`, Claude asks your name
  and how Whisper tends to mishear it. It uses your name to tell which to-dos are yours.
- **Your team.** The first time you pick the **team** profile for team notes, Claude asks
  for the team's name and roster.
- **Names Whisper gets wrong.** At the end of each write-up, Claude lists any names it had
  to correct and offers to remember them, so the next transcript gets them right. Accented
  names and company names that sound like ordinary words are the usual culprits.

All of this is saved in files that **git ignores**, so your colleagues', customers' and
partners' names are never committed, and updating meetingrec never overwrites them:

| What | File |
| --- | --- |
| Your name and names for your personal notes | `scribe/.claude/skills/meeting-notes/reference/names.local.md` |
| Names for team notes | `teamnotes/.claude/skills/team-notes/reference/names.local.md` |
| Your team's name and roster | `teamnotes/.claude/skills/team-notes/profiles/team.md` |

You can edit any of them directly too. Each sits next to tracked files that must stay as
they are, because git publishes them with the repo:

- **Templates** (`*.example.md`): the starting point the skills copy your files from.
- **`names.shared.md`**: empty in this repo, and it should stay that way. It's only for a
  team that [forks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo)
  meetingrec: the fork's maintainer fills it with names everyone on the team needs and
  commits them, so each member gets them on their next update. Never put names in it in
  your own copy of this repo.

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
Expected from `start`:
```text
recording: /Users/you/meetingrec/scribe/input/2026-10-01T14-00_acme-check-in
  tracks: mic,system
  mic:    AirPods Pro
  output: AirPods Pro (do not change it mid-call)
```
Expected from `status`: `recording` with the seconds elapsed and the folder, or `idle`
when nothing is recording:
```text
recording 754 /Users/you/meetingrec/scribe/input/2026-10-01T14-00_acme-check-in
```
Expected from `stop`: the length, the folder and the two files, as in
[setup step 5](#5-do-a-test-recording-and-grant-permissions). If it prints a line starting
with `WARNING`, read it before the recording is gone: usually a track is silent.

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
Expected: Claude Code opens with a `>` prompt. Then type **`scribe`**, or "write up notes from this meeting".

The skill:
1. finds the newest recording in `input/`;
2. asks a few quick questions (title, attendees, type), using the names to help Whisper.
   The first time, it also asks your name;
3. transcribes locally with Whisper, about 90 seconds for a 30-minute call;
4. writes `meeting-notes/<Title>.md` and tells you the path;
5. deletes the recording. Say **"keep the transcript"** to move it to `transcripts/`
   instead;
6. offers to remember any names Whisper got wrong.

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
   Expected: Claude Code opens with a `>` prompt. Then type **"team notes"**.
3. Pick the **team** profile (or **other**). The first time you pick **team**, Claude asks
   for your team's name and roster. Mark who was present, and confirm the action-item owners
   before anything is written.
4. You get two files:
   - `meeting-notes/<Team> — YYYY-MM-DD.md` for Obsidian.
   - `share/<Team> — YYYY-MM-DD.md`, plain Markdown to paste into Slack, email or a
     Google Doc.

`Action Items.md` shows everyone's open items, grouped by owner.

---

## Updating

**From the menu bar:** click **○** → *Check for updates…*. MeetingRec also checks by
itself once a day. When there's an update, that item changes to *Update available…*.
Clicking it lists what's new; click **Update** and the menu bar reloads when it's done,
with a notification like `Updated to 7f7bfed`. It never updates on its own, and it can't
update while you're recording.

**From the terminal:**
```bash
~/meetingrec/bin/meetingrec update --check   # only see what's new
~/meetingrec/bin/meetingrec update
```
Expected from `update`: the commits it downloaded, then the install steps, each one
already done or quickly finished, and:
```text
updated aae6175 → 7f7bfed:
  • Update workflow actions to their Node 24 versions
...
Update finished. Your recordings, notes, names and settings were not changed.
```
An update downloads the new code, then runs the installer's steps again to pick up
anything the new version needs, like a new audiotee or a new menu bar. Your recordings,
notes, name tables, team profiles and `~/.config/meetingrec/config.sh` are never
touched.

If you installed before updates existed (no *Check for updates…* in the menu), update
once by hand:
```bash
git -C ~/meetingrec pull && ~/meetingrec/bin/meetingrec update
```

---

## Customising

- **Team roster:** edit `teamnotes/.claude/skills/team-notes/profiles/team.md` when people
  join or leave. Every note's attendee and absent lists come from it.
- **Another recurring group** (e.g. a partner working group): pick the **other** profile and
  say yes when Claude offers to save it as a profile. Next time it appears in the list.
- **Whisper model:** `small.en` is the default. For poor audio, ask the skill to re-run
  with `medium.en`, after downloading it (1.5 GB):
  ```bash
  curl -L -o ~/.whisper-models/ggml-medium.en.bin \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin
  ```
  Expected: a progress table that ends at `100` with a size of about `1462M`.
- **New dashboard context:** to-dos are tagged with the note's `context` (default
  `work`). If you start using another context, add a `tags include <context>` block to
  `scribe/Tasks.md`.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `NO_ENGINE` | `brew install whisper.cpp`, or run the quick install command again. |
| `MODEL_NOT_FOUND` | Run the `curl` command it prints (see step 1). |
| `NO_FFMPEG` | `brew install ffmpeg` |
| `audiotee not found or not executable` | Run the quick install command again, redo manual step 3, or fix `AUDIOTEE_BIN` in `~/.config/meetingrec/config.sh`. |
| "system track produced no audio" / silent-track warning | System Audio Recording permission is missing for whatever started the recording (Terminal or Hammerspoon). See steps 5 and 6. |
| Skill says the inbox is empty | Run `ls scribe/input` from the repo folder. It should list one folder per recording, like `2026-10-01T14-00_acme-check-in`; no output means it's empty. If you set `OUTPUT_ROOT` in your config, it must point to `scribe/input`. |
| `meeting-notes` skill not found | Start `claude` from inside `scribe/` (or `teamnotes/` for team notes). |
| ○ button missing or frozen | Hammerspoon → *Reload Config*. If that fails, quit and reopen Hammerspoon. Check `~/.hammerspoon/meetingrec.log`. |
| `couldn't update, so nothing was changed` | A file in the repo was edited on your Mac and the update changes it too; git lists it. Run `claude` in the repo folder and ask it to help keep your edit, then update again. |
| Tasks dashboard is empty | Install and enable the Tasks plugin in *that* vault (setup step 7). |
| `claude: command not found` | Open a new Terminal window. If it still fails, run `export PATH="$HOME/.local/bin:$PATH"` and add that line to `~/.zprofile`. |

Each recording's measurements (track levels, timing offsets, warnings) are also appended
to `~/.local/state/meetingrec/metrics.jsonl`.

---

## License

MIT — see [LICENSE](LICENSE).
