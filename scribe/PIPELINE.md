# Meeting Notes Pipeline (this vault)

Personal meeting notes: written for the person who ran the skill. Team-facing
write-ups use `../teamnotes/` instead.

## Vault structure

```
scribe/                         (Obsidian vault root — open this folder as a vault)
├── PIPELINE.md                 # this file
├── Tasks.md                    # Tasks-plugin dashboard over every note's to-dos (yours to edit)
├── index.base                  # Obsidian Base over meeting-notes/ — created on the first run
├── input/                      # recorder inbox: meetingrec session dirs, or a dropped audio/transcript file
├── transcripts/                # archive — only used when you ask to keep a transcript
├── meeting-notes/              # output — one .md file per meeting (created on the first run)
└── .claude/
    └── skills/meeting-notes/
        ├── SKILL.md                     # full workflow spec
        ├── reference/shared.md          # names + rules shared across a fork of this repo (tracked; empty here)
        ├── reference/personal.md        # yours: the "Me" row, your names and rules (git-ignored, made on first run)
        ├── scripts/transcribe.sh        # flat audio file → .srt (whisper.cpp or openai-whisper)
        ├── scripts/transcribe_session.py# meetingrec session dir → per-track .srt + merged.txt
        └── assets/index.base            # starter Base, copied to the vault root if missing
```

## Pipeline (input → output)

1. **Set roots** — the skill and the archive are found from the skill's own location, so the
   repo can live anywhere. The vault (`NOTES_VAULT`, default this folder) and the inbox
   (`OUTPUT_ROOT`, default `input/`) come from `~/.config/meetingrec/config.sh` via
   `bin/meetingrec config get`. The first run asks where notes go and saves the answer.
2. **Load settings** — names and rules from `reference/shared.md` and your `personal.md` (created from its template on
   the first run, when it also asks your name for the `Me` row that says whose notes these are).
3. **Locate input** — newest meetingrec session directory in `input/`, else a single flat
   audio/transcript file. 0 → ask you to drop one in; >1 → ask which one.
4. **Gather context (chat, before transcribing)** — title, date (default today), type
   (open-ended; scanned from existing notes), attendees, company, context (default `work`),
   agenda. This becomes a **priming prompt** fed to Whisper to improve proper nouns.
5. **Transcribe (audio only)** — `transcribe_session.py` for a session dir, `transcribe.sh`
   for a flat file. Default model `small.en`. Engine is `whisper-cli` (whisper.cpp) if
   present, else openai-whisper. Failure exits (`NO_ENGINE`, `MODEL_NOT_FOUND`,
   `NO_FFMPEG`) are relayed verbatim — never worked around.
6. **Analyse** — Key Points, Decisions, To-Do (your commitments only, max five), Action Items
   (overflow and others' commitments you depend on), Questions to Ask. A two-track session
   tags lines `[Me]`/`[Them]`, so ownership is read off the tags rather than guessed.
7. **Write note** — `meeting-notes/<Title>.md`. Frontmatter:
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
8. **Ensure Base exists** — copy `assets/index.base` to the vault root if no Base exists yet.
9. **Clean up input** — delete only the consumed session dir or file (or move it to
   `transcripts/` if you asked to keep it). Only after the note is written.
10. **Report** — note path + one-line summary (e.g. "3 to-dos, 1 decision").

## Key architectural notes

- Transcription is a **local external dependency** (Whisper via shell) — the skill only runs
  in Claude Code on your machine, not a web sandbox.
- Obsidian-specific conventions (wikilinks-in-frontmatter, Bases, callouts, Tasks-plugin
  checkboxes) are central — output is not generic Markdown.
- The type vocabulary and the name-correction table are living and open-ended. At the end of
  each run the skill offers to add the names it had to correct, and rules suggested by your
  corrections, to `personal.md`. "From now on…" during a run saves a rule straight away.
