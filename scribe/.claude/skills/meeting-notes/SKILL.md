---
name: meeting-notes
description: >-
  Turn a meeting audio recording (or transcript) into a structured, Obsidian-ready
  Markdown note with a TL;DR, decisions, action items, and follow-up questions. Use
  this skill whenever the user provides or points to a meeting recording, audio file
  (.m4a/.mp3/.wav/.mp4), or raw transcript and wants it written up — including phrasings
  like "write up notes from this meeting", "summarize this call", "transcribe and
  summarize", "pull the action items from this recording", "scribe", "what were the next steps",
  or "turn this meeting into a note". Covers work meetings — 1:1s, standups, customer,
  partner, investor and strategy calls — written up as the user's own notes. When no file is
  given, the skill auto-scans the recorder inbox (`scribe/input/`) for a recording or
  transcript. Output is a single .md file with YAML frontmatter, wikilinked people and
  companies, checkbox action items, and topic timestamps, written into `scribe/meeting-notes/`
  (the scribe folder is the Obsidian vault). Always use this skill for meeting audio or
  transcripts rather than improvising a summary.
  NOT for anything described as "for the team" or meant to be shared with everyone who
  attended — those use the separate team-notes skill in the teamnotes vault.
allowed-tools: Bash, Read, Write, Glob
---

# Meeting Notes (Obsidian)

Turns meeting audio or a transcript into one clean Obsidian note. Transcription runs
locally via Whisper; the notes are written for an Obsidian vault (frontmatter +
wikilinks + a native Base), not generic Markdown. When the user invokes the skill without
naming a file (e.g. just "scribe"), it looks in the recorder's inbox for the recording or
transcript to use.

**The `scribe/` folder is the Obsidian vault.** This skill, its scripts, the recorder inbox
(`input/`), the transcript archive (`transcripts/`) and the notes (`meeting-notes/`) all live
under it. Every path is derived from `${CLAUDE_SKILL_DIR}`, so the repo can be cloned
anywhere — see Step 0.

**Key architectural fact:** transcription is an *external dependency*, not something this
model does natively. The skill shells out to a local Whisper binary. It must run in an
environment with shell access and Whisper installed — i.e. **Claude Code on the user's
machine**, not the web sandbox.

---

## Workflow

### Step 0 — Set the roots

Set these explicitly before anything else, and do not `cd`: every later command names one
of them.

- **`$VAULT`** — the `scribe/` folder, which is the Obsidian vault. Notes go to
  `$VAULT/meeting-notes/`.
- **`$INBOX`** — the recorder's drop folder, `$VAULT/input/`.
- **`$KEEP`** — the transcript archive, `$VAULT/transcripts/`. Only used when the user asks
  for the transcript to be kept (Step 5).

```bash
VAULT="$(cd "${CLAUDE_SKILL_DIR}/../../.." && pwd)"
INBOX="$VAULT/input"
KEEP="$VAULT/transcripts"
[ -d "$INBOX" ] || echo "MISSING INBOX: $INBOX"
mkdir -p "$VAULT/meeting-notes"
```

All three are derived from `${CLAUDE_SKILL_DIR}` rather than hardcoded, so they survive the
repo being cloned anywhere or renamed. `meeting-notes/` is created on demand — a fresh clone
won't have it. If the `$INBOX` check prints, stop and ask the user where it went — don't
guess, and don't create it: a missing `$INBOX` looks exactly like "no recordings waiting",
and usually means `meetingrec`'s `OUTPUT_ROOT` points somewhere else.

### Step 0.1 — Load the name corrections

**Read the name table before transcribing or writing anything:**

```bash
cat "${CLAUDE_SKILL_DIR}/reference/names.md"
```

It lists proper nouns Whisper reliably mishears. They feed the priming prompt in Step 1 and the
corrections in Step 2. This is not optional and nothing else loads it — skip it and the note
comes out looking perfectly fine with every recurring name spelled wrong.

The table's **`Me` row** names the person running the skill — "the user" everywhere below.
Their name always goes in the priming prompt, and on an untagged transcript it is how you
recognise which lines are theirs. If the row still holds the `{Your Name}` placeholder, ask
the user for their name once, use it for this run, and suggest they fill in the row.

