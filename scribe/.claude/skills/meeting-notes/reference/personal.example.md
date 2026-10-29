# Your settings — personal notes

Yours alone. The skill copied this file from `personal.example.md` the first time it ran.
Git ignores it, so nothing here is ever committed, and updating meetingrec never overwrites
it. The skill reads it on every run, together with `shared.md`; where they disagree, this
file wins.

## Me

The skill fills this row in on its first run by asking your name. It uses it to put your
name in the Whisper prompt and to tell which lines and commitments are yours.

| Heard as                          | Correct spelling | Who                          |
| --------------------------------- | ---------------- | ---------------------------- |
| {common mishearings of your name} | **{Your Name}**  | me — the person running this |

## Names

Your company, teammates, customers, partners and jargon that Whisper gets wrong. Accented
and non-English names are the worst offenders, followed by company and product names that
sound like ordinary words: e.g. `Kalibra / Calibra` → **Collibra**. At the end of each run
the skill offers to add the names it had to correct. You can also add rows yourself.

The `team-notes` skill keeps its own settings in `teamnotes/`. Names you need in both kinds
of notes go in both.

| Heard as | Correct spelling | Who |
| -------- | ---------------- | --- |

## Rules

How you want your notes written, in plain English, one bullet each. They take priority over
the skill's own defaults. Say "from now on…" or "remember that…" while writing up a meeting
and Claude adds a rule here; at the end of a run it may also suggest rules based on the
corrections you made. You can edit or delete any rule.

A few things can't be changed by a rule, because other parts of meetingrec depend on them:
recordings are never deleted before the note is saved, the note's frontmatter fields and
to-do format stay as the dashboards expect, and Claude never edits the skill's own files.

Examples, not active (anything inside `<!-- -->` is ignored):
<!--
- Calls with Acme Health get the context `acme` instead of `work`.
- Never use the tag `#job` on a meeting to-do.
- Keep Key Points to five bullets at most.
-->
