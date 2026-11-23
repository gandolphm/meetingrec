#!/usr/bin/env python3
# Prints a JSON map of each backed-up file to its SHA-256, to check after the update.
# Run by meetingrec (backup_own_files); kept out of the bash script so it can be linted
# and tested on its own.
import hashlib, json, os, sys
root = sys.argv[1]
with open(sys.argv[2], "rb") as f:
    names = f.read().split(b"\0")
sums = {}
for n in filter(None, names):
    path = os.path.join(root.encode(), n)
    if os.path.isfile(path):
        with open(path, "rb") as f:
            sums[n.decode("utf-8", "surrogateescape")] = hashlib.sha256(f.read()).hexdigest()
json.dump(sums, sys.stdout)
