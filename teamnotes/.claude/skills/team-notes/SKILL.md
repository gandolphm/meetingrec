---
name: team-notes
description: >-
  Write up a team-facing meeting from a recording or transcript into an Obsidian note plus
  a plain-Markdown share copy for everyone on the team: third person, action items for
  every member grouped by owner, decisions, discussion, next meeting, plus the sections that
  team needs (pipeline and accounts, upcoming events). Each team is a profile: `team` for
  the user's own team, `other` for anything else. Use this skill whenever the user says
  "team notes", "team meeting", "team sync", "write up the meeting for
  the team", "notes for everyone", or points to a recording or transcript in the teamnotes
  vault. When no file is given, the skill scans teamnotes/input/ for a phone recording, a
  transcript, or a meetingrec session directory. NOT for the user's own personal notes on a
  call or 1:1 — those use the separate meeting-notes skill in ../scribe/.
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# Team Notes (Obsidian)

Turns a team meeting recording or transcript into two files: an Obsidian note in the
`teamnotes` vault, and a plain-Markdown copy of the same note that can be pasted into an
email, Slack, or a Google Doc for the whole team.

Which team is a **profile** — a file under `${CLAUDE_SKILL_DIR}/profiles/` that supplies
everything team-specific: wikilinks for team and org, roster with roles, ownership hints,
extra template sections, filename prefix, tag, and Whisper priming terms. The workflow
below never hardcodes any of that.

This is **not** the scribe skill. The differences that matter:

| | scribe `meeting-notes` | this skill |
|---|---|---|
| Audience | the user only | the whole team, including absent members |
| Voice | first-person shorthand | third person, no "I" |
| Action items | the user's only | everyone's, grouped by owner |
| Coverage | skip minor topics | every agenda item discussed |
| Output | one vault note | vault note + `share/` copy |
| Vault | `scribe/` | `teamnotes/` — never touch `../scribe/` |

"The user" means whoever is running the skill.

**Key architectural fact:** transcription is an *external dependency*. The skill shells out to
a local Whisper binary, so it must run in Claude Code on the user's machine, not the web
sandbox.

Read the vault's `CLAUDE.md` before writing anything: voice rules and the shared Whisper
name-correction table live there.

---

## Workflow

### Step 0 — Locate the vault root

**First, `cd` to the vault root.** Every path in this skill is relative to it, and the shell
does *not* necessarily start there — Claude Code's working directory is usually the
repository root, one level above the vault.

The vault root is the directory containing both `input/` and `share/`. `share/` is the
discriminator: `../scribe/` also has an `input/`, so a check on `input/` alone would land in
the wrong tree and transcribe one of the user's personal recordings.

```bash
for d in . teamnotes .. ../teamnotes; do
  [ -d "$d/input" ] && [ -d "$d/share" ] && cd "$d" && break
done
pwd   # must end in /teamnotes — confirm before continuing
```

If `pwd` does not end in `teamnotes`, stop and ask the user where the vault is. Never fall
back to `../scribe/`, never read its `input/`, and never write into it.

### Step 0.25 — Pick the profile

```bash
ls "${CLAUDE_SKILL_DIR}/profiles/"
```

