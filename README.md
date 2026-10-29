# meetingrec

Record a meeting on your Mac. Claude Code then turns the recording into
Obsidian notes, with to-dos, decisions and follow-ups. Transcription runs locally with
Whisper; no meeting bot joins the call.

There are three parts:

| Part | What it does | Where |
| --- | --- | --- |
| **Recorder** | Records a virtual meeting as two tracks: your mic (`mic.wav`) and everyone else (`system.wav`). Start and stop it from the menu bar or the terminal. | `bin/meetingrec`, `hammerspoon/init.lua` |
| **scribe** | Your **personal** notes: TL;DR, your to-dos, decisions and questions to ask. | `scribe/` (an Obsidian vault), or a vault you already use |
| **teamnotes** | **Team-facing** notes: third person, action items for everyone grouped by owner, and a plain-Markdown copy you can paste into Slack or email. | `teamnotes/` (a second Obsidian vault), or another vault of yours |

```
meetingrec/
├── bin/meetingrec              # the recorder
├── bin/scribe, teamnotes       # start writing notes from any Terminal window
├── bin/clock-check, drift-check  # diagnostics for track timing (rarely needed)
├── hammerspoon/init.lua        # the ○ menu-bar button
├── config.example.sh           # template for ~/.config/meetingrec/config.sh
├── docs/manual-install.md      # the install, one step at a time
├── scribe/                     # Obsidian vault #1 — personal notes
│   ├── input/                  #   recordings land here
│   ├── meeting-notes/          #   notes are written here
│   ├── transcripts/            #   only used if you ask to keep a transcript
│   ├── Tasks.md                #   to-do dashboard
│   └── .claude/skills/meeting-notes/
│       └── reference/          #   your personal.md (names, rules) lives here
└── teamnotes/                  # Obsidian vault #2 — team notes
    ├── input/  meeting-notes/  share/
    ├── Action Items.md         #   everyone's open items, by owner
    └── .claude/skills/team-notes/
        ├── reference/          #   your personal.md for team notes
        └── profiles/           #   one file per team: roster, sections, rules
```

