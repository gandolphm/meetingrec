#!/usr/bin/env python3
"""transcribe_session.py — transcribe a two-track meetingrec session.

    transcribe_session.py <session_dir> [--model small.en] [--prompt "names, jargon"]

Produces, in the session directory:
    mic.srt  system.srt   per-track transcripts, timestamps in real session time
    merged.txt            both tracks interleaved and tagged [Me] / [Them]

Why this exists instead of calling transcribe.sh directly
---------------------------------------------------------
A per-speaker track is mostly silence — the far end is quiet while you talk —
and Whisper handles long silence badly in two ways that both corrupt the result:

  1. It hallucinates. Feed it a minute of silence and it will confidently emit a
     repeated sentence that nobody said. In a meeting transcript, invented
     content is far worse than missing content.
  2. Its timestamps drift. Measured on a 95s test track, speech at 12s/45s/78s
     came back tagged 0s/20s/50s — enough to interleave a reply ahead of the
     thing it replied to.

So silence is removed before Whisper ever sees it: ffmpeg's silencedetect finds
the speech regions, the track is compacted down to just those regions, and the
resulting timestamps are mapped back onto real session time afterwards. Whisper
sees only speech, and every cue keeps its true position.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))

# silencedetect tuning. -35 dB is well below speech but above a mic's room tone;
# 0.8s avoids chopping at every natural pause between sentences.
NOISE_DB = "-35dB"
MIN_SILENCE = 0.8
PAD = 0.25          # seconds kept either side of a region, so words aren't clipped
GAP_MERGE = 0.6     # regions closer than this are joined rather than split

# Silence inserted between regions in the compacted track. Butting regions
# directly against each other makes Whisper read utterances that were a minute
# apart as one continuous sentence, and the whole run then inherits the first
# region's timestamp. A pause restores the segment boundary. It is deliberately
# short: the hallucination loop needs many seconds of silence to get going, so
# one second buys the split without buying the problem back.
SEPARATOR = 1.0

TIMING = re.compile(
    r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*"
    r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})"
)
SIL = re.compile(r"silence_(start|end):\s*([0-9.]+)")


def die(msg):
    sys.exit(f"transcribe_session: {msg}")


def wav_info(path):
    with wave.open(path, "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            die(f"{path}: expected mono 16-bit; meetingrec writes s16le mono 16 kHz")
        return w.getframerate(), w.getnframes() / float(w.getframerate())


def speech_regions(path, duration):
    """Complement of ffmpeg's detected silence, padded and gap-merged."""
    proc = subprocess.run(
        ["ffmpeg", "-v", "info", "-nostdin", "-i", path,
         "-af", f"silencedetect=noise={NOISE_DB}:d={MIN_SILENCE}", "-f", "null", "-"],
        capture_output=True, text=True)
    marks = [(m.group(1), float(m.group(2))) for m in SIL.finditer(proc.stderr)]

    silences, open_start = [], None
    for kind, t in marks:
        if kind == "start":
            open_start = t
        elif open_start is not None:
            silences.append((open_start, t))
            open_start = None
    if open_start is not None:
        silences.append((open_start, duration))

    # Invert to get speech.
    regions, cursor = [], 0.0
    for s, e in silences:
        if s > cursor:
            regions.append((cursor, min(s, duration)))
        cursor = max(cursor, e)
    if cursor < duration:
        regions.append((cursor, duration))

    # Pad, then merge anything that ends up adjacent.
    padded = [(max(0.0, s - PAD), min(duration, e + PAD)) for s, e in regions if e > s]
    merged = []
    for s, e in padded:
        if merged and s - merged[-1][1] <= GAP_MERGE:
            merged[-1] = (merged[-1][0], e)
        else:
            merged.append((s, e))
    return [(s, e) for s, e in merged if e - s > 0.15]


