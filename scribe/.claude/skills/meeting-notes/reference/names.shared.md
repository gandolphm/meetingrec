# Whisper name corrections — shared

Whisper reliably mis-transcribes proper nouns. The skill reads this table together with
your own `names.local.md` and uses both for two jobs:

1. **Before transcribing** — feed the correct spellings into the priming prompt (Step 1).
2. **Before writing** — correct any that still came through wrong (Step 2).

**This table is empty on purpose, and stays empty in the public repo.** It exists for teams
that fork meetingrec: the fork's maintainer adds the names everyone on the team needs
(colleagues, customers, the company's own jargon) and commits them, and each member gets
them with their next update. Git tracks this file, so anything written here is published
with the repo.

**Your own names never go here.** They go in `names.local.md` next to this file, which git
ignores. The skill creates that file the first time it runs and adds names to it as you go.
If both files list the same name, yours wins.

| Heard as | Correct spelling | Who |
| -------- | ---------------- | --- |
