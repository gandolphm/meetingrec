#!/usr/bin/env python3
# The format audiotee says it captured, from its log: ok|rate|channels|bits|float|device, or mismatch|… / unknown|.
# Run by meetingrec (audiotee_metadata); kept out of the bash script so it can be linted
# and tested on its own.
import json, os, sys
want = int(os.environ["MR_RATE"])
meta = None
try:
    with open(os.environ["MR_LOG"], encoding="utf-8", errors="replace") as log:
        for line in log:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if msg.get("message_type") == "metadata" and msg.get("data"):
                meta = msg["data"]
                break
except OSError:
    pass
if not meta:
    print("unknown|||||"); sys.exit(0)
rate  = meta.get("sample_rate")
ch    = meta.get("channels_per_frame")
bits  = meta.get("bits_per_channel")
flt   = meta.get("is_float")
dev   = meta.get("device_name") or "unknown"
ok = (int(rate or 0) == want and int(ch or 0) == 1
      and int(bits or 0) == 16 and not flt)
print(f"{'ok' if ok else 'mismatch'}|{rate}|{ch}|{bits}|{flt}|{dev}")
