# What the installer does

The details behind the [quick install](../../README.md#quick-install-recommended). To do the
same thing one step at a time, use the [manual install](manual-install.md).

## What it downloads

The script goes through these steps and skips any that are already done:

| Step | Downloaded from |
| --- | --- |
| Xcode Command Line Tools (git and python3) | Apple, via `xcode-select --install` |
| meetingrec, cloned to `~/meetingrec` | this GitHub repo |
| Whisper `small.en` model (465 MB) | [Hugging Face](https://huggingface.co/ggerganov/whisper.cpp) |
| ffmpeg and whisper.cpp's `whisper-cli`, at pinned versions | this repo's [releases](https://github.com/gandolphm/meetingrec/releases), built by GitHub Actions ([ffmpeg](../../.github/workflows/build-ffmpeg.yml), [whisper-cli](../../.github/workflows/build-whisper.yml)) from [FFmpeg's](https://github.com/FFmpeg/FFmpeg) and [whisper.cpp's](https://github.com/ggml-org/whisper.cpp) source |
| audiotee, at the pinned commit | this repo's releases, built by a [GitHub Action](../../.github/workflows/build-audiotee.yml) from [audiotee's source](https://github.com/makeusabrew/audiotee) |
| Hammerspoon | [its own releases](https://github.com/Hammerspoon/hammerspoon/releases), signed by its developers |
| Claude Code, if you say yes when asked | Anthropic's installer, `claude.ai/install.sh` |

The model, ffmpeg, `whisper-cli`, audiotee and Hammerspoon are each checked against a SHA-256
fingerprint pinned in [config.example.sh](../config.example.sh) (the model's is in
[install.sh](../install.sh)), and refused if they don't match. Apple's tools, meetingrec
itself and Claude Code come straight from the sources above. The model, ffmpeg, `whisper-cli`
and audiotee all go in `~/.local/share/meetingrec`, where only meetingrec uses them: they
never replace other copies you might have, and
[uninstalling](../../README.md#uninstalling) removes them in one go.

## The one change to ffmpeg

meetingrec's ffmpeg is FFmpeg's own source with one change, about 50 lines in the file that
reads the microphone:
[ffmpeg-avfoundation-audio-queue.patch](../tools/ffmpeg-avfoundation-audio-queue.patch).
Without it, ffmpeg silently loses about a tenth of the audio from a microphone running at
44.1 or 48 kHz, which is the MacBook's own microphone and sometimes AirPods. The patch file
says how at its top, and [build-ffmpeg.sh](../tools/build-ffmpeg.sh) is the whole build. Each
release carries the patch beside the program, and GitHub's record that this repo's Action
built it: `gh attestation verify ffmpeg --repo gandolphm/meetingrec`.

Homebrew's ffmpeg (`USE_HOMEBREW=1`) doesn't have the change. meetingrec still measures the
loss with it, warns about it and keeps the transcript's timing right, but the missing audio
stays missing.

## What else it changes

It also writes `~/.config/meetingrec/config.sh` and the Hammerspoon config, starts
Hammerspoon, links the `meetingrec`, `scribe` and `teamnotes` commands into `~/.local/bin`,
and adds `~/.local/bin` to your PATH in `~/.zprofile` if it isn't there already. Hammerspoon
then opens at login, so the **○** is there after a restart. It doesn't change anything else.

## Read the script before running it

[Read it on GitHub](../install.sh), or use these three commands instead of the one-line
install, to download it, look through it, then run it:

```bash
curl -fsSL https://raw.githubusercontent.com/gandolphm/meetingrec/main/.engine/install.sh -o install.sh
less install.sh      # press q to quit
bash install.sh
```

## Hide Hammerspoon's own icon

Hammerspoon puts a hammer icon in the menu bar next to meetingrec's **○**, and meetingrec
doesn't need it. Click the hammer → *Preferences…* → untick **Show menu icon**. The **○**
stays, and ○ → *Reload config* still works. To get the hammer back, open Hammerspoon from
Applications: its window opens, and *Hammerspoon → Preferences…* is in the menu bar at the
top of the screen.
