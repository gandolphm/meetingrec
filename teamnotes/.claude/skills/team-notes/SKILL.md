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
  transcript, or a meetingrec session directory. Also use it when the user wants to change
  where team notes go. NOT for the user's own personal notes on a call or 1:1 — those use
  the separate meeting-notes skill in ../scribe/.
allowed-tools: Bash, Read, Write, Edit, Glob, AskUserQuestion
---

# Team Notes (Obsidian)

Turns a team meeting recording or transcript into two files: an Obsidian note in the team
vault (the `teamnotes` folder by default, or a vault the user chose on the first run), and a
plain-Markdown copy of the same note that can be pasted into an
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
| Vault | `scribe/`, or the user's own | `teamnotes/`, or the user's own — never the scribe vault |

"The user" means whoever is running the skill.

**Key architectural fact:** transcription is an *external dependency*. The skill shells out to
a local Whisper binary, so it must run in Claude Code on the user's machine, not the web
sandbox.

Read `teamnotes/CLAUDE.md` (`$TEAMNOTES/CLAUDE.md` after Step 0) before writing anything:
the voice rules live there. The Whisper
names and the user's rules are loaded in Step 0.1.

---

## Workflow

### Step 0 — Set the roots

Set these explicitly before anything else, and do not `cd`: every later command names one
of them. All three come from `${CLAUDE_SKILL_DIR}` and the user's settings, never from the
shell's working directory, so the skill can't land in `../scribe/` by mistake.

- **`$TEAMNOTES`** — the `teamnotes/` folder in the repo. Holds `CLAUDE.md` and the inbox.
- **`$INBOX`** — `$TEAMNOTES/input/`, where phone recordings and transcripts are dropped.
- **`$KEEP`** — `scribe/transcripts/`, where a transcript goes when the user chooses to keep
  it (Step 5). All kept transcripts live there, team or personal; it's the only place in
  `../scribe/` this skill touches.
- **`$VAULT`** — the Obsidian vault the notes go into: `meeting-notes/`, `share/`,
  `Action Items.md` and the Base. `$TEAMNOTES` unless the user chose another.

The vault is a setting in `~/.config/meetingrec/config.sh`, read through the `meetingrec`
command so the default lives in one place:

```bash
TEAMNOTES="$(cd "${CLAUDE_SKILL_DIR}/../../.." && pwd)"
MR="$(dirname "$TEAMNOTES")/.engine/bin/meetingrec"
INBOX="$TEAMNOTES/input"
KEEP="$(dirname "$TEAMNOTES")/scribe/transcripts"
VAULT="$("$MR" config get TEAM_VAULT)"; VAULT_SAVED=$?
echo "VAULT=$VAULT (saved: $([ $VAULT_SAVED -eq 0 ] && echo yes || echo no))"
[ -d "$INBOX" ] || echo "MISSING INBOX: $INBOX"
[ -d "$VAULT" ] || echo "MISSING VAULT: $VAULT"
```

If it prints `saved: no`, the user has never been asked where team notes go: do **Step
0.05** **now, before looking in the inbox**, even if the inbox turns out to be empty. A new
user often runs the skill once just to get set up. If `MISSING INBOX` prints, stop and ask the user where it went;
don't create it. If `MISSING VAULT` prints, the saved folder was moved or deleted: tell the
user, and do Step 0.05 to pick it again.

Then create the output folders; a fresh clone or a new vault won't have them:

```bash
mkdir -p "$VAULT/meeting-notes" "$VAULT/share"
```

### Step 0.05 — Ask where team notes go (first run, or when the user asks)

Do this when Step 0 printed `saved: no` or `MISSING VAULT`, or whenever the user asks to keep
team notes somewhere else. Ask with `AskUserQuestion`, once:

- Question: "Where should team notes go?"
- Option 1, **"In meetingrec's teamnotes folder (Recommended)"**: "The teamnotes folder is
  already an Obsidian vault with a notes table and an Action Items page. Open it in
  Obsidian once."
- Option 2, **"In another Obsidian vault"**: "Type its folder path in Other. It must be a
  different vault from your personal notes. Notes go in meeting-notes and share folders
  inside it."

On a first run, ask it in the same `AskUserQuestion` call as the profile question in Step
0.25 so the user isn't stopped twice.

Save the answer, then re-run Step 0 so `$VAULT` holds the new folder:

```bash
"$MR" config set TEAM_VAULT ""                # option 1: the teamnotes folder
"$MR" config set TEAM_VAULT "<their folder>"  # option 2
```

