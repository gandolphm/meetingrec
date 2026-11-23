#!/usr/bin/env python3
# Prints each backed-up file the update changed or removed, from the sums written before it.
# Run by meetingrec (settle_backup); kept out of the bash script so it can be linted
# and tested on its own.
import hashlib, json, os, sys
root = sys.argv[1]
with open(sys.argv[2]) as f:
    sums = json.load(f)
for name, digest in sorted(sums.items()):
    path = os.path.join(root, name)
    try:
        with open(path, "rb") as f:
            same = hashlib.sha256(f.read()).hexdigest() == digest
    except OSError:
        same = False
    if not same:
        print(name)