def compact(path, out_path, regions, rate):
    """Write a WAV of just the speech regions; return the offset map."""
    mapping, compact_t = [], 0.0
    gap = b"\x00" * (2 * int(SEPARATOR * rate))
    with wave.open(path, "rb") as src, wave.open(out_path, "wb") as dst:
        dst.setnchannels(1); dst.setsampwidth(2); dst.setframerate(rate)
        for i, (s, e) in enumerate(regions):
            if i:
                dst.writeframes(gap)
                compact_t += SEPARATOR
            src.setpos(int(s * rate))
            frames = src.readframes(int((e - s) * rate))
            dst.writeframes(frames)
            dur = len(frames) / 2.0 / rate
            mapping.append((compact_t, s, dur))
            compact_t += dur
    return mapping


def to_real(t, mapping):
    """Map a compacted-timeline second back onto real session time."""
    if not mapping:
        return t
    for c_start, o_start, dur in mapping:
        if t < c_start + dur:
            return o_start + max(0.0, t - c_start)
    c_start, o_start, dur = mapping[-1]
    return o_start + dur


def parse_srt(path):
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    cues = []
    for block in re.split(r"\n\s*\n", raw.replace("\r\n", "\n").lstrip("﻿")):
        lines = [l for l in block.split("\n") if l.strip()]
        idx = next((i for i, l in enumerate(lines) if TIMING.search(l)), None)
        if idx is None:
            continue
        g = [int(x) for x in TIMING.search(lines[idx]).groups()]
        start = g[0] * 3600 + g[1] * 60 + g[2] + g[3] / 1000.0
        end = g[4] * 3600 + g[5] * 60 + g[6] + g[7] / 1000.0
        text = " ".join(l.strip() for l in lines[idx + 1:]).strip()
        # whisper.cpp marks silence explicitly; it carries no information.
        if text and text != "[BLANK_AUDIO]":
            cues.append((start, end, text))
    return cues


def srt_time(t):
    ms = int(round(t * 1000))
    h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def write_srt(path, cues):
    with open(path, "w", encoding="utf-8") as f:
        for i, (s, e, text) in enumerate(cues, 1):
            f.write(f"{i}\n{srt_time(s)} --> {srt_time(e)}\n{text}\n\n")


def track_offsets(session, names):
    """Seconds each track started after the earliest one.

    The tracks do not start together. Each ffmpeg begins capturing only once its
    device is open, and a Bluetooth mic renegotiates to the HFP voice profile
    first — measured at 4.7s on AirPods Pro. Merging without correcting for that
    tags every [Me] line seconds early and can place a reply before the thing it
    replied to.

    meetingrec records the offset at stop time, which is the number to trust.
    Failing that it is re-derived the same way meetingrec derives it: finalize
    mtime minus audio duration. That fallback is best-effort — copying a session
    directory rewrites mtimes and destroys it — so a session recorded before
    meetingrec started writing the offsets should be transcribed in place.
    """
    try:
        doc = json.load(open(os.path.join(session, "session.json")))
        checks = doc.get("checks") or {}
        found = {n: checks[n + ".wav"]["start_offset_seconds"]
                 for n in names
                 if isinstance(checks.get(n + ".wav"), dict)
                 and "start_offset_seconds" in checks[n + ".wav"]}
        if len(found) == len(names):
            return found, "session.json"
    except Exception:
        pass

    first = {}
    for n in names:
        p = os.path.join(session, f"{n}.wav")
        try:
            with wave.open(p, "rb") as w:
                secs = w.getnframes() / float(w.getframerate())
            first[n] = os.path.getmtime(p) - secs
        except Exception:
            return {n: 0.0 for n in names}, "unavailable"
    base = min(first.values())
    return {n: t - base for n, t in first.items()}, "file mtimes"


