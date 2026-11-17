#!/usr/bin/env python3
# Prints the ID of the Antigravity project that holds a folder (see meetingrec antigravity-project); exits 1 if none.
# Run by meetingrec (antigravity-project); kept out of the bash script so it can be linted
# and tested on its own.
import glob, json, os, sys
from urllib.parse import unquote, urlparse

want = os.path.realpath(sys.argv[1])
found = []
for path in glob.glob(os.path.join(sys.argv[2], "*.json")):
    try:
        with open(path) as f:
            project = json.load(f)
        resources = project["projectResources"].get("resources") or []
    except (OSError, ValueError, KeyError, AttributeError, TypeError):
        continue
    uris = []
    for r in resources:
        if not isinstance(r, dict):
            continue
        uris.append(r.get("folderUri"))
        uris += [v.get("folderUri") for v in r.values() if isinstance(v, dict)]
    for uri in uris:
        if not isinstance(uri, str):
            continue
        u = urlparse(uri)
        if u.scheme != "file" or u.netloc not in ("", "localhost"):
            continue
        if os.path.realpath(unquote(u.path)) == want and project.get("id"):
            found.append((os.path.getmtime(path), str(project["id"])))
            break
if not found:
    sys.exit(1)
print(max(found)[1])
