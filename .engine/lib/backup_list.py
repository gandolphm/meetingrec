#!/usr/bin/env python3
# Filters git's NUL-separated list of the user's own files (stdin) down to what an update backs up.
# Run by meetingrec (backup_own_files); kept out of the bash script so it can be linted
# and tested on its own.
import sys
skip = ("scribe/input/", "teamnotes/input/")
for p in sys.stdin.buffer.read().split(b"\0"):
    s = p.decode("utf-8", "surrogateescape")
    if not s or s.startswith(skip) or s.endswith(".DS_Store") or "/__pycache__/" in s:
        continue
    sys.stdout.buffer.write(p + b"\0")
