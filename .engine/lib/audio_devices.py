#!/usr/bin/env python3
# The default input and output devices, from system_profiler's JSON on stdin: "<input>|<output>".
# Run by meetingrec (audio_devices); kept out of the bash script so it can be linted
# and tested on its own.
import json, sys
try:
    items = json.load(sys.stdin).get("SPAudioDataType", [])
except Exception:
    print("unknown|unknown"); sys.exit(0)
def walk(nodes):
    for it in nodes:
        yield it
        for sub in (it.get("_items") or []):
            yield sub
inp = out = "unknown"
for it in walk(items):
    name = it.get("_name", "unknown")
    if "coreaudio_default_audio_input_device" in it:  inp = name
    if "coreaudio_default_audio_output_device" in it: out = name
print(f"{inp}|{out}")
