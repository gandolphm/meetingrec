---
tags:
  - todo
---

# Action Items

Every open action item across every team's meeting notes, aggregated by the Tasks
plugin. Owners come from the `###` heading each task sits under. Tick a box here and it
updates the source note.

## Overdue & due soon

```tasks
not done
path includes meeting-notes
due before in two weeks
sort by due
sort by priority
short mode
```

## All open — by owner

```tasks
not done
path includes meeting-notes
group by heading
sort by priority
sort by due
```

## All open — by meeting

```tasks
not done
path includes meeting-notes
group by filename reverse
sort by priority
```

## Done in the last two weeks

```tasks
done after 14 days ago
path includes meeting-notes
sort by done reverse
short mode
limit 100
```