Before saving a folder of their own, check it isn't inside a vault (often the vault's own
`meeting-notes`), which would put the notes a level too deep, where the vault's notes table
can't see them:

```bash
"$MR" vault-root "<their folder>"   # prints the folder to use instead, or nothing
```

If it prints a folder, ask with `AskUserQuestion` whether to use that one instead
(Recommended) or keep theirs, and save whichever they pick.

If `config set` says the folder doesn't exist, check the path with the user (a typo is the
usual cause) and offer to create it; only `mkdir -p` it after a yes. If it says the folder is
already the personal-notes vault, explain that team and personal notes need separate vaults
(each has its own to-do page, and they would show each other's items) and ask again.

For a folder of their own, mention that Claude Code asks permission the first time it
writes outside the meetingrec folder, so the prompt isn't a surprise. Whether the folder is
set up as a vault is checked in Step 0.15, on every run.

When the folder **changed** from one that already holds notes, the old notes and share
copies stay where they are. Count them (`find "<old vault>/meeting-notes" "<old vault>/share"
-name '*.md' | wc -l`) and, if there are any, offer to move both folders' notes into the new
vault. Move only on a yes, and never over a file with the same name.

### Step 0.1 — Load the user's settings: names and rules

**Read both settings files before transcribing or writing anything:**

- **`shared.md`** — names and rules for everyone using one copy of the repo, tracked in
  git. Empty in the public repo; a team that forks it fills it in for its members.
- **`personal.md`** — the names the user has added and their rules for every team. Git
  ignores it, so it is never committed and an update never overwrites it. It doesn't exist
  until the first run, which creates it from its template:

```bash
REF="${CLAUDE_SKILL_DIR}/reference"
# Before the rules existed this file was names.local.md; carry it over.
[ -f "$REF/personal.md" ] || { [ -f "$REF/names.local.md" ] && mv "$REF/names.local.md" "$REF/personal.md" \
  && awk '!d && /^\| Heard as/ { print "## Names\n"; d = 1 } { print }' "$REF/personal.md" > "$REF/personal.md.tmp" \
  && mv "$REF/personal.md.tmp" "$REF/personal.md"; }
[ -f "$REF/personal.md" ] || cp "$REF/personal.example.md" "$REF/personal.md"
grep -q '^## Rules' "$REF/personal.md" || { echo; sed -n '/^## Rules/,$p' "$REF/personal.example.md"; } >> "$REF/personal.md"
cat "$REF/shared.md" "$REF/personal.md"
```

**Names.** The *Names* tables feed the priming prompt in Step 1 and the corrections in Step 2.

**Rules.** The *Rules* sections say how this user wants team notes written. The chosen
profile (Step 0.25) can have a *Rules* section too, for that team only. Apply all of them
through every later step. Lines inside `<!-- -->` are examples, not rules.

**Order of priority**, highest first: the protected rules below, then the profile's rules,
then `personal.md`, then `shared.md`, then the rest of this file. If two rules at the same
level contradict each other, say so and ask which one holds rather than picking one.

**Protected rules.** No rule from any of those files can change these, because the user's
data, the team, or the rest of meetingrec depends on them. When a rule conflicts with one,
follow the protected rule and tell the user which rule was set aside and why:

- The input is never deleted before both the note and the share copy are written and read
  back (Step 5).
- The frontmatter fields, their formats, and the action-item format (owner as the `###`
  heading, priority then `📅`) stay as specified below: `index.base` and `Action Items.md`
  depend on them. A rule can change their *values*.
- Never write to a tracked file: this `SKILL.md`, `shared.md`, `personal.example.md`,
  `other.md`, `team.example.md`, the scripts, `Action Items.md`. Writes go to `personal.md`
  or to the user's own profile files.
- Never write into the scribe vault or the user's personal-notes vault, never invent
  transcript content, and every attendee in the roll call comes from the user's answers.

**When the user states a lasting preference** during a run ("from now on…", "always…",
"remember that…", "never…"), apply it to this note and save it as a rule, worded as a rule:
under *Rules* in the profile if it's about this team only (the user's own profiles, never
`other.md`), otherwise under *Rules* in `personal.md`. If it's unclear which, ask. Show them
the line you added. If it would conflict with a protected rule, say so instead of adding it.

### Step 0.15 — Check the vault is set up (every run)

The team vault isn't always chosen through Step 0.05: the user can also pick it in
○ → Settings or edit `config.sh`, and neither of those sets the vault up. So check on every
run:

