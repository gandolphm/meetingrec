#!/usr/bin/env python3
# Writes a new recording's session.json.
# Run by meetingrec (write_session_json); kept out of the bash script so it can be linted
# and tested on its own.
import json, os, datetime
d = os.environ["MR_DIR"]
doc = {
    "title": os.environ["MR_TITLE"],
    "started": datetime.datetime.now(datetime.timezone.utc)
                 .isoformat(timespec="seconds").replace("+00:00", "Z"),
    "tracks": os.environ["MR_TRACKS"].split(","),
    "mic_device": os.environ["MR_MIC"],
    "output_device": os.environ["MR_OUT"],
    "audiotee_sha": os.environ["MR_SHA"],
    "format": {
        "sample_rate": int(os.environ["MR_RATE"]),
        "channels": 1,
        "encoding": "s16le",
    },
}

# What audiotee said it was actually producing. When this disagrees with
# "format" above, the WAV header is wrong but the PCM is fine — these are the
# values needed to re-wrap it.
tap = os.environ.get("MR_TAP", "")
if tap:
    status, rate, ch, bits, flt, dev = (tap.split("|") + [""] * 6)[:6]
    doc["tap"] = {"assertion": status, "device": dev or "unknown"}
    if rate:
        def num(v):
            try:
                return int(float(v))
            except ValueError:
                return v
        doc["tap"]["reported_format"] = {
            "sample_rate": num(rate), "channels": num(ch),
            "bits_per_channel": num(bits), "is_float": flt == "True",
        }
with open(os.path.join(d, "session.json"), "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