### Step 0.2 — Find the input

Unless the user already named a specific file or pasted a transcript in chat, find the input
yourself by scanning `$INBOX`.

There are two shapes of input. **Check for session directories first:**

```bash
find "$INBOX" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
```

(`find`, not `ls "$INBOX"/*/` — under zsh a non-matching glob aborts the whole command instead of
failing quietly, which is the same trap the flat-file scan below avoids.)

A **session directory** is what `meetingrec` produces — one directory per meeting, named
`<ISO-datetime>_<slug>/`, containing `mic.wav`, usually `system.wav`, and a `session.json`.
Take the newest one and continue to Step 0.5.

If there are no session directories, fall back to the **flat-file** scan for a manually
dropped recording:

```bash
ls -t "$INBOX" 2>/dev/null | grep -iE '\.(m4a|mp3|wav|mp4|txt|srt|vtt|md)$'
```

(`-t` lists newest-first; the `grep` keeps only audio/transcript extensions.) Then:

- **Exactly one match** → use it as the input and continue to Step 0.5.
- **Multiple matches** → list the filenames back to the user and ask which one to use before
  continuing.
- **No matches** → tell the user the inbox is empty and ask them to drop a recording/transcript
  in there or give a path. Don't fabricate a transcript or wait passively.
- If the user explicitly named a file or pasted a transcript, skip this scan and use that.

If both a session directory and loose files exist, ask which the user means rather than
guessing — the loose file may be an unrelated recording waiting for its own run.

### Step 0.5 — Gather context (ask in chat, briefly)

If the input is a session directory, read its `session.json` first and use it to **pre-fill**
these answers — but still ask. It records the title typed at record time, the tracks captured,
and which audio devices were used:

```bash
cat "$INBOX/<session-dir>/session.json"
```

Pre-filling, not skipping, is the point. A title typed while scrambling to join a call is
often wrong or absent, and any error here lands directly in the Whisper priming prompt — the
one place a wrong proper noun propagates through everything downstream. Confirm, don't assume.

Also note `tracks` — it decides which path Step 1 takes:

- `["mic", "system"]` → two tracks, merged and tagged
- `["mic"]` → recorded with `--mic-only`, on speakers. One track, so **no `[Me]`/`[Them]`
  tags** — say so when reporting back, since ownership in Step 2 is then inferred rather than
  known.

Either way Step 1 runs the same command; it adapts to whichever tracks are present.

If `session.json` is missing or unreadable, fall back to counting audio files in the
directory: two → two-track, one → single. A half-written session should still produce a note.

**Check the recording is sound before transcribing it.** `meetingrec stop` records what it
measured, and a bad track is much cheaper to find now than after a Whisper run that returns
nothing:

```bash
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

`peak_dbfs` is the loudest sample in the track. A healthy one is around −5 to −30. **`null`, or
anything below −60, means the track is digital silence** — it recorded nothing. Stop and tell
the user before transcribing; on `system.wav` this is almost always a System Audio Recording
permission problem, and the meeting audio is simply gone. Relay any `warnings` the same way.

Do not treat a silent track as a reason to abandon the note: if the *other* track is fine, say
what was lost and carry on with the single track, tagging nothing.

Then ask for the handful of things that improve both the transcript and the frontmatter. Keep
it to one compact round of questions:

- **Title / topic** of the meeting
- **Date** (default to today if not given)
- **Type**: the set of types is open-ended and grows over time — don't rely on a fixed
  list. Scan existing notes for types used so far:
  ```bash
  grep -h '^type:' "$VAULT"/meeting-notes/*.md 2>/dev/null | sed 's/^type: *//' | sort -u
  ```
  Present these as options (via AskUserQuestion or similar) alongside a clear way to enter
  a brand-new type. If the user picks or types a new type, just use it — no need to ask
  permission or treat it as special. Standard ones to expect even on a fresh vault:
  standup, strategy, client, 1:1, interview, other.
- **Attendees** (names → these become `[[wikilinks]]`)
- **Company / org** (→ a `[[wikilink]]`)
- **Context** — the single word every action item from this meeting gets tagged with
  (`context: work` → `#work` on each to-do). This is what makes the Tasks dashboard
  filterable. The default is `work`; a different value only makes sense for a meeting the
  user wants kept on a separate dashboard (e.g. a specific partner or workstream). **State the
  default and let the user override it.** Offer existing values first:
  ```bash
  grep -h '^context:' "$VAULT"/meeting-notes/*.md 2>/dev/null | sed 's/^context: *//' | sort -u
  ```
  One lowercase word, no `#`, no spaces — it becomes a tag, and Obsidian tags can't contain
  spaces or colons.
