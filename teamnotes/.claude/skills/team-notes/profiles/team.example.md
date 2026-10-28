# Profile: team — your own team

Triggers: "team notes", "team meeting", "team sync", "write up the meeting for the team".

**This is a template.** The first time you pick the `team` profile, the skill copies it to
`team.md` next to this file and fills it in by asking you for the team's name and roster.
Git ignores `team.md`, so your roster is never committed and an update never overwrites it.
After that, edit `team.md` directly when the team changes. Don't edit this template.

| Field           | Value                                           |
| --------------- | ----------------------------------------------- |
| team            | `[[{Team name}]]`                               |
| org             | `[[{Org name}]]`                                |
| share title     | {Team name}                                     |
| filename prefix | {Short team name}                               |
| tag             | {team-tag}                                      |
| meeting types   | regular, standup, strategy, pipeline-review     |

Internal team meetings. Customers, partners, advisors and consultants who join are guests,
not roster members.

## Roster

Wikilink targets are canonical; use them exactly. Keep this list current as the team
changes — `attendees` + `absent` in every note always equal this roster. Roles marked
`[confirm]` should be filled in by whoever knows them.

| Wikilink target    | Goes by    | Role                    |
| ------------------ | ---------- | ----------------------- |
| `[[{Full Name}]]`  | {Nickname} | {Role}                  |
| `[[{Full Name}]]`  | {Nickname} | {Role}                  |

## Ownership hints

Roles are context for resolving ambiguous ownership only. They never appear in headings,
frontmatter, or the share copy.

- {Kind of task, e.g. outbound lists, cold calls} → most likely {Name}.
- {Kind of task, e.g. sales follow-ups, prospect meetings} → most likely {Name}.
- Anything assigned on this basis rather than on what was said gets `[note: owner inferred]`.

## Extra sections

Inserted after **Action Items** and before **Decisions**, in this order. Omit any that are
empty.

```markdown
## Pipeline & Accounts
| Account | Stage | Next step | Owner |
|---|---|---|---|
| {Customer / prospect / partner} | {stage as discussed} | {next step} | [[{Name}]] |

## Upcoming
| What | Date | Lead |
|---|---|---|
| {Call, demo, deadline, conference} | {YYYY-MM-DD or TBD} | [[{Name}]] |
```

Only include an account in **Pipeline & Accounts** if it was actually discussed; record the
stage in the team's own words rather than mapping to a fixed list.

## Priming terms

{Org name}, plus the roster above and any customer, partner or product names that come up
often, plus any from the agenda.
