# Team Notes Pipeline (this vault)

Independent of `../scribe/`. Same transcription engine, different skill, voice, template,
and audience. Nothing here reads from or writes to the scribe vault; the only thing it puts
in `../scribe/` is a transcript you chose to keep, in `../scribe/transcripts/`.

## Vault structure

```
teamnotes/                      (Obsidian vault root, working dir for the skill)
├── CLAUDE.md                   # voice rules, profile index
├── PIPELINE.md                 # this file
├── index.base                  # Obsidian Base — All Meetings, By Team, By Type
├── Action Items.md             # Tasks-plugin page — every open item, grouped by owner heading
├── input/                      # drop zone: phone .m4a/.mp3, a .txt/.srt transcript, or a meetingrec session dir
├── meeting-notes/              # output — one Obsidian note per meeting, "<prefix> — YYYY-MM-DD.md" (created on the first run)
├── share/                      # output — plain-Markdown copy of each note for the team
├── settings/
│   ├── shared.md               # names + rules shared across a fork of this repo (tracked; empty here)
│   ├── personal.example.md     # template for personal.md (tracked; don't edit)
│   ├── personal.md             # your names and rules for every team (git-ignored, made on first run)
│   └── profiles/
│       ├── team.example.md     # template for your team's profile (tracked; don't edit)
│       ├── team.md             # your team: roster, extra sections, prefix, tag (git-ignored, set up on first use)
│       └── other.md            # anything else, asked at runtime
└── .claude/
    └── skills/team-notes/
        ├── SKILL.md                     # full workflow spec (profile-independent)
        └── assets/index.base            # starter Base, copied to vault root if missing
```

The routine steps run through the `meetingrec` command (`../.engine/bin/meetingrec`), so they
go the same way every time: `prepare`, `session-info`, `transcribe`, `note-path`,
`share-copy` and `clear-input`. The scripts behind them are in `../.engine/lib/`.

## Pipeline (input → output)

1. **Prepare** — `meetingrec prepare teamnotes` prints the folders: the inbox is `input/`
   here; the vault for `meeting-notes/`, `share/`, `Action Items.md` and the Base is
   `TEAM_VAULT` from `~/.config/meetingrec/config.sh` (default this folder). It checks the
   vault, creates what a first run is missing, lists the profiles and the recordings waiting,
   and prints the settings (names and rules): `settings/shared.md` and your
   `settings/personal.md`. The first run asks where team notes go; it can never be the
   scribe vault.
2. **Pick a profile** — always asked via AskUserQuestion, one option per profile file plus `other`. Read it; it
   supplies team, org, roster, ownership hints, extra sections, prefix, tag, priming terms. The
   first time `team` is picked, `team.md` is created from its template and filled in by asking
   for the team's name and roster.
3. **Locate input** — newest flat audio/transcript file in `input/`, or a session directory
   moved in by hand. 0 → ask; >1 → ask which.
4. **Gather context** — date, meeting type, roll call over the profile roster (absent =
   roster minus present), guests, agenda. Priming prompt = full roster + profile terms.
5. **Transcribe (audio only)** — `meetingrec transcribe`, for a flat file or a session dir.
   Model `small.en`. Failure exits relayed verbatim, never worked around.
6. **Analyse** — TL;DR, action items for every member with owner/priority/due, the profile's
   extra sections, decisions, discussion by agenda item, next meeting. Owner precedence:
   assigned > volunteered > inferred (flagged).
7. **Confirm** — show the action-item list and every `[note: …]` flag in chat; fix before writing.
8. **Write note** — `meeting-notes/<prefix> — YYYY-MM-DD.md` per the SKILL.md template, at
   the free name `meetingrec note-path` gives.
9. **Write share copy** — `meetingrec share-copy` → `share/<same basename>.md`.
10. **Base** — `prepare` copied `assets/index.base` to the vault root in step 1 if no
    `*.base` was present.
11. **Clean up input** — after both outputs are verified, ask whether to delete the transcript
    or move it to `../scribe/transcripts/`, then `meetingrec clear-input`; either way the
    consumed file/dir leaves `input/`.
12. **Report** — both paths, counts per person, unresolved flags, trust caveats.

## Recording

In-person meetings are recorded on a phone and the file is dropped into `input/`. A virtual
meeting recorded with `meetingrec` lands in `scribe/input/` and is moved here by hand before
running the skill.