- **Any agenda or context** worth knowing

Why this comes first: the attendee names, company, and jargon get passed to Whisper as a
**priming prompt**, which sharply improves how it transcribes proper nouns (company, product and
colleague names) that it would otherwise mangle. If the user already gave some of
this in chat, don't re-ask — fill the gaps only.

### Step 1 — Transcribe (only if the input is audio)

If the input is already a transcript (`.txt`/`.srt`/`.vtt`/`.md` or pasted text), skip to Step 2.

For audio, run the bundled script. It auto-selects whisper.cpp (fast, Metal-accelerated)
if `whisper-cli` is on PATH, else falls back to openai-whisper:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/transcribe.sh" \
  "<audio_path>" "<out_dir>" "small.en" "<priming prompt: attendee names, company, key terms>"
```

- Default model is `small.en` — noticeably more accurate than `base.en` on meeting audio,
  and still ~20x realtime on Apple silicon (a 30-minute track runs in ~90s). `base.en` is
  ~3x faster but hallucinates filler speech into silence, snaps timestamps to coarse
  blocks, and flubs short words — all of which degrade the notesheet. Only drop to
  `base.en` if the user explicitly wants speed on a long recording. (A two-track session
  runs Whisper twice, so the model choice costs roughly double.)
- The script prints `OK <path-to-.srt>` on success.
- Handle the documented failure exits gracefully and relay the fix to the user:
  - `NO_ENGINE` → no Whisper installed → `brew install whisper.cpp` (or `pip install openai-whisper`)
  - `MODEL_NOT_FOUND` → relay the exact `curl` command the script prints to fetch the ggml model
  - `NO_FFMPEG` → `brew install ffmpeg`
  Do **not** try to work around a missing engine by transcribing some other way — stop and
  tell the user what to install.

#### Session directories: use `transcribe_session.py` instead

For a **session directory** (either one or two tracks), do not call `transcribe.sh` yourself.
Use:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/transcribe_session.py" "$INBOX/<session-dir>" \
  --model small.en --prompt "<attendee names, company, key terms>"
```

It writes `mic.srt`, `system.srt` and — for two-track sessions — `merged.txt`, which is what
you read in Step 2. It prints a short summary; two lines in it need acting on:

- `NO SPEECH DETECTED` — on a real meeting, that track captured nothing. Cross-check
  `peak_dbfs` from Step 0.5: silence there too means a permissions problem, not a quiet call.
- `track alignment: ... corrected` — normal, no action. The two tracks never start at the same
  instant (a Bluetooth mic takes seconds to open; measured between 1.7 s and 4.7 s on the same
  hardware), and the offset is subtracted here. But **`track alignment: UNKNOWN`** means it
  could not be determined, so the tracks were merged as if they started together. Ordering
  *across* speakers is then unreliable — a reply may appear before what it answered. Say so in
  the report, and treat the interleaving in `merged.txt` as approximate. Ordering *within* one
  speaker's lines is still sound.

**Why not just run `transcribe.sh` twice.** A per-speaker track is mostly silence, because the
far end is quiet while you talk. Whisper handles long silence badly in two ways, both measured
on a 95-second test track:

- **It hallucinates.** A minute of silence produced a confidently repeated sentence that nobody
  said, fifteen times over. Invented content in a meeting transcript is worse than missing
  content — it reads exactly like a real commitment.
