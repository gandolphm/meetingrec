# Whisper name corrections — yours

Your own name corrections. The skill copied this file from `names.local.example.md` the
first time it ran. Git ignores it, so nothing here is ever committed, and updating the repo
never overwrites it. The skill reads it together with `names.shared.md`; if both list
the same name, this file wins.

## Me

The skill fills this row in on its first run by asking your name. It uses it to put your
name in the Whisper prompt and to tell which lines and commitments are yours.

| Heard as                          | Correct spelling | Who                          |
| --------------------------------- | ---------------- | ---------------------------- |
| {common mishearings of your name} | **{Your Name}**  | me — the person running this |

## People, companies and terms

Your company, teammates, customers, partners and jargon. Accented and non-English names
are the worst offenders, followed by company and product names that sound like ordinary
words: e.g. `Kalibra / Calibra` → **Collibra**. When the skill catches a name Whisper got
wrong, it offers to add a row here. You can also add rows yourself.

The `team-notes` skill keeps its own tables in `teamnotes/`. Names you need in both kinds
of notes go in both.

| Heard as | Correct spelling | Who |
| -------- | ---------------- | --- |
