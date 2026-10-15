# Team Notes Vault

Context for transcribing and writing up **team-facing meetings** in this vault:
meetings where the note goes to everyone who was (or should have been) in the room, not just
to the person who recorded it. Your own team uses the `team` profile; any other group
meeting fits under the `other` profile.

**This vault is independent of the `meeting-notes` skill in `../scribe/`.** Never read from
or write to `../scribe/` while working here. That skill handles the user's own personal notes —
a different vault, a different voice, and a different template. One-on-ones and personal
write-ups do not belong here.

"The user" below means whoever is running the skill.

## Profiles

Each meeting type is a profile file in `.claude/skills/team-notes/profiles/`. A profile
holds the team's wikilink and org, the roster with roles, ownership hints, the extra
template sections that team needs, the filename prefix, tag, and Whisper priming terms.

| Profile | Team                            | Org          |
| ------- | ------------------------------- | ------------ |
| `team`  | your team (fill in once)        | your org     |
| `other` | anything else, asked at runtime | —            |

To add a team, copy `other.md` to a new file and fill in the tables. Nothing in the skill
needs editing.

## Who the notes are for

- **Third person, always.** Never "I", "me", or "my". The user is referred to by name, like
  everyone else. What the user said or agreed to is recorded the same way as anyone else's
  contribution.
- **Action items for everyone**, grouped by owner. Not just the user's.
- **Complete enough for an absent member.** Cover every agenda item that was discussed,
  even briefly. Skip only true filler.
- Neutral, factual tone. Record outcomes and reasoning; don't editorialize.

Roles in a profile are **context for the skill, not decoration.** They resolve ownership
when the transcript is ambiguous and are never written into headings, frontmatter, or the
share copy. Anything assigned on that basis gets `[note: owner inferred]`.

Anyone not on the profile's roster who attends is a **guest** — list them under `guests:`
in the frontmatter, wikilinked, with their org or role in the Discussion text if stated.

## Known names / spelling corrections

Whisper mis-transcribes proper nouns. Always correct these before writing a note (the
transcript will contain the wrong spelling). Shared across every profile because people
and terms recur between meetings.

| Heard as                   | Correct spelling    | Who / what                   | Team   |
| -------------------------- | ------------------- | ---------------------------- | ------ |
| {acme health / act me}     | **{Acme Health}**   | {our company}                | {team} |
| {Jon Smith / John Smyth}   | **{Jan Smit}**      | {teammate — role}            | {team} |
| {Kalibra / Calibra}        | **{Collibra}**      | {vendor, comes up often}     | {team} |

Delete the example rows once you have real ones.

Add new names here as they come up (customers, partners, guests, advisors) so future ingests
stay consistent. Names shared with your personal notes belong in `../scribe/.claude/skills/meeting-notes/reference/names.md`
too.