- **Its timestamps drift.** Speech at 12s/45s/78s came back tagged 0s/20s/50s, which
  interleaved a reply ahead of the thing it was replying to.

`transcribe_session.py` strips the silence before Whisper sees it and maps the timestamps back
onto real session time afterwards, which fixed both (every cue then landed within ~1s of truth).
Calling `transcribe.sh` directly on a track skips that and reintroduces both problems.

Two things worth knowing about `merged.txt`:

- **Attribution is a routing fact, not a guess.** `[Me]` means the audio arrived on your
  microphone. This is the entire reason for recording two files.
- **Speaker bleed.** If the user was on speakers rather than headphones, `mic.wav` also picked
  up the other party through the air, so some lines appear twice — once as `[Me]` and once as
  `[Them]`. `system.wav` never contains the user, so the error only runs one way:
  **a `[Them]` tag is reliable; a duplicated `[Me]` line is not.** If the same sentence appears
  under both tags, trust `[Them]` and drop the `[Me]` copy. Mention it in the report so they
  know to use `--mic-only` next time they're on speakers.

### Step 2 — Analyse the transcript

Apply the name corrections from `reference/names.md` (Step 0.1) first, then extract:
- **Attendees** (reconcile with what the user gave in Step 0)
- **Key points** — important or new information, grouped by theme. Keep these as
  brief, scannable fragments — not full sentences, not a topic-by-topic recap. Just
  what's worth remembering, skipping minor topics entirely.
- **Decisions** — explicit agreements or resolved questions
- **To-Do** — tasks the user owns only (tasks assigned to other attendees are
  not tracked here), and only ones they *explicitly committed to* in the transcript.
  **Five maximum, fewer is normal.** Don't extrapolate: a topic being discussed, a
  problem being raised, or something that sounds like it *ought* to be done is not a
  to-do unless they said they'd do it. If more than five real commitments exist, keep the
  five that matter most (time-sensitive or blocking first) and leave the rest out
  rather than padding the list. For each one capture three things:
  - its **priority tier**;
  - any **stated deadline** → the due date (`📅`);
  - **when they said they'd actually do it** → the scheduled date (`⏳`).

  These last two are different facts and the meeting usually supplies them separately:
  *"they need it by Friday"* is a due date, *"I'll look at it Wednesday morning"* is a
  scheduled date. Capture whichever the transcript gives — often only one, sometimes
  neither. Resolve relative dates ("Thursday", "tomorrow") against the meeting date while
  the surrounding context is in front of you, not later at write time.
- **Action Items** — the overflow bucket: things that genuinely matter but didn't make
  the To-Do cut, either because the list was already at five or because they're real
  follow-ups the user never explicitly committed to. Also where another attendee's
  commitment goes when the user is depending on it. These are *not* tracked tasks —
  no checkbox, no tag, no dates — so they stay off the Tasks dashboard. This section is
  a release valve for the five-item cap, not a licence to re-add everything that was cut;
  if it wasn't worth a to-do and isn't worth remembering, leave it in Key Points.
- **Questions to ask** — things the user needs to follow up on with someone,
  not general open threads

**When the transcript is tagged** (a merged two-track session), ownership is *read off the
tags, not inferred from context*:

- A commitment on a `[Me]` line is the user's → it belongs in **To-Do**.
- A commitment on a `[Them]` line is someone else's → it does **not** go in To-Do, no matter
  how it's phrased. "I'll send that over" under `[Them]` is their task.
- A question on a `[Them]` line that the user didn't answer is a candidate for
  **Questions to Ask**; a question on a `[Me]` line that went unanswered is one to chase.

This replaces guessing from conversational context, which is what the single-track path has to
fall back on. On an **untagged** transcript (a `--mic-only` session or a manually dropped
file), infer as before — and say so in the final report, so a wrongly-assigned action item is
attributable to inference rather than read as fact.

### Step 3 — Write the Obsidian note

Write a single file to `$VAULT/meeting-notes/<Title>.md` (Step 0 already created the folder). **`meeting-notes/` must sit at the vault root** — `index.base` filters on
`file.inFolder("meeting-notes")`, which does not match a nested path. Don't put the date in the filename — it lives in the `date:` frontmatter field,
which is the single source of truth and what the Base sorts on. Follow the frontmatter
conventions and template below exactly — they are what make backlinks and the Base work.