```bash
[ -d "$VAULT/.obsidian" ] || echo "NOT A VAULT YET"
[ -f "$VAULT/Action Items.md" ] || echo "NO ACTION ITEMS PAGE"
```

- **`NOT A VAULT YET`** — Obsidian hasn't opened the folder. Tell the user, in one line, to
  open it once with Obsidian → *Open folder as vault*, and carry on.
- **`NO ACTION ITEMS PAGE`** — there's no page collecting everyone's action items, so this
  note's items won't show up on one. Unless a rule in `personal.md` says not to offer it for
  this vault, offer once to copy the starter page in. On a yes, copy it with
  `cp -n "$TEAMNOTES/Action Items.md" "$VAULT/Action Items.md"` (never over an existing
  file). On a no, add a rule to `personal.md` so the offer isn't repeated: *"Don't offer to
  copy Action Items.md into <vault path>."* Tell the user you saved it and that deleting the
  rule brings the offer back.

Neither check stops the run. Ask the offer in the same `AskUserQuestion` call as the
profile question in Step 0.25 when you can, so the user isn't stopped twice.

### Step 0.25 — Pick the profile

```bash
ls "${CLAUDE_SKILL_DIR}/profiles/"
```

Files ending in `.example.md` are templates, not profiles: never offer one. If `team.md` is
missing, offer **team** anyway (label it "set up on first use"); picking it runs the first-run
setup below.

