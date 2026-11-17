#!/bin/bash
#
# For the menu bar's "Write up notes…" when the notes agent isn't plain Claude
# Code, which has links of its own. macOS opens a .command file in a new Terminal
# window and runs it there, with no permission to grant.
exec "$(dirname "$0")/teamnotes"