### Step 4 — Ensure the Notes Base exists

Check whether a Base already covers the Notes folder. **Use `find`, not a glob.** A `*.base`
pattern that matches nothing makes zsh abort the whole command with `no matches found`, and
`2>/dev/null` does not suppress it — the failure happens in the shell before `ls` ever runs.
The result is indistinguishable from "no Base exists", which leads directly to overwriting one
that does:

```bash
find "$VAULT" -name '*.base' -not -path '*/.claude/*' -not -path '*/.obsidian/*' -not -path '*/.trash/*'
```

The `-not -path '*/.claude/*'` matters: the starter Base ships inside this skill's own
`assets/` directory, which sits inside the vault, so an unpruned `find` always reports a hit
and you would never create a Base on a vault that genuinely lacks one.

On a fresh clone there is no Base yet, so the first run creates it; after that this step is a
no-op and the paragraph below is what applies.

**If a Base already exists, leave it alone** — do not copy, do not "fix" its filter, do not
normalise its formatting. A user's Base holds hand-built views; it is not yours to rewrite.

If none exists, copy the starter in with `-n` so the copy is incapable of clobbering a file the
check may have missed, then point its filter at the real notes folder:

```bash
cp -n "${CLAUDE_SKILL_DIR}/assets/index.base" "$VAULT/index.base"
```

Verify the copy actually landed (`-n` fails silently when the target exists) and confirm the
filter names the folder Step 3 writes to:

```bash
grep -n 'inFolder' "$VAULT/index.base"
```

It must read `file.inFolder("meeting-notes")`. A Base whose filter names a folder that doesn't
exist renders as an empty table — it looks like a broken Base rather than a misconfigured
filter, which is a slow thing to debug. Tell the user to open it once to confirm it renders;
Bases' file format shifts between Obsidian versions.

### Step 5 — Clean up the used input

**Only after the note file has been successfully written**, deal with just the input you used
plus its own intermediate artifacts. By default the user doesn't want a recording or transcript
retained once its note exists, but leave any *other* entry in `$INBOX` alone — it may be an
unprocessed recording waiting for its own run.

**If the user asked for the transcript to be kept** — in any phrasing ("keep the transcript",
"don't delete it", "save the recording", "hang onto that one") — archive instead of deleting.
Move the whole session directory into `$KEEP` under its own name, so the transcript travels
with the session metadata that explains it:

```bash
[ -d "$KEEP" ] || echo "MISSING KEEP: $KEEP"
mv "$INBOX/<session-dir>" "$KEEP/<session-dir>"
```

For a flat file, move the source and everything derived from its basename the same way. `mv`,
not `cp` — `$INBOX` must end the run empty of the input either way, or the next run will treat
it as an unprocessed recording and write the note a second time. If `$KEEP` is missing, stop
and ask rather than creating it or falling back to `rm`; a keep request is the one case where
the input is unrecoverable if this goes wrong. Say in the Step 6 report where it landed.

**Otherwise — the default — delete it.** For a session directory, the whole directory is the
artifact:

```bash
rm -rf "$INBOX/<session-dir>"
```

This takes `session.json` and the ffmpeg logs with it, which is fine: `meetingrec stop` already
appended the measurements it took — clock error, track offsets, peak levels, any warnings — to
`~/.local/state/meetingrec/metrics.jsonl`. Nothing diagnostic is lost by
cleaning up, and there is no need to copy anything out first.

For a flat file, remove the source plus anything derived from the same basename:

```bash
rm -f "$INBOX/<used-file>" "$INBOX/<used-basename>".srt "$INBOX/<used-basename>".wav
```

Never run either before the note is on disk, and never wipe the whole folder. **Delete only
when the user hasn't asked to keep the transcript** — a keep request always wins over the
default, and if it's ambiguous whether they asked, archive to `$KEEP` and say so.