def do_track(session, name, model, prompt, offset=0.0):
    """Return (cues_in_real_time, human_summary)."""
    path = os.path.join(session, f"{name}.wav")
    rate, duration = wav_info(path)
    regions = speech_regions(path, duration)
    speech = sum(e - s for s, e in regions)

    if not regions or speech < 0.5:
        write_srt(os.path.join(session, f"{name}.srt"), [])
        return [], (f"{name}: NO SPEECH DETECTED in {duration:.0f}s — "
                    f"if this was a real meeting, suspect a permissions problem")

    compact_wav = os.path.join(session, f".{name}.speech.wav")
    mapping = compact(path, compact_wav, regions, rate)

    rc = subprocess.run(
        ["bash", os.path.join(HERE, "transcribe.sh"), compact_wav, session, model, prompt],
        capture_output=True, text=True)
    if rc.returncode != 0:
        os.path.exists(compact_wav) and os.remove(compact_wav)
        die(f"{name}: transcribe.sh failed ({rc.returncode}): {rc.stderr.strip()}")

    raw_srt = os.path.join(session, f".{name}.speech.srt")
    cues = [(to_real(s, mapping), to_real(e, mapping), t) for s, e, t in parse_srt(raw_srt)]
    # Bound against this track's own length before shifting: the offset moves the
    # track onto the shared session timeline, where that bound no longer applies.
    cues = [c for c in cues if c[0] <= duration + 1]
    cues = [(s + offset, e + offset, t) for s, e, t in cues]
    cues.sort(key=lambda c: c[0])
    write_srt(os.path.join(session, f"{name}.srt"), cues)

    for tmp in (compact_wav, raw_srt):
        os.path.exists(tmp) and os.remove(tmp)

    pct = 100.0 * (1 - speech / duration) if duration else 0
    return cues, (f"{name}: {len(cues)} cues from {len(regions)} speech regions "
                  f"({speech:.0f}s speech in {duration:.0f}s — {pct:.0f}% silence skipped)")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("session")
    ap.add_argument("--model", default="small.en")
    ap.add_argument("--prompt", default="")
    args = ap.parse_args()

    session = args.session.rstrip("/")
    if not os.path.isdir(session):
        die(f"not a directory: {session}")

    tracks = [(n, lab) for n, lab in (("mic", "Me"), ("system", "Them"))
              if os.path.exists(os.path.join(session, f"{n}.wav"))]
    if not tracks:
        die(f"no mic.wav or system.wav in {session}")

    offsets, source = ({t[0]: 0.0 for t in tracks}, "single track")
    if len(tracks) == 2:
        offsets, source = track_offsets(session, [n for n, _ in tracks])

    all_cues, notes = [], []
    for name, label in tracks:
        cues, summary = do_track(session, name, args.model, args.prompt,
                                 offsets.get(name, 0.0))
        notes.append(summary)
        all_cues += [(s, label, t) for s, _, t in cues]

    for n in notes:
        print(n)
    if len(tracks) == 2:
        if source == "unavailable":
            print("track alignment: UNKNOWN — merging as if both tracks started "
                  "together; ordering across speakers may be wrong")
        else:
            late = max(offsets, key=lambda n: offsets[n])
            print(f"track alignment: {late} started {offsets[late]:.1f}s late "
                  f"(from {source}), corrected")

    if len(tracks) < 2:
        print(f"single track ({tracks[0][0]}) — no merge, no [Me]/[Them] tags")
        return
    if not all_cues:
        die("both tracks transcribed empty — nothing to merge")

    # Tie goes to [Them]: a reply made in the same second is a response to it.
    all_cues.sort(key=lambda c: (c[0], c[1] == "Me"))
    out = os.path.join(session, "merged.txt")
    width = max(len(c[1]) for c in all_cues) + 2
    with open(out, "w", encoding="utf-8") as f:
        for start, who, text in all_cues:
            s = int(start)
            f.write(f"[{s//3600:02d}:{(s%3600)//60:02d}:{s%60:02d}] "
                    f"{('[' + who + ']'):<{width}} {text}\n")
    print(f"OK {out} ({len(all_cues)} cues)")


if __name__ == "__main__":
    main()
