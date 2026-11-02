#!/usr/bin/env python3
"""make_share_copy.py — turn a vault note into a plain-Markdown copy for the team.

    make_share_copy.py <vault-note.md> [--out-dir share]

The vault note is written for Obsidian: YAML frontmatter, [[wikilinks]], a callout, and
Tasks-plugin emoji. None of that survives a paste into email, Slack, or a Google
Doc. This script produces `share/<same basename>.md` with those replaced by plain text, and
leaves everything else byte-for-byte alone, so the two files never say different things.

Transforms, in order:
  1. Frontmatter → a header block: "<team> — <date>" (team read from `team:`, org from
     `org:` if present), then Present, Absent, Guests.
  2. [[Target]] → Target;  [[Target|Alias]] → Alias.
  3. `> [!summary] TL;DR` callout → **TL;DR** with the bullets un-quoted.
  4. Tasks emoji → words: 🔺 (urgent), ⏫ (high priority), 🔽 (low priority),
     📅 YYYY-MM-DD → "— due Mon D".
  5. `[note: …]` flags are kept verbatim and listed on stderr as a warning, so they get
     resolved before the note is sent.

Exit codes: 0 ok · 1 bad input · 2 written, but unresolved [note: …] flags remain.
"""

import argparse
import datetime
import os
import re
import sys

WIKILINK = re.compile(r"\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]")
DUE = re.compile(r"\s*📅\s*(\d{4}-\d{2}-\d{2})")
NOTE_FLAG = re.compile(r"\[note:[^\]]*\]")
PRIORITY = {"🔺": "(urgent)", "⏫": "(high priority)", "🔼": "(medium priority)",
            "🔽": "(low priority)", "⏬": "(lowest priority)"}


def die(msg):
    sys.exit(f"make_share_copy: {msg}")


def split_frontmatter(text):
    """Return (frontmatter lines, body) — frontmatter is [] if there is none."""
    if not text.startswith("---\n"):
        return [], text
    end = text.find("\n---\n", 4)
    if end == -1:
        die("frontmatter opened with --- but never closed")
    return text[4:end].splitlines(), text[end + 5:]


def parse_frontmatter(lines):
    """Minimal YAML reader: scalars and simple `- item` lists. Enough for this template."""
    doc, key = {}, None
    for raw in lines:
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith((" ", "\t")) and line.strip().startswith("- ") and key:
            doc.setdefault(key, []).append(line.strip()[2:].strip().strip('"').strip("'"))
            continue
        if ":" in line:
            key, _, val = line.partition(":")
            key, val = key.strip(), val.strip()
            if val == "":
                doc[key] = []
            elif val.startswith("[") and val.endswith("]"):
                doc[key] = [v.strip().strip('"').strip("'") for v in val[1:-1].split(",") if v.strip()]
            else:
                doc[key] = val.strip('"').strip("'")
    return doc


def unwrap(text):
    return WIKILINK.sub(lambda m: (m.group(2) or m.group(1)).strip(), text)


def names(val):
    if isinstance(val, list):
        return [unwrap(v) for v in val if v]
    return [unwrap(val)] if val else []


def pretty_date(iso):
    try:
        d = datetime.date.fromisoformat(iso)
    except ValueError:
        return iso
    return f"{d:%A, %B} {d.day}, {d.year}"


def short_date(iso):
    try:
        d = datetime.date.fromisoformat(iso)
    except ValueError:
        return iso
    return f"{d:%b} {d.day}"


def header_block(fm):
    date = fm.get("date", "")
    team = unwrap(str(fm.get("team", "") or "")).strip() or "Meeting"
    org = unwrap(str(fm.get("org", "") or "")).strip()
    title = f"{team} ({org})" if org and org.lower() not in team.lower() else team
    out = [f"**{title} — {pretty_date(date) if date else 'meeting'}**"]
    present, absent, guests = names(fm.get("attendees")), names(fm.get("absent")), names(fm.get("guests"))
    if present:
        out.append(f"Present: {', '.join(present)}")
    if absent:
        out.append(f"Absent: {', '.join(absent)}")
    if guests:
        out.append(f"Guests: {', '.join(guests)}")
    return "\n".join(out) + "\n"


def convert_body(body):
    out, in_callout = [], False
    for line in body.splitlines():
        # Callout: header line becomes bold, quoted bullets are un-quoted.
        if re.match(r"^>\s*\[!summary\]", line):
            title = re.sub(r"^>\s*\[!summary\]\s*", "", line).strip() or "TL;DR"
            out.append(f"**{title}**")
            in_callout = True
            continue
        if in_callout and line.startswith(">"):
            out.append(unwrap(re.sub(r"^>\s?", "", line)))
            continue
        in_callout = False

        line = unwrap(line)
        line = DUE.sub(lambda m: f" — due {short_date(m.group(1))}", line)
        for emoji, word in PRIORITY.items():
            line = line.replace(f" {emoji}", f" {word}").replace(emoji, word)
        out.append(line.rstrip())
    return "\n".join(out).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("note", help="vault note (meeting-notes/<file>.md)")
    ap.add_argument("--out-dir", default=None,
                    help="where to write the copy (default: share/ beside meeting-notes/)")
    args = ap.parse_args()

    if not os.path.isfile(args.note):
        die(f"no such file: {args.note}")
    text = open(args.note, encoding="utf-8").read()
    fm_lines, body = split_frontmatter(text)
    if not fm_lines:
        die("note has no frontmatter — is this a vault note?")
    fm = parse_frontmatter(fm_lines)

    out_dir = args.out_dir or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(args.note))), "share")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, os.path.basename(args.note))

    # The H1 already names the meeting; the header block replaces it so the date reads
    # as prose and the roll call sits at the top where a reader expects it.
    body_lines = body.lstrip("\n").splitlines()
    if body_lines and body_lines[0].startswith("# "):
        body_lines = body_lines[1:]
    while body_lines and not body_lines[0].strip():
        body_lines.pop(0)
    result = header_block(fm) + "\n" + convert_body("\n".join(body_lines))

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(result)
    print(f"OK {out_path}")

    flags = NOTE_FLAG.findall(result)
    if flags:
        print(f"WARNING: {len(flags)} unresolved flag(s) — fix these in the vault note and "
              f"re-run before sending:", file=sys.stderr)
        for fl in flags:
            print(f"  {fl}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