**Verify before deleting.** The note becomes the only artifact — there is no second pass. If
anything in it is worth acting on, confirm it reads correctly against the transcript *first*.
When in doubt, leave the input in place and tell the user; a stale directory in `$INBOX` costs
nothing, and a deleted recording cannot be recovered.

### Step 6 — Report back

Give the user the note's path and a one-line summary (e.g. "3 to-dos, 1 decision").
Don't paste the whole note back into chat — they'll read it in Obsidian.

Add a line only when something affects how much to trust the note:

- **Untagged transcript** (`--mic-only` or a dropped file) — say ownership was inferred rather
  than read from the tracks.
- **Speaker bleed** — say duplicated lines were resolved in favour of `[Them]`, and that
  `--mic-only` avoids it when recording on speakers.
- **`warnings` in `session.json`** — `meetingrec` flags a track that is far shorter than its
  duration implies, one that is digitally silent, or two tracks that started far apart. Relay
  it verbatim. Each of these means part of the meeting was never captured, and the first two
  usually mean a permission problem.
- **`track alignment: UNKNOWN`** — say that ordering between speakers is approximate, so a
  reply may appear before the thing it answered. Ownership tags are still correct; only the
  interleaving is in doubt.
- **A context with no dashboard block** — if the note's `#{context}` has no matching `tags
  include` query in `$VAULT/Tasks.md`, say so and quote the block they'd need to add. Its
  to-dos are written correctly but will not surface anywhere until they do. Don't edit
  `Tasks.md`.

---

## Frontmatter conventions (the one thing to get right)

Put wikilinks **inside** the YAML. A wikilink in a property does double duty: it registers
as a real **backlink** on the person's/company's note *and* it stays a filterable property
the Base can group and sort on. This single convention feeds backlinks, the graph, and the
Base at once.

```yaml
---
date: 2026-06-11            # ISO date — sortable, drives the Base
type: strategy             # open-ended — reuse an existing type or create a new one (see Step 0.5)
context: work              # one lowercase word — every action item below gets #work
company: "[[Acme Health]]"
attendees:
  - "[[Jan Smit]]"
  - "[[Alex Rivera]]"
tags: [meeting, strategy, work]  # always include `meeting`; add the type and the context
---
```

Rules:
- **`context:` is required** and is the source of truth for the action-item tag. It could be
  inferred per-task from the company and attendee wikilinks, but a declared field is the
  reliable version: it is decided once, with the user confirming it, instead of re-guessed on
  every line — and it stays correct on the tasks that mention some *other* company in passing.
  Write it bare (`work`), not `#work`; the `#` is added on the task lines only.
- Always include `meeting` in `tags`, plus the type, plus the `context:` value (so a work
  meeting note is itself tagged `#work`, not just its to-dos). **Tags can't contain colons** —
  Obsidian rejects them as invalid. If the type itself contains a colon (e.g. `1:1`),
  sanitize it for the tag only (e.g. `1-1`) — the `type:` property keeps the original
  value. So a 1:1 gets `type: 1:1` but `tags: [meeting, 1-1, work]`.
- The type vocabulary is open-ended and grows with the vault — don't restrict it to a
  fixed list. See Step 0.5 for how to surface existing types plus a "new type" option.
- People and company are **always** wrapped in `[[ ]]`, even if that note doesn't exist yet
  (Obsidian creates it on first click; the backlink still registers).
- Use the user's real names/casing for the wikilink targets so they don't fragment into
  duplicate notes.
- **No `source:` field** (or any audio/transcript path). The input files are deleted once
  the note is written, so such a path would only dangle. Use exactly the fields below.

---

## Output template

