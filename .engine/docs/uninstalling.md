# Uninstalling meetingrec

**Don't delete the meetingrec folder to start over:** unless you chose folders of your own,
your notes, recordings, kept transcripts and settings are inside it. To repair an install, run
the [install command](../../README.md#quick-install-recommended) again. It keeps everything
you have.

## From the menu bar

Click **○** → *Settings* → *Uninstall meetingrec…*. A window lists what goes; click
**Uninstall**. If you have notes or recordings inside the meetingrec folder, a second window
asks whether to keep them. If the installer added Claude Code, a third asks whether to remove
it. Keeping is always the default: pressing Return in any of these windows never deletes
anything. A notification says when it's done, and the ○ disappears.

## From the terminal

```bash
meetingrec uninstall --dry-run   # only list what would go
meetingrec uninstall
```

It prints the list, then asks the same questions (the Claude Code one only if the installer
added it).

## What it removes

- **meetingrec's own files** in the meetingrec folder, the downloads in
  `~/.local/share/meetingrec` (model, ffmpeg, whisper-cli, audiotee, update backups), your
  settings in `~/.config/meetingrec`, the recording measurements in
  `~/.local/state/meetingrec`, the three commands, and the menu-bar config.
- **Hammerspoon**, only if the installer added it and the menu bar was all it ran, along
  with its preferences (such as the hidden hammer icon). If you had Hammerspoon before, it
  stays, along with your own config and preferences.
- **Claude Code**, only if the installer added it and you say yes. Its settings, sign-in
  and conversation history in `~/.claude` and `~/.claude.json` stay; delete them yourself
  if you don't need them. If you had Claude Code or the Claude app before, or installed it
  yourself, you aren't asked, and it stays.

## What it never touches

Notes folders outside the meetingrec folder (like an Obsidian vault you picked), Apple's
command line tools, Homebrew, and the PATH line in `~/.zprofile`, since other things use them.
If Homebrew installed ffmpeg or whisper.cpp for meetingrec, it tells you the command to remove
them.

## If you kept your notes

They stay in `~/meetingrec/scribe` and `teamnotes`; move or delete them whenever you like. To
install again later, put them somewhere else first, or install into another folder: the
installer won't use a folder that already has things in it.
