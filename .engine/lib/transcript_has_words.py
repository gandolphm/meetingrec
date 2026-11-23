#!/usr/bin/env python3
"""Exit 0 if the transcript file holds words, 1 if not.

    transcript_has_words.py <file>

clear-input asks this before it deletes a recording and keeps only its
transcript. An .srt counts only with cue text other than whisper.cpp's
[BLANK_AUDIO], the same reading transcribe_session.py gives it: cue numbers and
timings alone are a silent recording. Any other file (merged.txt) counts with
anything but whitespace. A file that can't be read has no words.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from transcribe_session import parse_srt  # noqa: E402


def has_words(path):
    if path.lower().endswith(".srt"):
        return bool(parse_srt(path))
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return any(line.strip() for line in f)
    except OSError:
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: transcript_has_words.py <file>")
    sys.exit(0 if has_words(sys.argv[1]) else 1)
