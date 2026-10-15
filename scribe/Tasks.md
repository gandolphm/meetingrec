---
tags:
  - todo
---

# Tasks

Every open to-do from your meeting notes, aggregated by the Tasks plugin. Tick a box here
and it updates the source note. To-dos are matched by their `#context` tag; add a block
below when you start using a new context.

## Overdue & due soon

```tasks
not done
path includes meeting-notes
due before in two weeks
sort by due
sort by priority
short mode
```

## Work — all open

```tasks
not done
tags include work
sort by priority
sort by scheduled
sort by due
```

## Done in the last two weeks

```tasks
done after 14 days ago
path includes meeting-notes
sort by done reverse
short mode
limit 100
```