**Always ask which profile to use** — never infer it silently from the user's wording or
from the input filename. Use `AskUserQuestion` with one option per profile file (label =
the team name from the profile's header, description = its org), plus `other`. If the
user's words point at a profile ("Acme team notes"), put that one first and mark it
"(Recommended)", but still ask: a wrong profile puts the wrong roster in the roll call, the
wrong sections in the note, and the wrong name on the share copy, and none of that is
visible until the note is already written.

Ask this **before** scanning `input/` and before any other question, so the roll call in
Step 0.75 can be built from the right roster.

Then **read the chosen profile file in full** — it is the source for the roster, the extra
sections, the filename prefix, the tag, and the priming terms used in every later step.

For `other`, the profile tells you what to ask the user for instead (team name, org,
attendees). If that team is likely to recur, offer at the end to save a new profile file so
the next run doesn't have to ask.

### Step 0.5 — Locate the input

Unless the user already named a file or pasted a transcript in chat, scan `input/`. There
are two shapes:

**Flat files** are the usual case for in-person meetings recorded on a phone. Expect a `.m4a`/`.mp3`/`.wav`, or a `.txt`/`.srt`/`.vtt` exported by a phone
transcription app:

```bash
ls -t input/ 2>/dev/null | grep -iE '\.(m4a|mp3|wav|mp4|txt|srt|vtt|md)$'
```

**Session directories** appear only when the user has moved one in by hand from a
meetingrec recording of a virtual meeting — one directory named `<ISO-datetime>_<slug>/`
containing `mic.wav`, usually `system.wav`, and `session.json`:

```bash
find input -mindepth 1 -maxdepth 1 -type d 2>/dev/null
```

(`find`, not `ls input/*/` — under zsh a non-matching glob aborts the whole command.)

Then:

- **Exactly one candidate** (file or directory) → use it and continue.
- **Several** → list them back to the user and ask which one. A second file may be an
  unrelated recording — possibly for a different profile — waiting for its own run.
- **None** → say `input/` is empty and ask the user to drop a recording or transcript in, or
  paste one. Don't fabricate a transcript or wait passively.

### Step 0.75 — Gather context (one round of questions)

If the input is a session directory, read `session.json` first and use it to **pre-fill**
the answers — but still ask. Also run the recording health check:

```bash
cat "input/<session-dir>/session.json"
python3 - "input/<session-dir>/session.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in (d.get("checks") or {}).items():
    if isinstance(v, dict):
        print(f"{k}: peak {v.get('peak_dbfs')} dBFS, {v.get('audio_seconds')}s")
for w in d.get("warnings") or []:
    print("WARNING:", w)
EOF
```

`peak_dbfs` below −60 or `null` means that track is digital silence — it recorded nothing.
Tell the user before transcribing. If the *other* track is fine, carry on with it alone and
say what was lost. Relay any `warnings` verbatim.

Then ask, in **one compact round** (`AskUserQuestion`; roll call as a multi-select over the
profile's roster):

- **Date** of the meeting (default: today, or the date in the file name).
- **Meeting type** — the profile lists its usual types; also scan existing notes for this
  team and offer a way to type a new one:
  ```bash
  grep -l '^team: "\[\[<Team>\]\]"' meeting-notes/*.md 2>/dev/null \
    | xargs grep -h '^type:' 2>/dev/null | sed 's/^type: *//' | sort -u
  ```
- **Roll call** — which roster members were present. Everyone not selected goes under
  `absent:`. Ask separately for **guests** (anyone not on the roster) with their org if known.
- **Agenda or context** worth knowing — what was on the docket, anything being followed up
  from the previous meeting.

If the user already gave some of this in chat, fill only the gaps.

**The Whisper priming prompt is always the full roster plus the profile's priming terms**,
whether or not everyone attended: absent members get mentioned by name, and the prompt is
where Whisper learns the spelling. Add guest names and any org/event names from the agenda.

### Step 1 — Transcribe (only if the input is audio)

If the input is already a transcript (`.txt`/`.srt`/`.vtt`/`.md` or pasted text), skip to
Step 2.

**Flat audio file** (the phone case) → the bundled script. It auto-selects whisper.cpp
(Metal-accelerated) if `whisper-cli` is on PATH, else falls back to openai-whisper:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/transcribe.sh" \
  "input/<file>" "input" "small.en" "<priming prompt>"
```

- Default model is `small.en`; noticeably more accurate than `base.en` on meeting audio and
  still ~20x realtime on Apple silicon, so an hour-long meeting transcribes in about three
  minutes. Only drop to `base.en` if the user explicitly wants speed.
- The script prints `OK <path-to-.srt>` on success.
- Relay the documented failure exits and stop — do not work around a missing engine:
  - `NO_ENGINE` → `brew install whisper.cpp` (or `pip install openai-whisper`)
  - `MODEL_NOT_FOUND` → relay the exact `curl` command the script prints
  - `NO_FFMPEG` → `brew install ffmpeg`

A phone recording of a room is a **single, untagged track**. Nothing in it says who is
speaking; ownership in Step 2 is inferred from context (people addressing each other by
name, whoever runs the meeting assigning items, someone volunteering). Say so in the report.

**Session directory** → use `transcribe_session.py`, never `transcribe.sh` on each track:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/transcribe_session.py" "input/<session-dir>" \
  --model small.en --prompt "<priming prompt>"
```

It writes `mic.srt`, `system.srt` and — for two-track sessions — `merged.txt`, tagged
`[Me]`/`[Them]`. Two lines in its summary need acting on:

- `NO SPEECH DETECTED` — that track captured nothing; cross-check `peak_dbfs` above.
- `track alignment: UNKNOWN` — tracks were merged as if they started together, so ordering
  *across* speakers is approximate. Say so in the report.

(It strips silence before Whisper sees it, which is what stops Whisper hallucinating
repeated sentences into a quiet track and drifting its timestamps — both measured problems.
Running `transcribe.sh` per track reintroduces them.)

In a team meeting the tags mean less than they do in scribe: `[Me]` is the user, but
`[Them]` is **every other member mixed together**. The user's items can be read off the
tags; everyone else's are still inferred from context.

### Step 2 — Analyse the transcript

Apply the name corrections from `CLAUDE.md` first, then extract:

- **TL;DR** — 3–6 one-line bullets: what was decided, what was planned, what's next.
- **Action items for every member.** For each: owner, the task, a priority tier, and any
  stated deadline. Resolve relative dates ("next Wednesday", "before the demo") against the
  meeting date now, while the context is in front of you.
- **The profile's extra sections** — exactly the ones the profile lists, capturing the
  fields it specifies (e.g. for `team`, pipeline and accounts: account, stage, next step,
  owner).
- **Decisions** — agreements reached by consensus without a formal vote.
- **Discussion** — grouped by agenda item, in the order they came up. Fuller than personal
  notes: an absent member should be able to follow what was said and why. Still bullets,
  still scannable, no transcript-style narration.
- **Next meeting** — date/time if set, and items explicitly carried forward.

**Owner attribution**, in order of precedence:

1. Explicitly assigned by whoever is running the meeting ("Jan, can you…").
2. Self-volunteered ("I'll take that").
3. Inferred from role or context, using the profile's ownership hints or whoever raised the
   topic. **Always** mark these `[note: owner inferred]`.

If nobody can reasonably be assigned, put the item under a `### Needs an owner` heading with
`[note: owner unclear]`. Never silently assign a task to the user just because they recorded
or led the meeting.

Flag other ambiguity inline the same way: `[note: amount unclear — $1,200 or $1,800]`,
`[note: name uncertain from audio]`.

### Step 2.5 — Confirm before writing

The note goes to the whole team, so an action item attributed to the wrong person is worse
than a missing one. Before writing, show the user in chat:

1. The action-item list as `owner → task → due`, with inferred owners marked.
2. Every `[note: …]` flag you intend to write.

Ask for corrections in one round. Apply them, drop the flags that were resolved, and only
then write. If the user says to skip this step, keep the flags in the note; the share-copy
script will list them again.

### Step 3 — Write the Obsidian note

Write one file to `meeting-notes/<filename prefix> — YYYY-MM-DD.md`, prefix from the
profile (e.g. `Acme Team — 2026-09-10.md`). The date **is** in the filename here: every meeting of a team has the same title, so the date
is what makes filenames unique. `date:` in the frontmatter is still the sort key.

Follow the frontmatter conventions and the template at the end of this file exactly,
inserting the profile's extra sections where the template marks them.

### Step 3.5 — Write the share copy

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/make_share_copy.py" "meeting-notes/<file>.md"
```

It writes `share/<same basename>.md` with the frontmatter turned into a header block (team
and org from `team:`/`org:`, then Present / Absent / Guests), wikilinks unwrapped, the
callout flattened, and the Tasks emoji turned into words. Everything else is left
byte-for-byte alone, so the two files never disagree. Exit code 2 means it wrote the copy
but found `[note: …]` flags still in it — relay the list so they are fixed before the note is
sent. Read the share copy once to confirm it reads cleanly as plain text.

### Step 4 — Ensure the Base exists

**Use `find`, not a glob** — a `*.base` pattern that matches nothing makes zsh abort the
whole command, and the failure is indistinguishable from "no Base exists":

```bash
find . -name '*.base' -not -path './.claude/*' -not -path './.obsidian/*' -not -path './.trash/*'
```

The `-not -path './.claude/*'` matters: the starter Base ships inside this skill's own
`assets/`, so an unpruned `find` always reports a hit.

**If a Base already exists, leave it alone.** If none exists:

```bash
cp -n "${CLAUDE_SKILL_DIR}/assets/index.base" ./index.base
grep -n 'inFolder' ./index.base   # must read file.inFolder("meeting-notes")
```

### Step 5 — Clean up the used input

**Only after both files are written and read back**, delete just the input you used plus
its own intermediate artifacts. Leave any *other* entry in `input/` alone.

For a session directory, the whole directory is the artifact:

```bash
rm -rf "input/<session-dir>"
```

For a flat file, the source plus anything derived from the same basename:

```bash
rm -f "input/<used-file>" "input/<used-basename>".srt "input/<used-basename>".16k.wav
```

Never run either before the note is on disk, and never wipe the whole folder.

**Verify before deleting.** The note becomes the only record of the meeting — there is no
second pass. Spot-check every amount, tally, and owner against the transcript first. When
in doubt, leave the input in place and say so; a stale file in `input/` costs nothing.

### Step 6 — Report back

Give both paths and a one-line summary, e.g. "6 action items across 4 people, 3 accounts
discussed, 2 decisions". Don't paste the note into chat.

Add a line only when something affects how much to trust the note:

- **Untagged transcript** (phone recording, dropped transcript, or `--mic-only` session) —
  say every owner was inferred from context.
- **Two-track session** — say the user's items were read from the tags and everyone else's
  were inferred.
- **Unresolved `[note: …]` flags** — list them; they must be fixed before sending.
- **`warnings` in `session.json`** or **`track alignment: UNKNOWN`** — relay verbatim.
- **`other` profile** — offer to save a profile file if the team will recur.

---

## Frontmatter conventions

Wikilinks go **inside** the YAML: a wikilink in a property registers as a backlink on the
person's note *and* stays a filterable property for the Base.

```yaml
---
date: 2026-09-10
type: regular
team: "[[Acme Team]]"
org: "[[Acme Health]]"
attendees:
  - "[[Jan Smit]]"
  - "[[Alex Rivera]]"
absent:
  - "[[Sam Lee]]"
guests:
  - "[[Pat Kim]]"
tags: [meeting, acme-team, regular]
---
```

Rules:
- `team:` and `org:` come from the profile verbatim. `team` is deliberately generic — it
  holds a whole team, a working group, or a project group alike. Omit `org:` if the profile
  has none.
- `attendees` + `absent` together always equal the profile's roster. Omit `absent:` only
  when everyone was present; omit `guests:` when there were none.
- Always include `meeting` and the profile's tag in `tags`, plus the type. Tags can't
  contain colons; if a type ever has one, sanitize it for the tag only.
- People, team, and org are always wrapped in `[[ ]]`, using the exact canonical names from
  the profile so they don't fragment into duplicate notes.
- **No roles in the frontmatter or headings** — roles live in the profile and inform
  ownership decisions only.
- **No `source:` field.** The input is deleted once the note exists.

---

## Output template

```markdown
---
date: {YYYY-MM-DD}
type: {type}
team: "[[{Team}]]"
org: "[[{Org}]]"
attendees:
  - "[[{Name}]]"
absent:
  - "[[{Name}]]"
guests:
  - "[[{Name}]]"
tags: [meeting, {team-tag}, {type}]
---

# {Filename prefix} — {YYYY-MM-DD}

> [!summary] TL;DR
> - {3–6 one-line bullets: what was decided or planned, and what's next}

## Action Items
### [[{Owner}]]
- [ ] {Task} ⏫ 📅 {YYYY-MM-DD}
- [ ] {Task} 🔽
### [[{Owner}]]
- [ ] {Task} 🔺
### Needs an owner
- [ ] {Task} [note: owner unclear]

{PROFILE EXTRA SECTIONS GO HERE, in the profile's order — e.g. Pipeline & Accounts,
Upcoming for team; nothing for other}

## Decisions
- {Agreement reached without a formal vote — what, and the reasoning if given}

## Discussion
### {Agenda item}
- {Scannable bullets, complete enough for an absent member}

## Next Meeting
- **When:** {date/time, or TBD}
- **Carried forward:** {items}
```

Notes on the template:
- **Required:** frontmatter, title, TL;DR, Discussion. **Omit every other section entirely**
  (heading included) when it has no content — never an empty heading or "None". That
  includes profile extra sections.
- **Owner is the `###` heading, never on the task line.** `Action Items.md` in the vault root
  aggregates open tasks with `group by heading`, which is what makes per-person views work
  across every team. Headings are plain wikilinked names — no roles, no parentheticals.
- **Action items are checkboxes** (`- [ ]`) with Tasks-plugin metadata. **Emoji order is
  fixed: priority first, then due date** — `- [ ] {task} ⏫ 📅 2026-09-17`.
- **Priority** — every item gets exactly one: `🔺` time-sensitive or blocking · `⏫`
  important, not blocking · `🔽` nice-to-have / long-horizon.
- **Due date** — `📅 YYYY-MM-DD` only when a concrete deadline was stated. Resolve relative
  language against the meeting `date:`, not today's. Vague timing stays as prose in the
  task. A genuine guess keeps the `📅` and gets a `[note: …]`.
- **Nothing else on a task line** — no `· High` words, no 🔴🟡🟢, no owner marker. The
  `✅ YYYY-MM-DD` done date is written by the plugin when someone ticks the box.
- Tables in extra sections get one row per item; keep a `Notes` column to a phrase.
- `> [!summary]` is a native Obsidian callout; the share-copy script flattens it.

---

## Tone & style

- **Third person throughout.** The user is referred to by name like everyone else — never
  "I". What the user said or agreed to is recorded exactly like anyone else's contribution.
- Written for the team, including whoever was absent: cover every agenda item, record
  outcomes and the reasoning behind them, and don't assume the reader was in the room.
- Neutral and factual. Don't editorialize or characterize members' positions beyond what
  they said.
- Use members' first names (or what the profile says they go by) in prose after the first
  full-name mention. Wikilink the full canonical name in frontmatter, headings, and tables.
- Concise — bullets over paragraphs, no padding, no transcript-style narration.
- Flag ambiguity inline with `[note: …]` rather than guessing, and surface every flag in
  Step 2.5 and Step 6.

---

## Edge cases

- **Very short meeting:** collapse Discussion into a single short section.
- **Poor audio / inaudible spans:** note `[inaudible]` inline; flag in the TL;DR if a
  meaningful chunk was lost. Suggest `medium.en` for a re-run.
- **Transcript already has speaker labels** (some phone apps produce them): trust the labels
  for ownership and say so in the report; still apply the name corrections.
- **Profile roster still has placeholders** (e.g. `[[Name]]` rows): stop and ask the user to
  fill in the profile before running; don't write a note with placeholder attendees.
- **Wrong environment:** if there's no shell or no Whisper, don't fake a transcript — explain
  that this skill needs Claude Code with Whisper installed, and offer to proceed if the user
  pastes a transcript.
- **Not a team meeting:** if the content is clearly a 1:1 or a call the user wants as their
  own personal notes, stop and say so — that belongs to the `meeting-notes` skill in
  `../scribe/`.
