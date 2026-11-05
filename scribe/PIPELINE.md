# Meeting Notes Pipeline (this vault)

Personal meeting notes: written for the person who ran the skill. Team-facing
write-ups use `../teamnotes/` instead.

## Vault structure

```
scribe/                         (Obsidian vault root — open this folder as a vault)
├── PIPELINE.md                 # this file
├── Tasks.md                    # Tasks-plugin dashboard over every note's to-dos (yours to edit; git-ignored, made at install)
├── index.base                  # Obsidian Base over meeting-notes/ (yours; git-ignored, created on the first run)
├── input/                      # recorder inbox: meetingrec session dirs, or a dropped audio/transcript file
├── transcripts/                # transcripts you chose to keep at the end of a run
├── meeting-notes/              # output — one .md file per meeting (created on the first run)
├── settings/
│   ├── shared.md               # names + rules shared across a fork of this repo (tracked; empty here)
│   ├── personal.example.md     # template for personal.md (tracked; don't edit)
│   └── personal.md             # yours: the "Me" row, your names and rules (git-ignored, made on first run)
└── .claude/
    └── skills/meeting-notes/
        ├── SKILL.md                     # full workflow spec
        └── assets/                      # starters: Tasks.md and index.base, copied to the vault root if missing
```

The routine steps run through the `meetingrec` command (`../.engine/bin/meetingrec`), so they
go the same way every time: `prepare`, `session-info`, `transcribe`, `note-path` and
`clear-input`. The transcription scripts are in `../.engine/lib/`.

## Pipeline (input → output)

1. **Prepare** — `meetingrec prepare scribe` prints the folders: the vault (`NOTES_VAULT`,
   default this folder) and the inbox (`OUTPUT_ROOT`, default `input/`) from
   `~/.config/meetingrec/config.sh`, the archive and the settings folder. It also checks the
   vault, creates what a first run is missing (the notes folder, the Base, your
   `personal.md`), and lists the recordings waiting. The first run asks where notes go and
   saves the answer.
2. **Load settings** — names and rules from `settings/shared.md` and your `settings/personal.md`
   (on the first run the skill also asks your name for the `Me` row that says whose notes
   these are).
3. **Locate input** — newest meetingrec session directory in `input/`, else a single flat
   audio/transcript file. 0 → ask you to drop one in; >1 → ask which one.
4. **Gather context (chat, before transcribing)** — title, date (default today), type
   (open-ended; scanned from existing notes), attendees, company, context (default `work`),
   agenda. This becomes a **priming prompt** fed to Whisper to improve proper nouns.
5. **Transcribe (audio only)** — `meetingrec transcribe`, for a session dir or a flat file.
   Default model `small.en`. Engine is `whisper-cli` (whisper.cpp). Failure exits
   (`NO_ENGINE`, `MODEL_NOT_FOUND`, `NO_FFMPEG`) are relayed verbatim — never worked around.
6. **Analyse** — Key Points, Decisions, To-Do (your commitments only, max five), Action Items
   (overflow and others' commitments you depend on), Questions to Ask. A two-track session
   tags lines `[Me]`/`[Them]`, so ownership is read off the tags rather than guessed.
7. **Write note** — `meeting-notes/<Title>.md`, the free name `meetingrec note-path` gives
   (never over an existing note). Frontmatter:
   ```yaml
   date: 2026-06-11
   type: strategy
   context: work
   company: "[[Acme Health]]"
   attendees: ["[[Person]]"]
   tags: [meeting, strategy, work]
   ```
   Body: TL;DR callout → To-Do (checkboxes with `#work`, priority, ⏳/📅) → Action Items →
   Decisions → Questions to Ask → Key Points. Empty sections are omitted.
8. **Base** — `prepare` copied `assets/index.base` to the vault root in step 1 if no Base
   existed yet.
9. **Clean up input** — only after the note is written, ask whether to delete the transcript
   or move it to `transcripts/`, then `meetingrec clear-input`; either way the consumed
   session dir or file leaves `input/`.
10. **Report** — note path + one-line summary (e.g. "3 to-dos, 1 decision").

## Key architectural notes

- Transcription is a **local external dependency** (Whisper via shell) — the skill only runs
  in Claude Code on your machine, not a web sandbox.
- Obsidian-specific conventions (wikilinks-in-frontmatter, Bases, callouts, Tasks-plugin
  checkboxes) are central — output is not generic Markdown.
- The type vocabulary and the name-correction table are living and open-ended. At the end of
  each run the skill offers to add the names it had to correct, and rules suggested by your
  corrections, to `personal.md`. "From now on…" during a run saves a rule straight away.
