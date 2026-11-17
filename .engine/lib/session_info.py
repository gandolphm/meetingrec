#!/usr/bin/env python3
# Prints what meetingrec measured for a recording, for the skills (see meetingrec session-info).
# Run by meetingrec (session-info); kept out of the bash script so it can be linted
# and tested on its own.
import datetime, json, os, sys
d = sys.argv[1]
name = os.path.basename(os.path.normpath(d))
try:
    doc = json.load(open(os.path.join(d, "session.json")))
except (OSError, ValueError):
    doc = None
if doc is None:
    # A half-written session still gets a note: go by the audio files.
    tracks = [t for t in ("mic", "system") if os.path.exists(os.path.join(d, t + ".wav"))]
    print("NO SESSION FILE")
    print("TITLE=" + name.split("_", 1)[-1].replace("-", " "))
    print("DATE=" + name[:10])
    print("TRACKS=" + ",".join(tracks))
    sys.exit(0)
started = doc.get("started") or ""
try:
    date = (datetime.datetime.fromisoformat(started.replace("Z", "+00:00"))
            .astimezone().date().isoformat())
except ValueError:
    date = name[:10]
print("TITLE=" + (doc.get("title") or name.split("_", 1)[-1].replace("-", " ")))
print("DATE=" + date)
print("TRACKS=" + ",".join(doc.get("tracks") or []))
for track, c in (doc.get("checks") or {}).items():
    if not isinstance(c, dict):
        continue
    peak = c.get("peak_dbfs")
    print(f"TRACK {track}: peak {peak} dBFS, {c.get('audio_seconds')}s")
    # Healthy speech peaks around -5 to -30; below -60 is digital silence.
    if peak is None or peak < -60:
        print(f"SILENT {track}")
for w in doc.get("warnings") or []:
    print("WARNING " + w)
