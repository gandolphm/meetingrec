# meetingrec

Record a meeting on your Mac, and Claude Code turns it into Markdown notes with to-dos,
decisions and follow-ups. No meeting bot joins the call.

- **Records virtual meetings** from the menu bar or Terminal, on two tracks: your mic and
  everyone else.
- **Transcribes on your Mac** with Whisper. The audio is never uploaded; the transcript goes
  to Claude to write the notes (see [What leaves your Mac](#what-leaves-your-mac)).
- **Personal notes:** TL;DR, your to-dos, decisions and questions to ask.
- **Team notes:** third person, action items for everyone grouped by owner, and a
  plain-Markdown copy you can paste into Slack or email.
- **Built for [Obsidian](https://obsidian.md)** (free, recommended), which adds linked people
  and a to-do dashboard. Any Markdown editor can open the notes.
- **Yours to customize:** ask Claude to change how your notes are written ("from now on,
  keep Key Points to five bullets"), or edit the settings files yourself.

It works with Claude Code today; support for other agents, like Codex, is planned.

Feel free to email with any [feedback](#feedback), suggestions, or questions at **goblin_outlet@icloud.com**.

*meetingrec is a vibe-coded app.*

> **Always tell people you're recording.** No bot appears in the participant list, so
> nobody knows unless you say so.

## Contents

- [Install](#install): [Requirements](#requirements) ·
  [Quick install](#quick-install-recommended) · [Manual install](.engine/docs/manual-install.md) ·
  [Set up Obsidian](#set-up-obsidian) (recommended)
- [Your first meeting](#your-first-meeting)
- [The three parts](#the-three-parts) · [What leaves your Mac](#what-leaves-your-mac)
- [Usage](#usage): [record](#record-a-virtual-meeting) ·
  [personal notes](#write-your-personal-notes-scribe) · [team notes](#write-team-notes-teamnotes)
- [Make it yours](#make-it-yours): where notes go, names, rules, teams, moving things
- [Updating](#updating) · [Uninstalling](#uninstalling)
- [More guides](#more-guides) · [Feedback](#feedback) · [Troubleshooting](#troubleshooting)

---

## Install

Paste one command and answer a few prompts: the [quick install](#quick-install-recommended)
below. It takes around 5 minutes, mostly waiting. If you'd rather not
run a script from the internet, or want to see exactly what gets downloaded, follow the
**[manual install](.engine/docs/manual-install.md)** instead. Both end up with the same result.
Either way, finish with [Set up Obsidian](#set-up-obsidian) (recommended).

### Requirements

- A Mac with **Apple silicon**, running **macOS 14.2 or later**. System-audio capture uses
  Core Audio taps, which first shipped in 14.2.
- A **Claude plan that includes Claude Code**, or Anthropic API access. Claude Code can be the
  `claude` command or the **[Claude app](https://claude.ai/download)** for Mac (its Code tab).
  If your Mac has neither, the installer asks whether to install the `claude` command. The
  `scribe` and `teamnotes` commands need the `claude` command; *Write up notes…* in the menu
  bar opens the app if you have it, and Terminal if not.
- **Disk space:** about **0.55 GB** for the Whisper model and tools, or **2–2.5 GB** if your
  Mac also needs Apple's Command Line Tools and Claude Code. Recordings take about 230 MB per
  hour of meeting until their notes are written.

You don't need Homebrew or an administrator password for meetingrec itself (unless you
choose Homebrew in the [install options](#install-options)). If your Mac doesn't have
Apple's Command Line Tools yet, macOS may ask an administrator to approve them.

### Quick install (recommended)

Open **Terminal** (press Cmd+Space, type *Terminal*, press Enter), paste this line and
press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/gandolphm/meetingrec/main/.engine/install.sh | bash
```

The script skips any step that's already done. [What the installer does](.engine/docs/install-details.md)
lists every download and how it's verified, what else it changes on your Mac, and how to read
the script before running it.

**What you'll be asked to do while it runs:**

- **Install the command line developer tools.** If a window asks, click *Install* and
  agree. The script waits until it finishes. If you close the window instead, the script
  stops; run the install command again when you're ready.
- **Where to put meetingrec.** Press Enter for `~/meetingrec`, or type another folder, such
  as `~/Projects/meetingrec`. If you type a folder that already holds other things, like
  `~/Projects`, meetingrec goes in a `meetingrec` folder inside it.
- **Where your notes go.** Press Enter for meetingrec's own `scribe` folder, which is
  already set up as an Obsidian vault, or type the folder of an Obsidian vault you already
  use. Notes go in a `meeting-notes` folder inside it. You can change this later (see
  [Moving things](#moving-things)).
- **Install Claude Code?** Only if your Mac has neither the `claude` command nor the Claude
  app. Press Enter to install it. If you type `n`, install the Claude app or Claude Code
  yourself before your first write-up.
- **Accessibility access for Hammerspoon.** You can click *Deny*. meetingrec doesn't use
  it.
- **System audio permission for Hammerspoon.** macOS never shows a prompt for this one,
  so the script shows the steps, then opens System Settings when you press Enter: under
  *System Audio Recording Only*, click **+**, choose **Hammerspoon** in Applications, and
  make sure its switch is on. Then press Enter in Terminal again.
- **A test recording.** The script tells you to click the **○** in the menu bar, start a
  recording called `test`, click **Allow** on the Microphone prompt, play a video while
  you talk for 15 seconds, then stop it. If macOS asks whether Hammerspoon may send
  notifications, click **Allow**: that's how the menu bar tells you a recording started or an
  update finished. Warnings mid-call, like a track that isn't recording, arrive as
  **Script Editor** notifications instead; macOS shows those without asking, so just leave
  them on. Then press Enter in Terminal and the script checks that both tracks captured
  audio.

Each line starting with ✓ is a finished step. **If a step fails**, the script stops with a red **✗** and a message that says what went
wrong. Fix that, then paste the same command again. Steps that already finished are
skipped.

**If the test says a track is silent**, a permission is missing. Open **System Settings →
Privacy & Security** and:
- **Microphone** → turn on Hammerspoon.
- **Screen & System Audio Recording** → in the *System Audio Recording Only* list, add and
  turn on Hammerspoon.

Quit Hammerspoon (click its icon in the menu bar → *Quit Hammerspoon*, or run
`killall Hammerspoon` in Terminal if you've hidden its icon), then run the install command
again to repeat the test.

*Optional:* [hide Hammerspoon's own menu-bar icon](.engine/docs/install-details.md#hide-hammerspoons-own-icon).

**Then sign in to Claude Code.** Open a **new** Terminal window, so it picks up the new
PATH, and run:
```bash
claude
```
Expected: Claude Code starts and asks you to choose a theme, then to log in. Follow the
prompts. When you reach the `>` prompt, type `/exit`. If you use only the Claude app,
open it and sign in there instead.

Then [set up Obsidian](#set-up-obsidian) (recommended).

<a name="install-options"></a>
<details>
<summary>Install options: choose the folder, skip the menu bar, use Homebrew</summary>

- Choose the folder without being asked (for example in a script):
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
  Homebrew's ffmpeg lacks meetingrec's [microphone fix](.engine/docs/install-details.md#the-one-change-to-ffmpeg),
  so a microphone running at 44.1 or 48 kHz, such as the MacBook's own, loses about a tenth
  of its audio with it.
- Already cloned the repo? Run `.engine/install.sh` from inside it. That copy is used instead of
  a fresh clone.

</details>

---

### Set up Obsidian

Recommended, but optional. Obsidian is a free notes app that works directly on the Markdown
files: it turns names into linked pages, shows the TL;DR as a highlighted box, and
gathers your to-dos on one page. You can open the notes in any Markdown or text
editor instead. You'll see links as `[[Name]]` and to-dos as plain checkboxes with dates,
and the to-do dashboard and the table of meetings won't work. To skip Obsidian, go
straight to [Your first meeting](#your-first-meeting).

1. **Install Obsidian** from [obsidian.md](https://obsidian.md). It's free. You need
   version 1.9 or later for Bases.
2. **Open the vaults.** Obsidian → *Open folder as vault* → choose `~/meetingrec/scribe` (or
   `scribe` wherever you installed meetingrec). Do the same for `~/meetingrec/teamnotes` if
   you'll write team notes. Each is a separate vault.
   (In the file picker, Cmd+Shift+G lets you paste the path.)

   **Already use Obsidian?** You can keep your notes in your own vault instead (see
   [What Claude asks the first time](#what-claude-asks-the-first-time)), and Claude offers to
   copy in the to-do page. Do steps 3 and 4 in whichever vaults you use.
3. **Enable Bases** (in each vault): *Settings → Core plugins → Bases* → on. This powers
   `index.base`, a sortable table of all your meetings.
4. **Install the Tasks plugin** (in each vault): *Settings → Community plugins → Turn on
   community plugins → Browse* → search **Tasks** (by Clare Macrae and Ilyas Landikov) →
   *Install* → *Enable*. This makes the to-do checkboxes work and powers `Tasks.md` and
   `Action Items.md`.
5. *Optional:* the **Day Planner** community plugin shows to-dos on a daily timeline. The
   skill adds `⏳` scheduled dates when a meeting says when you'll do something, and Day
   Planner picks those up.

`index.base`, the table of meetings, is already in meetingrec's own `teamnotes` folder. In
`scribe`, or a vault of your own, it's created the first time you write a note there.

---

## Your first meeting

1. **Before the call:** put on headphones, click **○** in the menu bar → *Start
   recording…*, type a title, click *Start*. Tell the others you're recording.
2. **After the call:** click **● 34m** → *Stop*.
3. **Write it up:** click **○** → *Write up notes…*. The Claude app opens with `scribe`
   typed in (or Claude Code opens in Terminal, if you don't have the app or chose Terminal in
   **○ → Settings → *Write up notes in***); press **Enter**.
   The first time, Claude asks [a few setup questions](#what-claude-asks-the-first-time). Then
   it asks about the meeting (who was there, what kind of meeting) and transcribes it.
4. **Read it:** Claude tells you where the note is. Open it in Obsidian, where your to-dos
   also show up on the `Tasks.md` dashboard, or in any Markdown editor.

Team meeting instead? See [team notes](#write-team-notes-teamnotes).

---

## The three parts


| Part | What it does | Where |
| --- | --- | --- |
| **Recorder** | Records a virtual meeting as two tracks: your mic (`mic.wav`) and everyone else (`system.wav`). Start and stop it from the menu bar or the terminal. | `.engine/bin/meetingrec`, `.engine/hammerspoon/init.lua` |
| **scribe** | Your **personal** notes: TL;DR, your to-dos, decisions and questions to ask. | `scribe/` (a folder you can open as an Obsidian vault), or a folder you already use |
| **teamnotes** | **Team-facing** notes: third person, action items for everyone grouped by owner, and a plain-Markdown copy you can paste into Slack or email. | `teamnotes/` (a second folder and vault), or another folder of yours |

```
meetingrec/
├── .engine/                    # the machinery, hidden in Finder; you never need to open it
│   ├── bin/meetingrec          #   the recorder, plus updates, settings and the skills' routine steps
│   ├── bin/scribe, teamnotes   #   start writing notes from any Terminal window
│   ├── bin/clock-check, drift-check  # diagnostics for track timing (rarely needed)
│   ├── hammerspoon/init.lua    #   the ○ menu-bar button
│   ├── install.sh              #   the installer, also run by updates
│   ├── config.example.sh       #   template for ~/.config/meetingrec/config.sh
│   ├── docs/                   #   the manual install and other guides
│   ├── lib/                    #   transcription and share-copy scripts the commands run
│   ├── tests/                  #   the automated checks
│   └── tools/                  #   build scripts for the prebuilt downloads
├── scribe/                     # notes folder #1 (an Obsidian vault) — personal notes
│   ├── input/                  #   recordings land here
│   ├── meeting-notes/          #   notes are written here, unless you pick your own vault (made on first write-up)
│   ├── transcripts/            #   transcripts you chose to keep, personal and team
│   ├── Tasks.md                #   to-do dashboard (yours to edit; made at install)
│   ├── settings/               #   your personal.md (names, rules) lives here
│   └── .claude/skills/meeting-notes/  # the instructions Claude follows
└── teamnotes/                  # notes folder #2 (an Obsidian vault) — team notes
    ├── input/  meeting-notes/  share/
    ├── Action Items.md         #   everyone's open items, by owner (yours to edit)
    ├── settings/               #   your personal.md for team notes, and
    │   └── profiles/           #   one file per team: roster, sections, rules
    └── .claude/skills/team-notes/
```

Recordings, transcripts and notes are git-ignored, so nothing you record gets committed. So
are your settings and team rosters (see [Make it yours](#make-it-yours)), and the dashboards
and notes tables: change them as you like, and updates leave them alone.

---

## What leaves your Mac

Recording and transcription happen on your Mac. The audio files are never uploaded.

Writing the notes happens in Claude Code, so these go to Anthropic:
- the transcript;
- your answers to the skill's questions (title, attendees, meeting type);
- your names and rules files, and the team profile for team notes;
- anything else Claude Code reads while it works, such as files in your notes vault.

How Anthropic stores and uses that depends on your Claude plan and settings: see
[Anthropic's privacy policy](https://www.anthropic.com/legal/privacy). If a meeting
shouldn't leave your Mac, record it but don't write it up with Claude.

meetingrec also goes online to install and update itself: GitHub for its own files and
tools, and Hugging Face for the Whisper model. It checks GitHub for updates once a day
unless you turn that off. These connections only download; nothing you record is sent.

---

## Usage

### Record a virtual meeting

**From the menu bar:** click **○** → *Start recording…*, and type a title if you like. The
button shows **● 12m** while recording. Click it → *Stop* when the call ends.

**From the terminal**, in any folder (if you did the manual install without step 7, use `~/meetingrec/.engine/bin/meetingrec`):
```bash
meetingrec start "Acme check-in"   # title is optional
meetingrec status
meetingrec stop
```
If `stop` prints a line starting with `WARNING`, read it before the recording is gone: usually
a track is silent.

**Wear headphones** if you can. On speakers your mic also picks up the other side, and
some lines get attributed to you. If you're on speakers, use *Start (mic only — on
speakers)* or `meetingrec start --mic-only`. That records just one track, and the skill
works out who said what from context.

Each recording is a folder in `scribe/input/` (or wherever `OUTPUT_ROOT` points; see
[Make it yours](#make-it-yours)), like
`2026-10-01T14-00_acme-check-in/`, containing `mic.wav`, `system.wav` and
`session.json`.

### Write your personal notes (scribe)

Click **○** → *Write up notes…* and press **Enter**, or type `scribe` in Terminal from any
folder (manual install: see [step 7](.engine/docs/manual-install.md#7-add-the-commands-optional)).
By hand: `cd ~/meetingrec/scribe`, run `claude`, then type **`scribe`** or "write up notes from
this meeting".

The skill:
1. finds the newest recording in `input/`;
2. asks a few quick questions (title, attendees, type), using the names to help Whisper;
3. transcribes locally with Whisper, about 90 seconds for a 30-minute call;
4. sends the transcript to Claude, which writes `meeting-notes/<Title>.md` in your notes
   vault and tells you the path (see [What leaves your Mac](#what-leaves-your-mac));
5. asks whether to delete the transcript or move it to `~/meetingrec/scribe/transcripts/`,
   then clears the recording out of `input/`. The audio is deleted either way, unless you
   say "keep the recording". Say "always keep transcripts" (or "always delete them") and it
   stops asking;
6. offers to remember any names Whisper got wrong, and any preferences your corrections
   suggested.

Open the note in Obsidian or any Markdown editor. To-dos are tagged with the meeting's
context, `#work` unless your rules say otherwise. In Obsidian they also appear in `Tasks.md`.

You can also drop an audio file (`.m4a`, `.mp3`, `.wav`, `.mp4`, `.aac`, `.caf`) or a
transcript (`.txt`, `.srt`, `.vtt`, `.md`) into `scribe/input/`, or paste a transcript straight into the chat.

### Write team notes (teamnotes)

For a meeting whose notes go to the whole team:

1. Put the recording in `teamnotes/input/`. **meetingrec saves recordings to
   `scribe/input/` (unless you changed where recordings go), so a recorded call has to be
   moved over first:** in Finder, open
   `scribe/input/` in your meetingrec folder (`~/meetingrec` unless you moved it) and drag
   the recording's whole folder, like `2026-10-01T14-00_standup/`, into `teamnotes/input/`.
   Move the folder, not just the `.wav` files inside it. Phone recordings of in-person
   meetings and transcripts can go straight into `teamnotes/input/`.
2. Click **○** → *Write up team notes…* and press **Enter**, or type `teamnotes` in
   Terminal. By hand: `cd ~/meetingrec/teamnotes`, run `claude`, then type **"team notes"**.
3. Pick the **team** profile (or **other**). The first time you pick **team**, Claude asks
   for your team's name and roster. Mark who was present, and confirm the action-item owners
   before anything is written.
4. You get two files:
   - `meeting-notes/<Team> — YYYY-MM-DD.md`, the full note, with links for Obsidian.
   - `share/<Team> — YYYY-MM-DD.md`, plain Markdown to paste into Slack, email or a
     Google Doc.
5. Choose whether to delete the transcript or move it to `scribe/transcripts/`, the same
   question and folder as for personal notes.

`Action Items.md` shows everyone's open items, grouped by owner.

---

## Make it yours

Everything personal lives in files that **git ignores**: your colleagues', customers' and
partners' names are never committed, and updating meetingrec never overwrites them. You
rarely need to open them: most changes are a sentence to Claude while you write up a
meeting, or a click in **○ → Settings**.

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
| Move the meetingrec folder itself | — | `meetingrec move ~/Projects` (see [Moving things](#moving-things)) |
| Remove meetingrec from this Mac | — | ○ → Settings → *Uninstall meetingrec…* (see [Uninstalling](#uninstalling)) |
| Stop the daily update check | — | ○ → Settings → untick *Check for updates daily* |
| Write up notes in Terminal instead of the Claude app | — | ○ → Settings → *Write up notes in* → *Terminal* |
| Use Homebrew's ffmpeg and whisper.cpp instead | — | `meetingrec config set USE_HOMEBREW on`, then `meetingrec update` |
| Use a more accurate Whisper model | "re-run with medium.en" ([download it first](.engine/docs/settings.md#whisper-model)) | — |

You don't need a meeting to change these. Open Claude in the notes folder
(`cd ~/meetingrec/scribe`, or `teamnotes` for team notes, then `claude`) and ask it to
show, change or remove your names, rules or team profiles: "what rules do I have?", "delete the rule about Key
Points", "Pat is now the team lead". The files it edits are listed under
[Where everything is saved](.engine/docs/settings.md#where-everything-is-saved). Don't use the `scribe` command for
this: it starts a write-up.

Settings saves to `~/.config/meetingrec/config.sh`. From Terminal, `meetingrec config list`
shows every setting and `meetingrec config set NOTES_VAULT ~/path` changes one (also
`TEAM_VAULT`, `OUTPUT_ROOT`, `AUTO_UPDATE_CHECK` or `USE_HOMEBREW` with `on` or `off`, and `WRITEUP_IN` with `app` or `terminal`). Changing a notes
folder doesn't move the notes already in the old one; ask Claude to move them.

Pick the vault itself, not its `meeting-notes` folder: notes go in a `meeting-notes` folder
inside whatever you pick, and meetingrec offers the vault instead if you pick a folder inside
one. A vault that already has a `meeting-notes` folder is fine: new notes go in beside your
own, and nothing is ever overwritten. A note whose name is taken (a weekly meeting, say)
gets the date added, like `Acme check-in (2026-10-30).md`. Team notes already have the date
in their name, so they get a number instead.

### What Claude asks the first time

- **Your name** (personal notes), and how Whisper tends to mishear it. It's how Claude
  tells which to-dos are yours.
- **Where your notes go:** meetingrec's own `scribe/` or `teamnotes/` vault, or one you
  already use. The installer asks this for personal notes, so Claude only asks if you
  skipped it; team notes are asked the first time you write them. Personal and team notes
  need separate vaults. Claude Code asks permission
  the first time it writes outside the meetingrec folder.
- **Your team's name and roster**, the first time you pick the **team** profile.

For where each setting is saved, how rules work, and the Whisper model, see
[Settings in detail](.engine/docs/settings.md).

### Moving things

Change where notes and recordings go in **○ → Settings**. To move the meetingrec folder
itself, use `meetingrec move`, not Finder:
```bash
meetingrec move ~/Projects             # ends up in ~/Projects/meetingrec
```
[Moving meetingrec](.engine/docs/moving.md) covers what it updates, what it can't, and what to do if you
already moved the folder in Finder.

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
An update downloads the new code, then runs the installer's steps again to pick up
anything the new version needs, like a new audiotee or a new menu bar. Your recordings,
notes, settings (names and rules), team profiles and `~/.config/meetingrec/config.sh` are never
touched.

As a safety net, an update first copies your own files in the meetingrec folder (settings,
team profiles, notes and kept transcripts, but not recordings) to a backup, then checks them
once the new code is in. If none changed, which is what should always happen, the backup is
deleted straight away, so nothing builds up. If an update did change or remove one, it says
which, and the backup stays in `~/.local/share/meetingrec/backups/`: open it in Finder (it
unpacks into a folder) and copy the file back.

---

## Uninstalling

Don't delete the meetingrec folder to start over: unless you chose folders of your own,
your notes, recordings, kept transcripts and settings are inside it. To repair an install,
run the [install command](#quick-install-recommended) again. It keeps everything you have.

To remove meetingrec, click **○** → *Settings* → *Uninstall meetingrec…*, or run
`meetingrec uninstall` (add `--dry-run` to only list what would go). Keeping your notes is
always the default. [Uninstalling meetingrec](.engine/docs/uninstalling.md) covers exactly what it
removes and what it leaves.

---

## More guides

- [Manual install](.engine/docs/manual-install.md): the install, one step at a time
- [What the installer does](.engine/docs/install-details.md): downloads, verification, changes to your Mac
- [Settings in detail](.engine/docs/settings.md): where everything is saved, how rules work, the Whisper model
- [Moving meetingrec](.engine/docs/moving.md): new notes folders, or the meetingrec folder itself
- [Uninstalling meetingrec](.engine/docs/uninstalling.md): what it removes and what it leaves

---

## Feedback

Something broken, confusing, or missing? Email meetingrec's feedback address,
**goblin_outlet.3x@icloud.com**, or [open an issue](https://github.com/gandolphm/meetingrec/issues)
if you use GitHub. Say which macOS version you're on, and whether you were on headphones or
speakers.

Issues are public, so never paste a transcript, note text, or anyone's name into one.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `NO_ENGINE` | whisper-cli is missing. Run `meetingrec update`, or the quick install command again. |
| `MODEL_NOT_FOUND` | Run the `curl` command it prints, or run the quick install command again. |
| `NO_FFMPEG` | ffmpeg is missing. Run `meetingrec update`, or the quick install command again. |
| `audiotee not found or not executable` | Run the quick install command again, redo [manual step 3](.engine/docs/manual-install.md#3-install-ffmpeg-whisper-cli-and-audiotee), or fix `AUDIOTEE_BIN` in `~/.config/meetingrec/config.sh`. |
| "system track produced no audio" / silent-track warning | System Audio Recording permission is missing for whatever started the recording (Terminal or Hammerspoon). See [manual steps 5 and 6](.engine/docs/manual-install.md#5-do-a-test-recording-and-grant-permissions). |
| Skill says the inbox is empty | The recording isn't where the skill looks: `scribe/input/`, or wherever `OUTPUT_ROOT` in `~/.config/meetingrec/config.sh` points. Click **○** → *Open recordings folder* to see what's there. Team notes look in `teamnotes/input/`. |
| No notifications from the menu bar (starting, stopping, updates) | Turn on **System Settings → Notifications → Hammerspoon → Allow notifications**. |
| No warning when a track stops recording mid-call | Those warnings come from the recorder script, so macOS lists them as **Script Editor**. Turn on **System Settings → Notifications → Script Editor → Allow notifications**. It only appears there after the first one. |
| `your recordings folder … is missing` when starting | The recordings folder you chose was moved, renamed, or is on a drive that isn't connected, and meetingrec won't record into a new folder in its place. Reconnect the drive, or choose the folder again in **○ → Settings → Recordings**. |
| `meeting-notes` skill not found | Claude was started in the wrong folder. Use **○** → *Write up notes…* or the `scribe` command, or start `claude` from inside `scribe/` (`teamnotes/` for team notes). |
| "Couldn't open Claude" from *Write up notes…* | Neither the Claude app nor Claude Code's link handler is installed. Install the [Claude app](https://claude.ai/download), or type `scribe` in Terminal. |
| `scribe: command not found` | Open a new Terminal window. If it still fails, see [manual step 7](.engine/docs/manual-install.md#7-add-the-commands-optional). |
| ○ button missing or frozen | ○ → *Reload config*, or the Hammerspoon icon → *Reload Config*. If that fails, run `killall Hammerspoon` and open Hammerspoon from Applications again. Check `~/.hammerspoon/meetingrec.log`. |
| `couldn't update, so nothing was changed` | A file in the repo was edited on your Mac and the update changes it too; git lists it. Run `claude` in the repo folder and ask it to help keep your edit, then update again. |
| Tasks dashboard is empty | Install and enable the Tasks plugin in *that* vault ([Set up Obsidian](#set-up-obsidian)). |
| `claude: command not found` | Open a new Terminal window. If it still fails, run `export PATH="$HOME/.local/bin:$PATH"` and add that line to `~/.zprofile`. |

Each recording's measurements (track levels, timing offsets, warnings) are also appended
to `~/.local/state/meetingrec/metrics.jsonl`.

---

## License

MIT — see [LICENSE](LICENSE).