```markdown
---
date: {ISO date}
type: {type}              # existing or newly-created — see Step 0.5
context: {context}        # one lowercase word — see Step 0.5
company: "[[{Company}]]"
attendees:
  - "[[{Name}]]"
tags: [meeting, {type}, {context}]
---

# {Title}

> [!summary] TL;DR
> {3–5 short, one-line bullets: what was learned, decided, what's next. No sub-clauses.}

## To-Do
- [ ] {Task} #{context} 🔺 ⏳ {YYYY-MM-DD}
- [ ] {Task} #{context} ⏫ ⏳ {YYYY-MM-DD} 📅 {YYYY-MM-DD}
- [ ] {Task} #{context} 🔽
*(Only tasks the user owns, five at most. Omit this section entirely if there are none.)*

## Action Items
- {Important follow-up that didn't make the To-Do cut — plain bullet, no checkbox or tag.}
- {Another attendee's commitment the user is waiting on} — [[{Person}]]
*(Overflow only. Omit this section entirely if there are none.)*

## Decisions
- {Specific decision — who decided, what was agreed.}
*(Omit this section entirely if no explicit decisions were made.)*

## Questions to Ask
- {Question the user needs to follow up on} — ask [[{Person}]]
*(Only the user's open questions for others. Omit this section entirely if there are none.)*

## Key Points

### {Topic}
- {Brief, scannable fragment — important or new info only. Skip minor topics entirely.}
```

Notes on the template:
- **Sections are optional except the frontmatter, title, TL;DR, and Key Points.** Omit any
  of To-Do, Action Items, Decisions, or Questions to Ask *entirely* (heading included) when it has no
  content — never emit an empty heading or a "None"/"N/A" placeholder. A note with only a
  TL;DR and Key Points is perfectly valid.
- **At most five to-dos per note**, and only for commitments the user actually made
  out loud. A short list they'll act on beats a complete one they'll ignore — every
  speculative or trivial line dilutes the ones that matter. When in doubt, leave it out;
  it's still in Key Points.
- **Action Items is the overflow section** for what the cap pushed out: plain bullets
  (`-`), never checkboxes, with no `#{context}` tag, no priority and no date emoji. That
  is deliberate — a checkbox or tag here would put it back on the Tasks dashboard and
  undo the cap. Wikilink a person when the item is theirs or aimed at them. If a to-do
  slot frees up, promote the item to **To-Do** rather than duplicating it in both.
- **To-Do items are checkboxes** (`- [ ]`) so they're tickable in Obsidian. These are
  always the user's own tasks — no owner wikilink needed. The trailing emoji are **Tasks
  plugin metadata**, not decoration — the vault aggregates open tasks with `tasks` queries
  that read only the vocabulary below.
- **`Tasks.md` in the vault root is the user's, not this skill's.** It is the dashboard that
  surfaces these to-dos; the repo ships a starter copy, and after that it is hand-maintained.
  The skill **never writes, creates or repairs it** — not even to add a query block for a new
  context (reading it for the Step 6 check is fine). If a context has no block yet, say so in
  the Step 6 report and let the user add it. The same goes for any other dashboard note in
  the vault root.
- **Line order is fixed: text, then `#{context}`, then priority, then `⏳`, then `📅`** —
  `- [ ] Send Jan the pricing model #work ⏫ ⏳ 2026-08-05 📅 2026-08-07`. The plugin
  accepts any order; a consistent one keeps notes diffable. The tag goes at the end of the
  description and before the signifiers, so the plugin reads it as part of the task text.
- **Context tag** — every to-do gets `#{context}` from the `context:` frontmatter field, and
  they all get the *same* one: it describes the meeting, not the individual task. Never
  re-derive it per line.

  **The tag is load-bearing.** `Tasks.md` aggregates by tag (`tags include work`), not by
  folder, so the tag is the *only* thing that puts a to-do on the dashboard. A task written
  without one, or with a misspelt context, is not merely unfiltered — it is invisible
  everywhere, sitting in a note nobody opens again. Never emit a to-do without its tag, and
  reuse an existing context verbatim rather than coining a near-miss variant (`work`, never
  `work-meetings`). The Step 0.5 `grep` exists to make reuse the easy path.
- **Priority** — every to-do gets exactly one:
  `🔺` = time-sensitive or blocking · `⏫` = important, not blocking · `🔽` = nice-to-have /
  long-horizon.
- **Due date** — `📅 YYYY-MM-DD`, only when the meeting names a concrete deadline: the date
  the thing is *owed to someone*.
