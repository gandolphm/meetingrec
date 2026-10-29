# meetingrec configuration — sourced by bin/meetingrec.
# Copy to ~/.config/meetingrec/config.sh and edit:
#   mkdir -p ~/.config/meetingrec && cp config.example.sh ~/.config/meetingrec/config.sh

# Path to the audiotee binary (install.sh puts it here; see docs/manual-install.md step 3).
AUDIOTEE_BIN="$HOME/bin/audiotee"

# The audiotee commit in use. If you built it yourself: git -C ~/src/audiotee rev-parse --short HEAD
#
# audiotee publishes no releases or tags, so this is the only version identifier
# that exists. It is written into every session.json — if a recording ever comes
# back as garbage, this hash is what lets you work backward to the code that
# produced it. Keep the working tree pinned to it too (git checkout <sha>), so a
# later pull + rebuild can't change behaviour silently.
#
# In this file (config.example.sh) it's the pin: install.sh and the GitHub Action
# install and build this commit. In your config.sh it's only a fallback: when
# install.sh installed audiotee, the commit it wrote to ~/bin/audiotee.commit wins.
AUDIOTEE_SHA="56ac954"

# SHA-256 of the prebuilt audiotee for that commit, published by the "Build
# audiotee" GitHub Action. install.sh downloads it and refuses any file that
# doesn't match. Empty means no prebuilt copy yet: install.sh builds from source.
# Change it together with AUDIOTEE_SHA, after running the Action for the new commit.
AUDIOTEE_SHA256="43d4f65c4da39c1d6aa2801e19e0b5bcdf382576aa8df61c6d7acba0b17bd4f9"

# The other tools install.sh downloads, so no Mac needs Homebrew. ffmpeg and
# whisper-cli are built by this repo's "Build ffmpeg" and "Build whisper-cli"
# GitHub Actions (tools/build-*.sh); Hammerspoon is the zip its developers
# publish. install.sh refuses any download whose SHA-256 doesn't match. An empty
# SHA-256 means no prebuilt copy yet: install.sh uses Homebrew for that tool.
# Change a version together with its SHA-256, after running the Action for it.
FFMPEG_VERSION="9.0.2"
FFMPEG_SHA256="8f1f0460aa33cea88365f238d60cd12d46485486f0d2119e8ab420a4b28c6821"
WHISPER_CPP_VERSION="v1.9.5"
WHISPER_CLI_SHA256="6db71de03c6266947dbfcf92fea691624bf968b452c058976a2a091ad34b28db"
HAMMERSPOON_VERSION="1.1.1"
HAMMERSPOON_SHA256="11bb1c90faf5427f37c7bd4fe7eab9774ae43e1d5cb020c5b3088dac32849efa"

# Where recordings go. Leave this commented out to use the default, scribe/input/
# inside this repo. The meeting-notes skill looks wherever this points.
# OUTPUT_ROOT="$HOME/somewhere/else"

# Where the notes go: the Obsidian vaults the meeting-notes (NOTES_VAULT) and
# team-notes (TEAM_VAULT) skills write into. Each skill asks once, on its first
# run, and saves the answer here. "" means the default: scribe/ or teamnotes/ in
# this repo, which are vaults already. Any other folder works, such as a vault you
# already use, but not the same one for both. To change it later, edit the line,
# use ○ → Settings, or run: meetingrec config set NOTES_VAULT ~/path/to/vault
# NOTES_VAULT=""
# TEAM_VAULT=""

# Whether the menu bar checks GitHub for a new version once a day and, when
# there is one, relabels its menu item "Update available…". It never updates by
# itself. "off" leaves only ○ → Check for updates…. Also in ○ → Settings.
# AUTO_UPDATE_CHECK="on"

# Use Homebrew's ffmpeg, whisper.cpp and Hammerspoon instead of the pinned copies
# install.sh downloads. "on" gets whatever versions Homebrew currently has, and
# Homebrew asks for your Mac password when it installs itself. To switch, run
#   meetingrec config set USE_HOMEBREW on    (or off)
# then: meetingrec update. Installing with USE_HOMEBREW=1 sets it too.
# USE_HOMEBREW="off"
