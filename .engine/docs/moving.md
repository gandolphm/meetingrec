# Moving meetingrec

## Your notes folder

Click **○ → Settings → *Personal notes* → *Choose folder…***, or tell Claude "keep my notes in
~/Documents/My Vault". Team notes and recordings work the same way. Notes already written stay
in the old folder: to bring them along, ask Claude to move them. Then open the new folder in
Obsidian (*Open folder as vault*).

## The meetingrec folder itself

Use `meetingrec move`, not Finder, so everything that points at the folder is updated with it:

```bash
meetingrec move ~/Projects             # ends up in ~/Projects/meetingrec
meetingrec move ~/Projects/recorder    # or pick the new name yourself
```

Like `mv`, an existing folder means "put it inside". It asks before moving, and refuses while
a recording is running.

It updates the `meetingrec`, `scribe` and `teamnotes` commands, the menu bar, any folder
setting that pointed inside meetingrec, and Claude Code's permissions for the folder.
Recordings and notes inside meetingrec move with it. Two things it can't do for you:

- **Obsidian** still looks for a vault in the old place. If it lists one, choose *Open folder
  as vault* and pick the new folder.
- **Claude Code** treats the new folder as a new project: it asks once whether to trust it,
  and earlier sessions are listed under the old folder.

## Already moved it in Finder?

Move it back and use `meetingrec move`. Or run `bash <new folder>/.engine/install.sh`, which
points the menu bar and commands at the new place but not the rest: check
`meetingrec config list` for folders that still name the old one.