- **Scheduled date** — `⏳ YYYY-MM-DD`, when the user intends to *work on* it. These are two
  different facts and the plugin treats them as such, so do not write one and call it the
  other. **`⏳` is also the signifier the (optional) Day Planner plugin reads: it schedules
  from scheduled dates only, so a to-do carrying just a `📅` never appears on its timeline** —
  it exists in the vault and is invisible in the day. Whenever the meeting supports a `⏳`, emit it, and
  emit both when the meeting also names a deadline.

  **Emit a `⏳` only when the date is inferable from the meeting itself** — never from today's
  date, never from how urgent the task feels, never from a default like "the next working
  day". The two things that support one:
  - They say when they'll do it → `⏳` on that date ("I'll look at it Wednesday morning").
  - The meeting names a concrete deadline and nothing else → `⏳` on the deadline date itself
    if it's within a couple of days, otherwise the working day before it, so the task surfaces
    with time left to act. Flag it `[note: scheduled date inferred]` so a derived plan is
    never read as something they actually said.

  Anything else — no timing at all, or timing too vague to resolve to a calendar day
  ("sometime this quarter", "before we launch", "soon") — gets **no `⏳`**. Leave the task
  undated rather than inventing a day: a wrong date drops the task onto the wrong day's
  timeline, which is worse than it not being on one, because they'll act on it as if they'd
  planned it there. Priority and the `#{context}` tag still carry it to the Tasks dashboard.
- **Resolving relative dates** — resolve "Thursday", "tomorrow", "end of next week" against
  the `date:` frontmatter value, the *meeting* date, not today's. When timing is vague
  ("sometime this quarter", "before we launch"), emit no date emoji and leave it as prose in
  the task text. If a resolved date is a genuine guess (e.g. "Thursday" spoken on a Thursday),
  keep the emoji and append `[note: …]`.
- **Nothing else on a task line** — no `· High`/`· Medium`/`· Low` words, no 🔴🟡🟢, no other
  emoji, and no tags beyond the single `#{context}`. Wikilinks may still appear inside the
  task *text* when a person is its object (`[[Jan]]`), just never as an owner marker. The
  `✅ YYYY-MM-DD` done date is written by the plugin when the user ticks the box — the skill
  never writes it.
- **Key Points** are brief, scannable fragments — no timestamps, no full sentences.
- `> [!summary]` is a native Obsidian callout — it renders as a highlighted box.

---

## Tone & style

- These are the user's personal notes — capture what's important or new to remember,
  not a comprehensive record for an outside reader. It's fine to skip minor topics
  entirely.
- Don't narrate the user's own statements or actions ("I said...", "I agreed to...") —
  they already know what they said and did. Third person is fine for what *others* said
  or decided (e.g. "Acme is leaning toward enterprise-first pricing.").
- Concise — short bullets over paragraphs, no padding.
- **To-Do** only includes tasks the user clearly owns and explicitly agreed to —
  five maximum. Don't track other attendees' action items, and don't invent tasks the
  transcript merely implies — anything important that overflows goes to **Action Items**.
- **Action Items** is for what matters but isn't a tracked task: overflow past the five,
  uncommitted follow-ups, and commitments by others that the user is waiting on.
- **Questions to Ask** only includes things the user needs to follow up on with
  someone — not general unresolved threads from the meeting.
- Flag ambiguity inline with `[note: …]` rather than guessing (a hard-to-parse name, an
  implied-but-unstated decision).

---

## Edge cases

- **Standup / very short meeting:** collapse Key Points into a single short Summary.
- **No decisions:** omit the Decisions section entirely.
- **Poor audio / inaudible spans:** the transcript will contain gaps; note `[inaudible]`
  inline and flag in the TL;DR if a meaningful chunk was unclear. Suggest a larger model
  (`medium.en`) for a re-run if quality is poor.
- **Non-English meeting:** Whisper can transcribe many languages; produce the notes in the
  language the user is writing in (default English) and note the source language.
- **Wrong environment:** if there's no shell or no Whisper (e.g. the web sandbox), don't
  fake a transcript — explain that this skill needs Claude Code with Whisper installed, and
  offer to proceed if the user pastes a transcript instead.
