# Your settings — team notes

Yours alone. The skill copied this file from `personal.example.md` the first time it ran.
Git ignores it, so nothing here is ever committed, and updating meetingrec never overwrites
it. The skill reads it on every run, together with `shared.md`; where they disagree, this
file wins. Settings for one team only belong in that team's profile instead.

## Names

Customers, partners, guests, advisors and jargon that Whisper gets wrong, so future
write-ups stay consistent: e.g. `Kalibra / Calibra` → **Collibra**. At the end of each run
the skill offers to add the names it had to correct. You can also add rows yourself.

The `meeting-notes` skill in `scribe/` keeps its own settings. Names you need in both kinds
of notes go in both.

| Heard as | Correct spelling | Who / what | Team |
| -------- | ---------------- | ---------- | ---- |

## Rules

How you want team notes written, for every team, in plain English, one bullet each. They
take priority over the skill's own defaults; a rule in a team's profile takes priority over
these for that team. Say "from now on…" or "remember that…" while writing up a meeting and
Claude adds a rule here or to the profile; at the end of a run it may also suggest rules
based on the corrections you made. You can edit or delete any rule.

A few things can't be changed by a rule, because other parts of meetingrec depend on them:
recordings are never deleted before both notes are saved, the note's frontmatter fields and
action-item format stay as the Action Items page expects, and Claude never edits the
skill's own files.

Examples, not active (anything inside `<!-- -->` is ignored):
<!--
- Always list guests' organisations in the Discussion section.
- Write dates in the share copy as "Wed 10 Sep", not 2026-09-10.
-->
