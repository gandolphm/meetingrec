# meetingrec configuration — sourced by bin/meetingrec.
# Copy to ~/.config/meetingrec/config.sh and edit:
#   mkdir -p ~/.config/meetingrec && cp config.example.sh ~/.config/meetingrec/config.sh

# Path to the audiotee binary you built (see "Install audiotee" in the README).
AUDIOTEE_BIN="$HOME/bin/audiotee"

# The audiotee commit you built, from: git -C ~/src/audiotee rev-parse --short HEAD
#
# audiotee publishes no releases or tags, so this is the only version identifier
# that exists. It is written into every session.json — if a recording ever comes
# back as garbage, this hash is what lets you work backward to the code that
# produced it. Keep the working tree pinned to it too (git checkout <sha>), so a
# later pull + rebuild can't change behaviour silently.
AUDIOTEE_SHA="56ac954"

# Where recordings go. Leave this commented out to use the default, scribe/input/
# inside this repo — which is where the meeting-notes skill looks for them.
# OUTPUT_ROOT="$HOME/somewhere/else"