**Always ask which profile to use** — never infer it silently from the user's wording or
from the input filename. Use `AskUserQuestion` with one option per profile file (label =
the team name from the profile's header, description = its org), plus `other`. If the
user's words point at a profile ("Acme team notes"), put that one first and mark it
"(Recommended)", but still ask: a wrong profile puts the wrong roster in the roll call, the
wrong sections in the note, and the wrong name on the share copy, and none of that is
visible until the note is already written.

Ask this **before** scanning `$INBOX` and before any other question, so the roll call in
Step 0.75 can be built from the right roster.

Then **read the chosen profile file in full** — it is the source for the roster, the extra
sections, the filename prefix, the tag, the priming terms, and any *Rules* for this team
(see Step 0.1 for where they rank) used in every later step.

**First-run setup of the `team` profile.** Profiles the user fills in are theirs: git ignores
every file in `profiles/` except `other.md` and the templates, so a roster is never committed
and an update never overwrites it. If `team.md` doesn't exist yet, create it from the template:

```bash
P="${CLAUDE_SKILL_DIR}/profiles"
[ -f "$P/team.md" ] || cp "$P/team.example.md" "$P/team.md"
```

Then, if its field table or roster still holds `{…}` placeholders, fill them in by asking
the user, in one round:

- the **team name**, the **org**, and a **short name** for filenames (default: the team name);
- the **roster**: everyone on the team, with the name they go by and their role. Let them
  paste it as a list;
- whether to keep the template's **extra sections** (*Pipeline & Accounts*, *Upcoming*).

Write the answers into `team.md`: the field table (tag = the short name, slugified), one
roster row per person, and the priming terms. Remove the template's placeholder ownership
hints, keeping only the `[note: owner inferred]` line; hints can be added later. Drop the
extra sections they don't want. Replace the "This is a template" paragraph with one line
saying the file is the user's own and to edit it when the team changes. Then continue with
the run. Only `{…}` in the field table and roster count as unfilled: the extra-section blocks
contain `{…}` on purpose, as the template for each row.

For `other`, the profile tells you what to ask the user for instead (team name, org,
attendees). If that team is likely to recur, offer at the end to save a new profile file so
the next run doesn't have to ask.

### Step 0.5 — Locate the input

Unless the user already named a file or pasted a transcript in chat, scan `$INBOX`. There
are two shapes:

**Flat files** are the usual case for in-person meetings recorded on a phone. Expect a `.m4a`/`.mp3`/`.wav`, or a `.txt`/`.srt`/`.vtt` exported by a phone
transcription app:

```bash
ls -t "$INBOX" 2>/dev/null | grep -iE '\.(m4a|mp3|wav|mp4|txt|srt|vtt|md)$'
```

**Session directories** appear only when the user has moved one in by hand from a
meetingrec recording of a virtual meeting — one directory named `<ISO-datetime>_<slug>/`
containing `mic.wav`, usually `system.wav`, and `session.json`:

```bash
find "$INBOX" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
```

(`find`, not `ls "$INBOX"/*/` — under zsh a non-matching glob aborts the whole command.)

Then:

- **Exactly one candidate** (file or directory) → use it and continue.
- **Several** → list them back to the user and ask which one. A second file may be an
  unrelated recording — possibly for a different profile — waiting for its own run.
- **None** → say the inbox (`$INBOX`) is empty and ask the user to drop a recording or transcript in, or
  paste one. Don't fabricate a transcript or wait passively.

### Step 0.75 — Gather context (one round of questions)

If the input is a session directory, read `session.json` first and use it to **pre-fill**
the answers — but still ask. Also run the recording health check:

```bash
cat "$INBOX/<session-dir>/session.json"
python3 - "$INBOX/<session-dir>/session.json" <<'EOF'
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

Then ask, in **one compact round**, **with `AskUserQuestion`, not as a written list.** It
takes up to four questions per call, each with two to four options, and always adds a
free-text answer. Fill the options with real guesses, so most answers are one click:

- **Date** of the meeting. Options: the date in the file or folder name (Recommended) and
  today, if they differ.
- **Meeting type** — the profile lists its usual types; also scan existing notes for this
  team. Offer up to four; a new type is typed in the free-text answer:
  ```bash
  grep -l '^team: "\[\[<Team>\]\]"' "$VAULT"/meeting-notes/*.md 2>/dev/null \
    | xargs grep -h '^type:' 2>/dev/null | sed 's/^type: *//' | sort -u
  ```
- **Roll call** — which roster members were present, as a multi-select. A question holds
  at most four options, so split a larger roster across several multi-select questions
  ("Who was there? (1 of 2)"), in the same or a second call. Everyone not selected goes under
  `absent:`.
- **Guests** — anyone not on the roster, with their org if known. Options: "No guests", and
  guests from this team's earlier notes; others are typed in the free-text answer.
- **Agenda or context** worth knowing — what was on the docket, anything being followed up
  from the previous meeting. Options: "Nothing to add", with the agenda typed in the
  free-text answer.

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
  "$INBOX/<file>" "$INBOX" "small.en" "<priming prompt>"
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
python3 "${CLAUDE_SKILL_DIR}/scripts/transcribe_session.py" "$INBOX/<session-dir>" \
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

Apply the name corrections from both settings files (Step 0.1) first, then extract:

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

Write one file to `$VAULT/meeting-notes/<filename prefix> — YYYY-MM-DD.md`, prefix from the
profile (e.g. `Acme Team — 2026-09-10.md`). The date **is** in the filename here: every meeting of a team has the same title, so the date
is what makes filenames unique. `date:` in the frontmatter is still the sort key.

**Never overwrite a note or a share copy.** Two meetings of one team on the same day, or a
vault that already held notes, can collide, so check both folders first:

```bash
ls "$VAULT/meeting-notes/<basename>.md" "$VAULT/share/<basename>.md" 2>/dev/null
```

If either exists, add ` 2`, ` 3` and so on until neither does: `Acme Team — 2026-09-10 2.md`.
The share copy in Step 3.5 takes the same name automatically.

Follow the frontmatter conventions and the template at the end of this file exactly,
inserting the profile's extra sections where the template marks them.

### Step 3.5 — Write the share copy

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/make_share_copy.py" "$VAULT/meeting-notes/<file>.md"
```

It writes `$VAULT/share/<same basename>.md` with the frontmatter turned into a header block (team
and org from `team:`/`org:`, then Present / Absent / Guests), wikilinks unwrapped, the
callout flattened, and the Tasks emoji turned into words. Everything else is left
byte-for-byte alone, so the two files never disagree. Exit code 2 means it wrote the copy
but found `[note: …]` flags still in it — relay the list so they are fixed before the note is
sent. Read the share copy once to confirm it reads cleanly as plain text.

### Step 4 — Ensure the Base exists

**Use `find`, not a glob** — a `*.base` pattern that matches nothing makes zsh abort the
whole command, and the failure is indistinguishable from "no Base exists":

```bash
find "$VAULT" -name '*.base' -not -path '*/.claude/*' -not -path '*/.obsidian/*' -not -path '*/.trash/*'
```

The `-not -path '*/.claude/*'` matters: in the default vault the starter Base ships inside
this skill's own `assets/`, so an unpruned `find` always reports a hit.

**If a Base already exists, leave it alone.** If none exists:

```bash
cp -n "${CLAUDE_SKILL_DIR}/assets/index.base" "$VAULT/index.base"
grep -n 'inFolder' "$VAULT/index.base"   # must read file.inFolder("meeting-notes")
```

### Step 5 — Clean up the used input

**Only after both files are written and read back**, deal with just the input you used plus
its own intermediate artifacts. Leave any *other* entry in `$INBOX` alone.

**Verify first.** The note may become the only record of the meeting — there is no second
pass. Spot-check every amount, tally, and owner against the transcript before this step.
When in doubt, leave the input in place and say so; a stale file in `$INBOX` costs nothing.

**Ask what happens to the transcript**, every run, with `AskUserQuestion`:

- Question: "The notes are saved. What should happen to the transcript?"
- Option 1, **"Delete it"**: "The recording and its transcript are removed. The note is the
  only record of the meeting."
- Option 2, **"Move it to transcripts/"**: "The transcript text is kept in
  scribe/transcripts/ to look back at later. The audio is deleted."

Don't ask when the answer is already known: the user's request said it in any phrasing, or a
rule in `personal.md` or the profile settles it ("always keep transcripts for this team"). If
they answer with a lasting preference, save it as a rule the way Step 0.1 describes, so later
runs don't ask. If they asked to keep the recording itself, move the whole session directory
or audio file into `$KEEP` instead of the steps below.

**Move it to transcripts/.** `$KEEP` must exist; if it doesn't, stop and ask rather than
creating it or falling back to deleting. For a session directory, keep the text and the
session metadata, in a folder of the same name:

```bash
[ -d "$KEEP" ] || echo "MISSING KEEP: $KEEP"
mkdir "$KEEP/<session-dir>"
for f in merged.txt mic.srt system.srt session.json; do
  [ -f "$INBOX/<session-dir>/$f" ] && mv "$INBOX/<session-dir>/$f" "$KEEP/<session-dir>/"
done
ls "$KEEP/<session-dir>"
```

Check that `merged.txt` (or `mic.srt` for a mic-only session) is listed, then delete what's
left: `rm -rf "$INBOX/<session-dir>"`. For a flat file, keep the transcript: the `.srt` made
from a phone recording, or the dropped `.txt`/`.srt` itself. Move it with `mv -n` (never over
a file of the same name; add the date to the name if one exists), then delete the source
audio and its `.16k.wav`.

**Delete it.** For a session directory, the whole directory is the artifact:

```bash
rm -rf "$INBOX/<session-dir>"
```

For a flat file, the source plus anything derived from the same basename:

```bash
rm -f "$INBOX/<used-file>" "$INBOX/<used-basename>".srt "$INBOX/<used-basename>".16k.wav
```

Never delete before the note is on disk, and never wipe the whole folder. `$INBOX` must end
the run without this input either way, or the next run would write the note a second time.
Say in the Step 6 report where a kept transcript landed.

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

**Then offer to remember what this run taught you**, in one message with up to two lists.
Skip a list that would be empty, and skip the message if both are.

- **New names.** Every proper noun that came through wrong and isn't in either *Names*
  table: ones the user corrected (including in Step 2.5), and ones you fixed from the roster
  or context. Show them as rows:

  | Heard as | Correct spelling | Who / what | Team |
  | -------- | ---------------- | ---------- | ---- |
  | Kalibra / Calibra | **Collibra** | vendor, comes up often | {team} |

- **Possible rules.** Corrections the user made to *how* the note was written that look like
  a lasting preference rather than a one-off fix: they moved an item to a different owner
  for the same reason twice, asked for a section to be shorter, changed how votes or
  decisions are worded. Word each as a rule and say where it would go: this team's profile,
  or `personal.md` for every team. Don't suggest one the user already stated (Step 0.1 saved
  those), one that conflicts with a protected rule, or one based on a single fact about
  this meeting.

Ask once which to keep — all, some, or none. Append accepted names to the *Names* table in
`personal.md` and accepted rules where you proposed them. Never add anything the user didn't
accept, and never write to `shared.md`, `other.md` or a template.

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
- **Profile roster still has placeholders** (e.g. `[[{Full Name}]]` rows): run the first-run
  setup in Step 0.25 before going further; never write a note with placeholder attendees.
- **Wrong environment:** if there's no shell or no Whisper, don't fake a transcript — explain
  that this skill needs Claude Code with Whisper installed, and offer to proceed if the user
  pastes a transcript.
- **Not a team meeting:** if the content is clearly a 1:1 or a call the user wants as their
  own personal notes, stop and say so — that belongs to the `meeting-notes` skill in
  `../scribe/`.
