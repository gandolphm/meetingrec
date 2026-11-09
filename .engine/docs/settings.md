# Settings in detail

Most changes are a sentence to Claude or a click in **○ → Settings**: see
[Make it yours](../../README.md#make-it-yours). This page covers where your settings live and
the few that need more than that.

## Where everything is saved

| What | File |
| --- | --- |
| Where notes and recordings go | `~/.config/meetingrec/config.sh` |
| Transcripts you kept, personal and team | `scribe/transcripts/`, in the meetingrec folder even if your notes go to a vault of your own. A meetingrec recording gets a folder with the transcript in `merged.txt` (`mic.srt` for a mic-only recording) |
| Your name, names and rules for personal notes | `scribe/settings/personal.md` |
| Names and rules for team notes, for every team | `teamnotes/settings/personal.md` |
| One team's name, roster, sections and rules | `teamnotes/settings/profiles/<team>.md` |

## How rules work

Rules are plain English, one bullet each, and take priority over the skills' defaults. A
team's rules beat your general ones for that team. A few things can't be changed by a rule,
because other parts of meetingrec depend on them: recordings aren't deleted before the note
is saved, notes keep the format the notes table and to-do pages read, and Claude never edits
the skills' own files. At the end of each write-up Claude offers to remember the names it
corrected and any preferences your corrections suggested; you choose which to keep.

## Files to leave as they are

Next to your files are tracked ones that must stay as they are, because git publishes them
with the repo:

- **Templates** (`*.example.md`): the starting point the skills copy your files from.
- **`shared.md`**: empty in this repo, and it should stay that way. It's only for a team
  that [forks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo)
  meetingrec: the fork's maintainer fills it with the names and rules everyone on the team
  needs and commits them, so each member gets them on their next update. Never put anything
  in it in your own copy of this repo.

## A new context on the to-do dashboard

To-dos are tagged with the note's `context` (`work` unless your rules say otherwise). If you
start using another, add a `tags include <context>` block to `Tasks.md` in your notes vault.
Claude points this out when it happens.

## Whisper model

`small.en` is the default. For poor audio, download `medium.en` (1.5 GB), then ask the skill
to re-run with it:

```bash
curl -L -o ~/.local/share/meetingrec/models/ggml-medium.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin
```

Expected: a progress table that ends at `100` with a size of about `1462M`.
