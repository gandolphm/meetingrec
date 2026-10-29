# Manual install

The same result as the [quick install](../README.md#quick-install-recommended), one step at
a time. Use this if you'd rather not run a script from the internet, or you want to see
exactly what gets downloaded.

Do the steps in order. Every command runs in **Terminal**. In the expected outputs, `you`
stands for your Mac username, and dates, times, sizes and version numbers will differ.

When you've finished, go back to the README and [set up Obsidian](../README.md#set-up-obsidian).

## 1. Install the command-line tools

**Xcode Command Line Tools** (provides git and python3, plus Swift for building audiotee
yourself in step 3B):
```bash
xcode-select --install
```
Expected, if they're not installed yet:
```text
xcode-select: note: install requested for command line developer tools
```
A window then opens. Click *Install*, agree, and wait for it to finish (5–15 minutes).
If instead you get a message saying the command line tools are already installed, move on.

**Homebrew**, if you don't have it ([brew.sh](https://brew.sh)):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
It asks for your Mac password, then shows what it will install and asks you to press
Enter. It ends with:
```text
==> Installation successful!
...
==> Next steps:
- Run these commands in your terminal to add Homebrew to your PATH:
    echo >> /Users/you/.zprofile
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/you/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
```
Run the lines it prints under *Next steps*. They print nothing. Then close Terminal and
open it again. To check:
```bash
brew --version
```
Expected:
```text
Homebrew 4.6.0
```

**ffmpeg and Whisper:**
```bash
brew install ffmpeg whisper.cpp
```
This prints a lot and takes a few minutes. It ends with lines like:
```text
==> Summary
🍺  /opt/homebrew/Cellar/whisper-cpp/1.8.0: 45 files, 12MB
```
To check:
```bash
which ffmpeg whisper-cli
```
Expected:
```text
/opt/homebrew/bin/ffmpeg
/opt/homebrew/bin/whisper-cli
```

**The Whisper model** (`small.en`, 465 MB):
```bash
mkdir -p ~/.whisper-models
curl -L -o ~/.whisper-models/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
```
`mkdir` prints nothing. `curl` shows a progress table while it downloads. When it
finishes, the `% Total` column reads `100` and the size is `465M`. To check the file isn't
damaged:
```bash
shasum -a 256 ~/.whisper-models/ggml-small.en.bin
```
Expected:
```text
c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d  /Users/you/.whisper-models/ggml-small.en.bin
```
If the long number is different, delete the file and download it again.

**Claude Code:**
```bash
curl -fsSL https://claude.ai/install.sh | bash
```
Expected: it ends by saying Claude Code was installed successfully. If it also tells you
to add `~/.local/bin` to your PATH, run the command it shows. Then open a new Terminal
window and run:
```bash
claude
```
Expected: Claude Code starts and asks you to choose a theme, then to log in. Follow the
prompts. When you reach the `>` prompt, type `/exit`. See the
[Claude Code docs](https://docs.claude.com/en/docs/claude-code/overview) for other ways to
install it.

## 2. Clone this repo

Clone it wherever you like. Nothing in the tool depends on where it lives. Commands in
this guide that start with `bin/`, `scribe/` or `teamnotes/` are run **from the repo
folder** (the one containing the README). `<repo>` means that folder's full path.

```bash
git clone https://github.com/gandolphm/meetingrec.git   # creates a folder called meetingrec
cd meetingrec
chmod +x bin/*
pwd                            # this is your <repo> path; note it down
```
Expected (`cd` and `chmod` print nothing):
```text
Cloning into 'meetingrec'...
remote: Enumerating objects: ...
Receiving objects: 100% ..., done.
Resolving deltas: 100% ..., done.
/Users/you/meetingrec
```

## 3. Install audiotee (system-audio capture)

[audiotee](https://github.com/makeusabrew/audiotee) is a small open-source tool. It
captures the audio your Mac is playing, which during a call is everyone else's voice.
Use the commit this tool was tested with, `56ac954`. Either download the copy this repo
publishes (**A**) or build it yourself (**B**). Both give you the same program.

**A. Download it.** It's built from audiotee's source by a
[GitHub Action](../.github/workflows/build-audiotee.yml) in this repo:
```bash
mkdir -p ~/bin
curl -fL --progress-bar -o ~/bin/audiotee https://github.com/gandolphm/meetingrec/releases/download/audiotee-56ac954/audiotee
chmod +x ~/bin/audiotee
shasum -a 256 ~/bin/audiotee
grep AUDIOTEE_SHA256 config.example.sh
```
Expected: a download progress bar, then the same 64-character code twice:
```text
###################################################################### 100.0%
<64-character code>  /Users/you/bin/audiotee
AUDIOTEE_SHA256="<the same 64-character code>"
```
If the two codes differ, the download is damaged: delete it with `rm ~/bin/audiotee` and
use **B** instead.

**B. Build it from source:**

```bash
mkdir -p ~/src ~/bin
git clone https://github.com/makeusabrew/audiotee.git ~/src/audiotee
git -C ~/src/audiotee checkout 56ac954
cd ~/src/audiotee && swift build -c release && cd -
cp ~/src/audiotee/.build/release/audiotee ~/bin/audiotee
```
The build takes a minute or two. Expected (`mkdir` and `cp` print nothing):
```text
Cloning into '/Users/you/src/audiotee'...
...
Note: switching to '56ac954'.
...
HEAD is now at 56ac954 ...
Building for production...
...
Build complete! (52.31s)
/Users/you/meetingrec
```
The last line is `cd -` taking you back to the repo folder.

Check that the binary is in place:
```bash
ls -l ~/bin/audiotee
```
Expected (the `x`s in `-rwxr-xr-x` mean it can run):
```text
-rwxr-xr-x  1 you  staff  412496 Oct 26 14:02 /Users/you/bin/audiotee
```

## 4. Configure the recorder

```bash
mkdir -p ~/.config/meetingrec
cp config.example.sh ~/.config/meetingrec/config.sh
```
Expected: no output.

The defaults work if you followed steps 2 and 3 exactly. If you put audiotee somewhere
else, edit `AUDIOTEE_BIN` in `~/.config/meetingrec/config.sh`.

## 5. Do a test recording and grant permissions

macOS asks for permission the first time each app records audio. Do a short test run from
Terminal so you can answer the prompts now, not at the start of a real call:

```bash
bin/meetingrec start "test"
```
Allow the **Microphone** and **System Audio Recording** prompts. Expected:
```text
recording: /Users/you/meetingrec/scribe/input/2026-10-26T14-05_test
  tracks: mic,system
  mic:    MacBook Pro Microphone
  output: MacBook Pro Speakers (do not change it mid-call)
```
The `mic` and `output` lines show your own devices, e.g. your headphones.

Play a YouTube video and talk for 15 seconds, then run:

```bash
bin/meetingrec stop
```
`stop` reports what it captured. Expected:
```text
stopped after 0m18s
  /Users/you/meetingrec/scribe/input/2026-10-26T14-05_test
  -rw-r--r--  1 you  staff  576044 Oct 26 14:05 /Users/you/meetingrec/scribe/input/2026-10-26T14-05_test/mic.wav
  -rw-r--r--  1 you  staff  450604 Oct 26 14:05 /Users/you/meetingrec/scribe/input/2026-10-26T14-05_test/system.wav
  format-check: audiotee metadata OK (ok|16000|1|16|...)
  format-check: system OK (32000 B/s)
  format-check: mic OK (32000 B/s)
```
The `B/s` numbers can be a little off 32000. The `format-check` lines can be in a different
order.

If it prints a line starting with **WARNING** saying a track is silent, a permission is
missing. Fix it in **System Settings → Privacy & Security**:
- **Microphone** → turn on Terminal.
- **Screen & System Audio Recording** → in the *System Audio Recording Only* list, add
  and turn on Terminal.

Then quit and reopen Terminal and try again.

Delete the test session afterwards:
```bash
rm -rf scribe/input/*_test
```
Expected: no output.

## 6. Install Hammerspoon (menu-bar button)

[Hammerspoon](https://www.hammerspoon.org) is a free macOS automation app. Here it adds a
small **○** button to your menu bar that starts and stops recordings. It's optional, since
the terminal commands work too, but it's much easier mid-meeting.

1. **Install it:**
   ```bash
   brew install --cask hammerspoon
   ```
   Expected, at the end:
   ```text
   🍺  hammerspoon was successfully installed!
   ```
   You can also download it from [hammerspoon.org](https://www.hammerspoon.org) and drag
   it into Applications.
2. **Install the config.** Run this **from the repo folder**. It copies the config and
   fills in where you cloned the repo:
   ```bash
   mkdir -p ~/.hammerspoon
   sed "s|^local REPO = .*|local REPO = \"$PWD\"|" hammerspoon/init.lua > ~/.hammerspoon/init.lua
   ```
   Expected: no output. To check the path was filled in:
   ```bash
   grep '^local REPO' ~/.hammerspoon/init.lua
   ```
   Expected (your repo path from step 2):
   ```text
   local REPO = "/Users/you/meetingrec"
   ```
   If you already have your own `~/.hammerspoon/init.lua`, don't overwrite it. Write to
   `~/.hammerspoon/meetingrec.lua` instead (same command, different last path), then add
   this line to your `init.lua`:
   ```lua
   require("meetingrec")
   ```
   If you ever move the repo, run the command again.
3. **Open Hammerspoon** from Applications. It asks for **Accessibility** access. You can
   **decline**: this config doesn't use it. A **○** appears in the menu bar. The config
   also turns on *Launch Hammerspoon at login*, so it comes back after a restart.
   If Hammerspoon was already running, click its menu-bar icon → *Reload Config*.
4. **Grant Hammerspoon its own permissions.** macOS gives permissions to the app that
   launches the recording, so Terminal's permissions don't carry over. Start a test
   recording from the ○ menu, then allow the prompts. Stop it from the menu after 15
   seconds. If a notification says *check this recording*, a permission is missing: add
   **Hammerspoon** under **Microphone** and **System Audio Recording Only** in System
   Settings (see step 5). Delete the test session afterwards, as in step 5.

If the button misbehaves, check `~/.hammerspoon/meetingrec.log`.

## 7. Add the commands (optional)

The quick install links `meetingrec`, `scribe` and `teamnotes` into `~/.local/bin`, so they
work from any folder. To do the same, run this **from the repo folder**:
```bash
mkdir -p ~/.local/bin
ln -s "$PWD/bin/meetingrec" "$PWD/bin/scribe" "$PWD/bin/teamnotes" ~/.local/bin/
```
Expected: no output. Open a new Terminal window, then check:
```bash
which scribe
```
Expected:
```text
/Users/you/.local/bin/scribe
```
If it prints nothing, `~/.local/bin` isn't on your PATH: run
`echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile` and open a new window. Without
these commands, use `<repo>/bin/meetingrec`, and start note-writing from the ○ menu or with
`cd <repo>/scribe && claude`.

Now go back to the README and [set up Obsidian](../README.md#set-up-obsidian).
