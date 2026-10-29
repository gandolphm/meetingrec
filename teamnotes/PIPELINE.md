# Team Notes Pipeline (this vault)

Independent of `../scribe/`. Same transcription engine, different skill, voice, template,
and audience. Nothing here reads from or writes to the scribe vault.

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
└── .claude/
    └── skills/team-notes/
        ├── SKILL.md                     # full workflow spec (profile-independent)
        ├── reference/shared.md          # names + rules shared across a fork of this repo (tracked; empty here)
        ├── reference/personal.md        # your names and rules for every team (git-ignored, made on first run)
        ├── profiles/team.example.md     # template for your team's profile (tracked; don't edit)
        ├── profiles/team.md             # your team: roster, extra sections, prefix, tag (git-ignored, set up on first use)
        ├── profiles/other.md            # anything else, asked at runtime
        ├── scripts/transcribe.sh        # flat audio file → .srt (whisper.cpp or openai-whisper)
        ├── scripts/transcribe_session.py# meetingrec session dir → per-track .srt + merged.txt
        ├── scripts/make_share_copy.py   # vault note → share/ copy (header from team:, unwrap wikilinks, emoji → words)
        └── assets/index.base            # starter Base, copied to vault root if missing
```

## Pipeline (input → output)

1. **Set roots** — the inbox is `input/` here, found from the skill's own location. The vault
   for `meeting-notes/`, `share/`, `Action Items.md` and the Base is `TEAM_VAULT` from
   `~/.config/meetingrec/config.sh` (default this folder). The first run asks where team notes
   go; it can never be the scribe vault.
   Then load the settings (names and rules): `shared.md` and your `personal.md` (created from its
   template on the first run).
2. **Pick a profile** — always asked via AskUserQuestion, one option per profile file plus `other`. Read it; it
   supplies team, org, roster, ownership hints, extra sections, prefix, tag, priming terms. The
   first time `team` is picked, `team.md` is created from its template and filled in by asking
   for the team's name and roster.
3. **Locate input** — newest flat audio/transcript file in `input/`, or a session directory
   moved in by hand. 0 → ask; >1 → ask which.
4. **Gather context** — date, meeting type, roll call over the profile roster (absent =
   roster minus present), guests, agenda. Priming prompt = full roster + profile terms.
5. **Transcribe (audio only)** — `transcribe.sh` for a flat file, `transcribe_session.py` for
   a session dir. Model `small.en`. Failure exits relayed verbatim, never worked around.
6. **Analyse** — TL;DR, action items for every member with owner/priority/due, the profile's
   extra sections, decisions, discussion by agenda item, next meeting. Owner precedence:
   assigned > volunteered > inferred (flagged).
7. **Confirm** — show the action-item list and every `[note: …]` flag in chat; fix before writing.
8. **Write note** — `meeting-notes/<prefix> — YYYY-MM-DD.md` per the SKILL.md template.
9. **Write share copy** — `make_share_copy.py` → `share/<same basename>.md`.
10. **Ensure Base exists** — copy `assets/index.base` to the vault root if no `*.base` is present.
11. **Clean up input** — delete only the consumed file/dir and its derived artifacts, after
    both outputs are verified.
12. **Report** — both paths, counts per person, unresolved flags, trust caveats.

## Recording

In-person meetings are recorded on a phone and the file is dropped into `input/`. A virtual
meeting recorded with `meetingrec` lands in `scribe/input/` and is moved here by hand before
running the skill.
