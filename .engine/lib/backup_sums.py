#!/usr/bin/env python3
# Prints a JSON map of each backed-up file to its SHA-256, to check after the update.
# Run by meetingrec (backup_own_files); kept out of the bash script so it can be linted
# and tested on its own.
import hashlib, json, os, sys
root, names = sys.argv[1], open(sys.argv[2], "rb").read().split(b"\0")
sums = {}
for n in filter(None, names):
    path = os.path.join(root.encode(), n)
    if os.path.isfile(path):
        sums[n.decode("utf-8", "surrogateescape")] = hashlib.sha256(open(path, "rb").read()).hexdigest()
json.dump(sums, sys.stdout)
