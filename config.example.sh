# meetingrec configuration — sourced by bin/meetingrec.
# Copy to ~/.config/meetingrec/config.sh and edit:
#   mkdir -p ~/.config/meetingrec && cp config.example.sh ~/.config/meetingrec/config.sh

# Path to the audiotee binary (see "Install audiotee" in the README).
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

# Where recordings go. Leave this commented out to use the default, scribe/input/
# inside this repo — which is where the meeting-notes skill looks for them.
# OUTPUT_ROOT="$HOME/somewhere/else"