Recordings, transcripts and notes are git-ignored, so nothing you record gets committed. So
are your settings and team rosters (see [Make it yours](#make-it-yours)).

> **Always tell people you're recording.** No bot appears in the participant list, so
> nobody knows unless you say so.

## Contents

- [Requirements](#requirements)
- [Install](#install)
  - [Quick install](#quick-install-recommended) · [Manual install](docs/manual-install.md)
  - [Set up Obsidian](#set-up-obsidian)
- [Your first meeting](#your-first-meeting)
- [Usage](#usage): [record](#record-a-virtual-meeting) ·
  [personal notes](#write-your-personal-notes-scribe) · [team notes](#write-team-notes-teamnotes)
- [Make it yours](#make-it-yours): where notes go, names, rules, teams
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)

---

## Requirements

- A Mac with **Apple silicon**, running **macOS 14.2 or later**. System-audio capture uses
  Core Audio taps, which first shipped in 14.2.
- A **Claude Code** subscription or API access.
- **Disk space:** about **0.55 GB** for the Whisper model (465 MB), ffmpeg, whisper.cpp and
  Hammerspoon. If your Mac doesn't have them yet, add about 1.3 GB for Apple's Command Line
  Tools and about 0.3 GB for Claude Code, which grows toward 0.8 GB as it keeps previous
  versions: about **2–2.5 GB** in all. Recordings take about 230 MB per hour of meeting
  until their notes are written.
- **No Homebrew, and no administrator password** for meetingrec itself (unless you
  [choose Homebrew](#quick-install-recommended)). If your Mac doesn't have Apple's Command
  Line Tools yet, macOS may ask an administrator to approve them.
- *Optional:* the **[Claude app](https://claude.ai/download)** for Mac, so *Write up notes…*
  in the menu bar opens there instead of in Terminal.

---

## Install

Paste one command and answer a few prompts: the [quick install](#quick-install-recommended)
below. About 20 minutes, mostly waiting. If you'd rather not run a script from the internet,
or want to see exactly what gets downloaded, follow the
**[manual install](docs/manual-install.md)** instead. Both end up with the same result.
Either way, finish with [Set up Obsidian](#set-up-obsidian).

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
| Xcode Command Line Tools (git and python3) | Apple, via `xcode-select --install` |
| meetingrec, cloned to `~/meetingrec` | this GitHub repo |
| Whisper `small.en` model (465 MB) | [Hugging Face](https://huggingface.co/ggerganov/whisper.cpp) |
| ffmpeg and whisper.cpp's `whisper-cli`, at pinned versions | this repo's [releases](https://github.com/gandolphm/meetingrec/releases), built by GitHub Actions ([ffmpeg](.github/workflows/build-ffmpeg.yml), [whisper-cli](.github/workflows/build-whisper.yml)) from [FFmpeg's](https://github.com/FFmpeg/FFmpeg) and [whisper.cpp's](https://github.com/ggml-org/whisper.cpp) source |
| audiotee, at the pinned commit | this repo's releases, built by a [GitHub Action](.github/workflows/build-audiotee.yml) from [audiotee's source](https://github.com/makeusabrew/audiotee) |
| Hammerspoon | [its own releases](https://github.com/Hammerspoon/hammerspoon/releases), signed by its developers |
| Claude Code | [claude.ai](https://docs.claude.com/en/docs/claude-code/overview) |

Every download is checked against the SHA-256 fingerprint pinned in
[config.example.sh](config.example.sh), and refused if it doesn't match. ffmpeg and
`whisper-cli` go in `~/.local/share/meetingrec/bin`, where only meetingrec uses them, so
they never replace other copies you might have.

It also writes `~/.config/meetingrec/config.sh` and the Hammerspoon config, starts
Hammerspoon, links the `meetingrec`, `scribe` and `teamnotes` commands into `~/.local/bin`,
and adds `~/.local/bin` to your PATH in `~/.zprofile` if it isn't there already. It doesn't change anything else. You can [read the script](install.sh) first, or
download it, look at it, then run it:
```bash
curl -fsSL https://raw.githubusercontent.com/gandolphm/meetingrec/main/install.sh -o install.sh
less install.sh      # press q to quit
bash install.sh
```

**What you'll be asked to do while it runs:**

- **Install the command line developer tools.** If a window asks, click *Install* and
  agree. The script waits until it finishes.
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

==> Xcode Command Line Tools (git, python3)
  ✓ already installed

==> meetingrec
  ✓ downloaded to /Users/you/meetingrec

==> Whisper model (small.en, 465 MB)
######################################################################## 100.0%
  ✓ downloaded and verified

==> ffmpeg and whisper.cpp
  ✓ ffmpeg downloaded (verified)
  ✓ whisper-cli downloaded (verified)

==> audiotee (system-audio capture)
  ✓ downloaded commit 56ac954 (verified) → /Users/you/bin/audiotee

==> Hammerspoon (menu-bar button)
  ✓ installed in /Applications

==> Recorder config
  ✓ created /Users/you/.config/meetingrec/config.sh

==> Your settings and team profile
  ✓ created. Claude fills them in the first time you write up a meeting

==> Claude Code
  ✓ installed

==> Commands: meetingrec, scribe, teamnotes
  ✓ meetingrec scribe teamnotes → /Users/you/.local/bin

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

Then [set up Obsidian](#set-up-obsidian).

<details>
<summary>Options</summary>

- Install somewhere other than `~/meetingrec`:
  `curl -fsSL …/install.sh | MEETINGREC_DIR=~/Documents/meetingrec bash`
- Skip the menu-bar button (you'll use `meetingrec` from Terminal):
  `curl -fsSL …/install.sh | NO_HAMMERSPOON=1 bash`
- Build audiotee on your Mac instead of downloading the prebuilt copy (takes a minute or
  two longer, and uses Swift from the Command Line Tools):
  `curl -fsSL …/install.sh | AUDIOTEE_FROM_SOURCE=1 bash`. The installer also does this by
  itself if the download fails or doesn't match its SHA-256.
- Use Homebrew's ffmpeg, whisper.cpp and Hammerspoon instead of meetingrec's pinned
  downloads: `curl -fsSL …/install.sh | USE_HOMEBREW=1 bash`. It installs Homebrew if
  needed, which asks for your Mac password, and you get whatever versions Homebrew
  currently has. The choice is remembered for updates; `USE_HOMEBREW=0` switches back.
- Already cloned the repo? Run `./install.sh` from inside it. That copy is used instead of
  a fresh clone.

</details>

---

### Set up Obsidian

1. **Install Obsidian** from [obsidian.md](https://obsidian.md). It's free. You need
   version 1.9 or later for Bases.
2. **Open the vaults.** Obsidian → *Open folder as vault* → choose `<repo>/scribe`. Do the
   same for `<repo>/teamnotes` if you'll write team notes. Each is a separate vault.
   (In the file picker, Cmd+Shift+G lets you paste the path.)

   **Already use Obsidian?** You can keep your notes in your own vault instead. The first
   time you run each skill, Claude asks where its notes should go: press Enter for the
   folder above, or give your vault's folder. Notes then go into a `meeting-notes/` folder
   inside it (and `share/` for team notes), and Claude offers to copy in the to-do page.
   Personal and team notes need separate vaults. Do steps 3 and 4 in whichever vaults you
   use. See [Make it yours](#make-it-yours) to change it later.
3. **Enable Bases** (in each vault): *Settings → Core plugins → Bases* → on. This powers
   `index.base`, a sortable table of all your meetings.
4. **Install the Tasks plugin** (in each vault): *Settings → Community plugins → Turn on
   community plugins → Browse* → search **Tasks** (by Clare Macrae and Ilyas Landikov) →
   *Install* → *Enable*. This makes the to-do checkboxes work and powers `Tasks.md` and
   `Action Items.md`.
5. *Optional:* the **Day Planner** community plugin shows to-dos on a daily timeline. The
   skill adds `⏳` scheduled dates when a meeting says when you'll do something, and Day
   Planner picks those up.

`index.base`, the table of meetings, is created in the vault automatically the first time
you write a note there.

---

## Your first meeting

1. **Before the call:** put on headphones, click **○** in the menu bar → *Start
   recording…*, type a title, click *Start*. Tell the others you're recording.
2. **After the call:** click **● 34m** → *Stop*.
3. **Write it up:** click **○** → *Write up notes…*. The Claude app opens with `scribe`
   typed in; press **Enter**. The first time, Claude asks your name and where your notes
   should go. Then it asks a few questions about the meeting (who was there, what kind of
   meeting) and transcribes it.
4. **Read it:** open the note in Obsidian. Your to-dos are on the `Tasks.md` dashboard.

Team meeting instead? Use *Write up team notes…* (see [team notes](#write-team-notes-teamnotes)).

---

## Usage

### Record a virtual meeting

**From the menu bar:** click **○** → *Start recording…*, and type a title if you like. The
button shows **● 12m** while recording. Click it → *Stop* when the call ends.

**From the terminal**, in any folder (if you did the manual install, use `<repo>/bin/meetingrec`):
```bash
meetingrec start "Acme check-in"   # title is optional
meetingrec status
meetingrec stop
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
[manual install step 5](docs/manual-install.md#5-do-a-test-recording-and-grant-permissions). If it prints a line starting
with `WARNING`, read it before the recording is gone: usually a track is silent.

**Wear headphones** if you can. On speakers your mic also picks up the other side, and
some lines get attributed to you. If you're on speakers, use *Start (mic only — on
speakers)* or `meetingrec start --mic-only`. That records just one track, and the skill
works out who said what from context.

Each recording is a folder in `scribe/input/` (or wherever `OUTPUT_ROOT` points; see
[Make it yours](#make-it-yours)), like
`2026-10-01T14-00_acme-check-in/`, containing `mic.wav`, `system.wav` and
`session.json`.

### Write your personal notes (scribe)

Any of these starts it; they all end up in the same place:

- **Menu bar:** click **○** → *Write up notes…*. The Claude app opens a Claude Code session
  in `scribe/` with `scribe` already typed. Press **Enter**. (Without the Claude app, it
  opens Claude Code in Terminal instead.)
- **Terminal, from any folder:** type `scribe`. (Manual install: see
  [step 7](docs/manual-install.md#7-add-the-commands-optional).)
- **By hand:**
  ```bash
  cd <repo>/scribe
  claude
  ```
  Expected: Claude Code opens with a `>` prompt. Then type **`scribe`**, or "write up notes
  from this meeting".

The skill:
1. finds the newest recording in `input/`;
2. asks a few quick questions (title, attendees, type), using the names to help Whisper.
   The first time, it also asks your name and where your notes should go;
3. transcribes locally with Whisper, about 90 seconds for a 30-minute call;
4. writes `meeting-notes/<Title>.md` in your notes vault and tells you the path;
5. deletes the recording. Say **"keep the transcript"** to move it to `transcripts/`
   instead;
6. offers to remember any names Whisper got wrong, and any preferences your corrections
   suggested.

Open the note in Obsidian. To-dos are tagged with the meeting's context, `#work` unless your
rules say otherwise, and appear in `Tasks.md`.

You can also drop an audio file (`.m4a`, `.mp3`, `.wav`, `.mp4`) or a transcript (`.txt`,
`.srt`, `.vtt`) into `scribe/input/`, or paste a transcript straight into the chat.

### Write team notes (teamnotes)

For a meeting whose notes go to the whole team:

1. Put the recording in `teamnotes/input/`. That can be a phone recording of an
   in-person meeting, a transcript, or a `meetingrec` session folder moved over from
   `scribe/input/`.
2. Click **○** → *Write up team notes…* and press **Enter**, or type `teamnotes` in
   Terminal. By hand: `cd <repo>/teamnotes`, run `claude`, then type **"team notes"**.
3. Pick the **team** profile (or **other**). The first time you pick **team**, Claude asks
   for your team's name and roster. Mark who was present, and confirm the action-item owners
   before anything is written.
4. You get two files:
   - `meeting-notes/<Team> — YYYY-MM-DD.md` for Obsidian.
   - `share/<Team> — YYYY-MM-DD.md`, plain Markdown to paste into Slack, email or a
     Google Doc.

`Action Items.md` shows everyone's open items, grouped by owner.

---

## Make it yours

Everything personal lives in files that **git ignores**: your colleagues', customers' and
partners' names are never committed, and updating meetingrec never overwrites them. You
rarely need to open them: most changes are a sentence to Claude while you write up a
meeting, or a click in **○ → Settings**.

```
○ → Settings
    ✓ Check for updates daily
      Personal notes: ~/meetingrec/scribe (default)   ▸  Choose folder… · Use default · Show in Finder
      Team notes: ~/meetingrec/teamnotes (default)    ▸  …
      Recordings: ~/meetingrec/scribe/input (default) ▸  …
      Edit my rules and names…
      Edit team rules and names…
      Team profiles…
```

| I want to… | Say to Claude | Or |
| --- | --- | --- |
| Keep my notes in a vault I already use | "keep my notes in ~/Documents/My Vault" | ○ → Settings → *Personal notes* → *Choose folder…* |
| Keep team notes somewhere else | "keep team notes in ~/…" | ○ → Settings → *Team notes* |
| Change how my notes are written | "from now on, keep Key Points to five bullets" | ○ → Settings → *Edit my rules and names…* |
| Give a company's meetings their own to-do tag | "from now on, Acme calls get the context `acme`" | the same, under *Rules* |
| Fix a name Whisper keeps getting wrong | accept it in the list at the end of a write-up | the same, under *Names* |
| Change my team's roster | "Sam left the team, Pat joined" | ○ → Settings → *Team profiles…* |
| Add another team or group | pick **other**, then say yes to "save as a profile" | copy a profile file in *Team profiles…* |
| Set rules for one team only | "from now on, for this team, record vote counts" | *Rules* in that team's profile |
| Record somewhere else | — | ○ → Settings → *Recordings* |
| Stop the daily update check | — | ○ → Settings → untick *Check for updates daily* |
| Use Homebrew's ffmpeg and whisper.cpp instead | — | `meetingrec config set USE_HOMEBREW on`, then `meetingrec update` |
| Use a more accurate Whisper model | "re-run with medium.en" (download it first, below) | — |

Settings saves to `~/.config/meetingrec/config.sh`. From Terminal, `meetingrec config list`
shows every setting and `meetingrec config set NOTES_VAULT ~/path` changes one (also
`TEAM_VAULT`, `OUTPUT_ROOT`, and `AUTO_UPDATE_CHECK` or `USE_HOMEBREW` with `on` or `off`). Changing a notes
folder doesn't move the notes already in the old one; ask Claude to move them.

### What Claude asks the first time

- **Your name** (personal notes), and how Whisper tends to mishear it. It's how Claude
  tells which to-dos are yours.
- **Where your notes go:** meetingrec's own `scribe/` or `teamnotes/` vault, or one you
  already use. Personal and team notes need separate vaults. Claude Code asks permission
  the first time it writes outside the meetingrec folder.
- **Your team's name and roster**, the first time you pick the **team** profile.

### Where everything is saved

| What | File |
| --- | --- |
| Where notes and recordings go | `~/.config/meetingrec/config.sh` |
| Your name, names and rules for personal notes | `scribe/.claude/skills/meeting-notes/reference/personal.md` |
| Names and rules for team notes, for every team | `teamnotes/.claude/skills/team-notes/reference/personal.md` |
| One team's name, roster, sections and rules | `teamnotes/.claude/skills/team-notes/profiles/<team>.md` |

Rules are plain English, one bullet each, and take priority over the skills' defaults. A
team's rules beat your general ones for that team. A few things can't be changed by a rule,
because other parts of meetingrec depend on them: recordings aren't deleted before the note
is saved, notes keep the format the notes table and to-do pages read, and Claude never edits
the skills' own files. At the end of each write-up Claude offers to remember the names it
corrected and any preferences your corrections suggested; you choose which to keep.

Next to your files are tracked ones that must stay as they are, because git publishes them
with the repo:

- **Templates** (`*.example.md`): the starting point the skills copy your files from.
- **`shared.md`**: empty in this repo, and it should stay that way. It's only for a team
  that [forks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo)
  meetingrec: the fork's maintainer fills it with the names and rules everyone on the team
  needs and commits them, so each member gets them on their next update. Never put anything
  in it in your own copy of this repo.

### Other settings

- **A new context on the to-do dashboard:** to-dos are tagged with the note's `context`
  (`work` unless your rules say otherwise). If you start using another, add a
  `tags include <context>` block to `Tasks.md` in your notes vault. Claude points this out
  when it happens.
- **Whisper model:** `small.en` is the default. For poor audio, download `medium.en`
  (1.5 GB), then ask the skill to re-run with it:
  ```bash
  curl -L -o ~/.whisper-models/ggml-medium.en.bin \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin
  ```
  Expected: a progress table that ends at `100` with a size of about `1462M`.

---

## Updating

**From the menu bar:** click **○** → *Check for updates…*. MeetingRec also checks by
itself once a day. When there's an update, that item changes to *Update available…*.
Clicking it lists what's new; click **Update** and the menu bar reloads when it's done,
with a notification like `Updated to 7f7bfed`. It never updates on its own, and it can't
update while you're recording. To stop the daily check, untick ○ → Settings → *Check for
updates daily*.

**From the terminal:**
```bash
meetingrec update --check   # only see what's new
meetingrec update
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
notes, settings (names and rules), team profiles and `~/.config/meetingrec/config.sh` are never
touched.

If you installed before updates existed (no *Check for updates…* in the menu), update
once by hand:
```bash
git -C ~/meetingrec pull && ~/meetingrec/bin/meetingrec update
```

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `NO_ENGINE` | whisper-cli is missing. Run `meetingrec update`, or the quick install command again. |
| `MODEL_NOT_FOUND` | Run the `curl` command it prints, or run the quick install command again. |
| `NO_FFMPEG` | ffmpeg is missing. Run `meetingrec update`, or the quick install command again. |
| `audiotee not found or not executable` | Run the quick install command again, redo [manual step 3](docs/manual-install.md#3-install-ffmpeg-whisper-cli-and-audiotee), or fix `AUDIOTEE_BIN` in `~/.config/meetingrec/config.sh`. |
| "system track produced no audio" / silent-track warning | System Audio Recording permission is missing for whatever started the recording (Terminal or Hammerspoon). See [manual steps 5 and 6](docs/manual-install.md#5-do-a-test-recording-and-grant-permissions). |
| Skill says the inbox is empty | The recording isn't where the skill looks: `scribe/input/`, or wherever `OUTPUT_ROOT` in `~/.config/meetingrec/config.sh` points. Click **○** → *Open recordings folder* to see what's there. Team notes look in `teamnotes/input/`. |
| `meeting-notes` skill not found | Claude was started in the wrong folder. Use **○** → *Write up notes…* or the `scribe` command, or start `claude` from inside `scribe/` (`teamnotes/` for team notes). |
| "Couldn't open Claude" from *Write up notes…* | Neither the Claude app nor Claude Code's link handler is installed. Install the [Claude app](https://claude.ai/download), or type `scribe` in Terminal. |
| `scribe: command not found` | Open a new Terminal window. If it still fails, see [manual step 7](docs/manual-install.md#7-add-the-commands-optional). |
| ○ button missing or frozen | Hammerspoon → *Reload Config*. If that fails, quit and reopen Hammerspoon. Check `~/.hammerspoon/meetingrec.log`. |
| `couldn't update, so nothing was changed` | A file in the repo was edited on your Mac and the update changes it too; git lists it. Run `claude` in the repo folder and ask it to help keep your edit, then update again. |
| Tasks dashboard is empty | Install and enable the Tasks plugin in *that* vault ([Set up Obsidian](#set-up-obsidian)). |
| `claude: command not found` | Open a new Terminal window. If it still fails, run `export PATH="$HOME/.local/bin:$PATH"` and add that line to `~/.zprofile`. |

Each recording's measurements (track levels, timing offsets, warnings) are also appended
to `~/.local/state/meetingrec/metrics.jsonl`.

---

## License

MIT — see [LICENSE](LICENSE).
