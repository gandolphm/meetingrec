#!/usr/bin/env python3
"""Exit 0 if the file is a session.json that meetingrec wrote, 1 if not.

    session_json_ok.py <path to session.json>

`meetingrec start` has written "started" and "tracks" (mic, and system unless
--mic-only) into every session.json since its first version. Another app's
file of the same name, or an empty {}, doesn't count: clear-input --delete
removes a whole folder on the strength of this answer.
"""

import json
import sys


def ok(path):
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError):
        return False
    if not isinstance(doc, dict) or not isinstance(doc.get("started"), str):
        return False
    tracks = doc.get("tracks")
    return (isinstance(tracks, list) and bool(tracks)
            and all(t in ("mic", "system") for t in tracks))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: session_json_ok.py <session.json>")
    sys.exit(0 if ok(sys.argv[1]) else 1)
