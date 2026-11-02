# Profile: other — any other team-facing meeting

Used when the meeting isn't one of the named profiles. Everything a named profile would
supply comes from the user in Step 0.5 instead.

| Field           | Value                                                    |
| --------------- | -------------------------------------------------------- |
| team            | ask — becomes `[[{Team name}]]`                          |
| org             | ask — becomes `[[{Org name}]]`, omit if none             |
| share title     | the team name as given                                   |
| filename prefix | the team name as given                                   |
| tag             | the team name slugified (lowercase, hyphens)             |
| meeting types   | regular, special, or whatever the user names             |

## Roster

Ask for attendees and, if the team is going to recur, offer to save a new profile file
under `profiles/` so the roster and any extra sections are remembered next time.

## Ownership hints

None. Ownership comes only from explicit assignment or self-volunteering; everything else
is `[note: owner inferred]` or goes under `### Needs an owner`.

## Extra sections

None. The shared template alone: TL;DR, Action Items, Decisions, Discussion, Next Meeting.

## Priming terms

The attendee names and any org or project names the user gives.
