# Whisper name corrections

Whisper reliably mis-transcribes these proper nouns. Two jobs:

1. **Before transcribing** — feed the correct spellings into the priming prompt (Step 1).
2. **Before writing** — correct any that still came through wrong (Step 2).

## Me

**Fill this in once after cloning.** The skill writes *your* notes: it uses this row to put
your name in the Whisper prompt and to tell which lines and commitments are yours.

| Heard as                          | Correct spelling | Who                          |
| --------------------------------- | ---------------- | ---------------------------- |
| {common mishearings of your name} | **{Your Name}**  | me — the person running this |

## People, companies and terms

Seed this with your company, your teammates, and the customers, partners and jargon that
come up often. Accented and non-English names are the worst offenders, followed by company
and product names that sound like ordinary words. Delete the example rows once you have
real ones.

| Heard as                   | Correct spelling    | Who                          |
| -------------------------- | ------------------- | ---------------------------- |
| {acme health / act me}     | **{Acme Health}**   | {our company}                |
| {Jon Smith / John Smyth}   | **{Jan Smit}**      | {teammate — role}            |
| {Kalibra / Calibra}        | **{Collibra}**      | {vendor, comes up often}     |

Add new names here as they come up so future ingests stay consistent. This file is the only
copy the `meeting-notes` skill reads; the `team-notes` skill keeps its own table in
`teamnotes/CLAUDE.md` — add shared names to both.
