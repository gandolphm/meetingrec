#!/usr/bin/env python3
# After a stop: repairs unfinished WAV headers, measures each track, adds the checks to session.json, prints warnings, and appends a row to metrics.jsonl.
# Run by meetingrec (stop); kept out of the bash script so it can be linted
# and tested on its own.
import json, os, datetime, glob, wave, array, math, re, struct
d, dur = os.environ["MR_DIR"], int(os.environ["MR_DUR"])


def finish_header(path):
    """Write the two sizes in a WAV's header if its recorder never did.

    ffmpeg starts a WAV with both sizes set to 0xFFFFFFFF and comes back to fill
    them in when it stops. One that was killed (see stop) or that crashed never
    does: the audio is all there, but the file claims 37 hours of it, and how a
    player takes that is up to the player. The sizes follow from the file's
    length, so they are written here. True if the header was changed.

    The file's modification time is put back afterwards. It is the moment the
    last audio was written, and the track's place on the timeline is worked out
    from it below; left at "now" it would move the whole track by however long
    stop waited for the recorder.
    """
    try:
        st = os.stat(path)
        with open(path, "r+b") as f:
            head = f.read(4096)
            if head[:4] != b"RIFF" or head[8:12] != b"WAVE":
                return False
            # ffmpeg writes fmt and a LIST chunk before data, so data is found
            # by walking the chunks, not assumed to sit at byte 36.
            pos, block = 12, 2
            while pos + 8 <= len(head):
                cid = head[pos:pos + 4]
                size = struct.unpack("<I", head[pos + 4:pos + 8])[0]
                if cid == b"data":
                    break
                if cid == b"fmt " and pos + 22 <= len(head):
                    block = struct.unpack("<H", head[pos + 20:pos + 22])[0] or 2
                pos += 8 + size + (size & 1)
            else:
                return False
            start = pos + 8
            data = st.st_size - start
            data -= data % block       # a kill can land in the middle of a sample
            if data < 0:
                return False
            if size == data and struct.unpack("<I", head[4:8])[0] == start + data - 8:
                return False
            f.truncate(start + data)
            f.seek(4)
            f.write(struct.pack("<I", start + data - 8))
            f.seek(pos + 4)
            f.write(struct.pack("<I", data))
        os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))
        return True
    except (OSError, struct.error):
        return False

_PROG = re.compile(r"time=\s*(\d+):(\d\d):(\d\d(?:\.\d+)?)"
                   r".*?elapsed=\s*(\d+):(\d\d):(\d\d(?:\.\d+)?)")


def clock_error_ppm(log):
    """How fast this track's capture clock ran, vs the wall clock, in ppm.

    Recorded here because the ffmpeg logs do not survive: the meeting-notes skill
    deletes the whole session directory once the note is written. Measuring at
    stop means every recording leaves evidence about drift without anyone having
    to remember to look, which is what answers the phase 5 question over time.

    ffmpeg's progress lines carry both the audio timestamp (advanced by the
    device clock) and the wall clock. If the device clock is fast or slow, the
    difference grows linearly, and the slope is the error. Drift *between* the
    two tracks is the difference of their two errors — a constant offset is
    already corrected, a diverging one cannot be.
    """
    try:
        raw = open(log, encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    pts = []
    for m in _PROG.finditer(raw.replace("\r", "\n")):
        t = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
        e = int(m.group(4)) * 3600 + int(m.group(5)) * 60 + float(m.group(6))
        if e >= 30.0:          # skip device startup and buffer priming
            pts.append((e, t - e))
    if len(pts) < 20:
        return None            # too short to fit a slope worth reporting
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    den = sum((x - mx) ** 2 for x, _ in pts)
    if den == 0:
        return None
    return sum((x - mx) * (y - my) for x, y in pts) / den * 1e6


_SIZE = re.compile(r"size=\s*(\d+)KiB\s+time=\s*(\d+):(\d\d):(\d\d(?:\.\d+)?)")
_INPUT_HZ = re.compile(r"Input #0.*?Stream #0:0.*?Audio: [^,\n]+, (\d+) Hz", re.S)


def capture_progress(log, bytes_per_sec):
    """ffmpeg's progress lines as [(audio seconds written, seconds captured)].

    The two columns answer different questions. size= is what reached the file.
    time= is the capture clock: the timestamp the device put on the last buffer.
    On a healthy track they stay equal. When buffers go missing they part, and
    the gap between them is exactly the audio that was lost up to that point.

    They do go missing. FFmpeg's avfoundation input keeps one audio buffer: a
    new one replaces the last whether or not it was read, and ffmpeg looks every
    10 ms or so. A mic at 24 kHz hands over a buffer every 21 ms and loses
    nothing. At 48 kHz (AirPods in their 48 kHz mode) it is every 10.7 ms, and
    about one buffer in nine is overwritten; at 44.1 kHz (a MacBook Air's own
    mic) every 11.6 ms, and about one in fourteen. Nothing is logged, and time=
    keeps pace with the wall clock throughout. Measured on a 32-minute call:
    1720 s of audio for 1944 s captured.

    meetingrec's own ffmpeg is built with a patch that queues the buffers
    (.engine/tools/ffmpeg-avfoundation-audio-queue.patch), so it should lose
    nothing. This stays for Homebrew's ffmpeg, which has no such patch, and for
    whatever else loses audio one day.

    Also returns the mic's input sample rate, which is what decides it.
    """
    try:
        raw = open(log, encoding="utf-8", errors="replace").read()
    except OSError:
        return [], None
    pts = []
    for m in _SIZE.finditer(raw.replace("\r", "\n")):
        t = int(m.group(2)) * 3600 + int(m.group(3)) * 60 + float(m.group(4))
        pts.append((int(m.group(1)) * 1024.0 / bytes_per_sec, t))
    hz = _INPUT_HZ.search(raw)
    return pts, (int(hz.group(1)) if hz else None)


def timeline(pts, audio_secs, span, step=30.0):
    """A thinned [[audio seconds, seconds captured], ...] for the merge.

    Where a line sits in the file says when it was said only if nothing was
    lost before it. This is the map from one to the other: a point every half
    minute, which follows the loss even when it is uneven (it depends on how
    busy the Mac is), and ends on the exact totals.
    """
    out = [[0.0, 0.0]]
    for a, t in pts:
        a, t = min(a, audio_secs), min(t, span)
        if t - out[-1][1] >= step and a >= out[-1][0]:
            out.append([round(a, 2), round(t, 2)])
    if span - out[-1][1] < step / 2 and len(out) > 1:
        out.pop()
    out.append([round(audio_secs, 3), round(span, 3)])
    return out


def peak_dbfs(path):
    """Loudest sample in the file, in dBFS. None if unreadable.

    This is the actual silence test — the one phase 0 ran by hand with ffmpeg's
    volumedetect, finally automated. Size alone cannot do it: a tap that TCC has
    denied still streams zeros at the full 32,000 B/s, so it satisfies the
    byte-rate check, the metadata check and the size guard while recording
    nothing. Digital silence reads -91 dBFS or lower; anything real is far above.

    Done with array.max rather than ffmpeg so stop stays instant on a long
    recording: the per-chunk max runs in C, so an hour of audio costs well under
    a second and adds no dependency to the stop path.
    """
    try:
        peak = 0
        with wave.open(path, "rb") as w:
            if w.getsampwidth() != 2:
                return None
            while True:
                chunk = w.readframes(1 << 16)
                if not chunk:
                    break
                a = array.array("h")
                a.frombytes(chunk[:len(chunk) - len(chunk) % 2])
                if a:
                    peak = max(peak, max(a), -min(a))
    except Exception:
        return None
    if peak <= 0:
        return -math.inf
    return 20 * math.log10(peak / 32768.0)
p = os.path.join(d, "session.json")
try:
    doc = json.load(open(p))
except Exception:
    doc = {}
doc["ended"] = (datetime.datetime.now(datetime.timezone.utc)
                .isoformat(timespec="seconds").replace("+00:00", "Z"))
doc["duration_seconds"] = dur

checks = {}
cf = os.path.join(d, "format-check.txt")
if os.path.exists(cf):
    checks["startup_format"] = [l for l in open(cf).read().splitlines() if l.strip()]
# Track start offsets. The two tracks do NOT begin at the same instant: each
# ffmpeg only starts capturing once its device is open, and opening the mic can
# take seconds — a Bluetooth headset renegotiates to the HFP voice profile
# first. Measured on AirPods Pro: mic.wav began 4.7s after system.wav.
#
# Left uncorrected that offset lands straight in the merged transcript, tagging
# every [Me] line seconds early and interleaving replies ahead of what they
# replied to. So it is measured here, while the evidence still exists, rather
# than guessed at later.
#
# Each track's first sample is (when ffmpeg finalized the file) minus (how long
# it had been capturing). The finalize mtime is exact: SIGINT makes ffmpeg seek
# back and rewrite the RIFF header, so mtime is the moment capture ended. Frame
# count comes from the header rather than from file size, because ffmpeg writes
# 78 bytes of header and chunks, not the canonical 44. It is capped by the file
# size all the same: an ffmpeg that died before rewriting the header leaves a
# placeholder that reads as 37 hours of audio.
#
# How long it had been capturing is NOT how much audio the file holds. A track
# that lost audio along the way is shorter than its capture, and taking the
# audio length made every lost second look like a second of late start: a mic
# track that lost 11% of a 32-minute call was reported as starting 225 s late,
# and the merge then moved all of its lines by 225 s. So the capture length
# comes from ffmpeg's capture clock (see capture_progress), and what is missing
# from the file is recorded as lost audio, with a timeline the merge can follow.
#
# Note this measures the offset between the tracks, not either one's offset from
# when you clicked record — that is all the merge needs.
expect = int(os.environ["MR_EXPECT"])
first_sample = {}
repaired = set()
for name in ("mic.wav", "system.wav"):
    fp = os.path.join(d, name)
    if not os.path.exists(fp):
        continue
    if finish_header(fp):
        repaired.add(name)
    try:
        with wave.open(fp, "rb") as w:
            frame = w.getsampwidth() * w.getnchannels()
            frames = min(w.getnframes(), max(0, os.path.getsize(fp) - 44) // frame)
            audio_secs = frames / float(w.getframerate())
    except Exception:
        continue  # unreadable WAV is the silence guard's problem, not this one
    pts, input_hz = capture_progress(os.path.join(d, name[:-4] + "-ffmpeg.log"), expect)
    # Never shorter than the audio: an ffmpeg that was killed leaves a last
    # progress line up to half a second old.
    span = max(audio_secs, pts[-1][1] if pts else 0.0)
    first_sample[name] = (os.path.getmtime(fp) - span, audio_secs, span, pts, input_hz)
base = min((v[0] for v in first_sample.values()), default=0.0)

warnings = []
for name in ("mic.wav", "system.wav"):
    fp = os.path.join(d, name)
    if not os.path.exists(fp):
        continue
    size = os.path.getsize(fp)
    checks[name] = {"bytes": size,
                    "bytes_per_sec": round(size / dur) if dur else None}
    if name in repaired:
        # Its recorder was killed or crashed: see finish_header.
        checks[name]["header_repaired"] = True
    if name in first_sample:
        t0, audio_secs, span, pts, input_hz = first_sample[name]
        checks[name]["audio_seconds"] = round(audio_secs, 3)
        checks[name]["start_offset_seconds"] = round(t0 - base, 3)
        if input_hz and name == "mic.wav":   # the system track's is our own fifo
            checks[name]["input_sample_rate"] = input_hz
        # Under a second is not worth correcting for: the progress lines are
        # only that precise.
        lost = span - audio_secs
        if lost >= 1.0:
            checks[name]["lost_seconds"] = round(lost, 3)
            checks[name]["timeline"] = timeline(pts, audio_secs, span)
        if lost >= 2.0 and lost > 0.03 * span:
            side = "your side" if name == "mic.wav" else "the other side"
            warnings.append(
                f"{name} lost {100 * lost / span:.0f}% of its audio ({lost:.0f}s of "
                f"{span:.0f}s), in small gaps spread across the call. Its lines "
                f"are still placed at the right time, but words on {side} may be "
                f"missing or misheard.")
    ppm = clock_error_ppm(os.path.join(d, name[:-4] + "-ffmpeg.log"))
    if ppm is not None:
        checks[name]["clock_error_ppm"] = round(ppm, 1)
    # Is the file the right size?
    if dur > 5 and size < expect * dur * 0.5:
        warnings.append(f"{name} is {size} bytes for {dur}s "
                        f"(expected ~{expect*dur}) — likely a permissions problem")
    # Does it contain anything? A full-size file of zeros passes every other
    # check we have, so this is the one that catches a denied tap.
    pk = peak_dbfs(fp)
    if pk is not None:
        checks[name]["peak_dbfs"] = (None if pk == -math.inf else round(pk, 1))
        if pk < -60:
            cause = ("System Audio Recording" if name == "system.wav"
                     else "Microphone")
            warnings.append(
                f"{name} is silent (peak {'-inf' if pk == -math.inf else f'{pk:.0f}'} "
                f"dBFS) — it recorded no audio at all. Either nothing was playing, "
                f"or whatever launched meetingrec lacks {cause} permission. "
                f"Permissions attach to the launcher, so a working Terminal does "
                f"not mean a working menu bar.")
doc["checks"] = checks

# A large skew is not itself an error — the merge corrects for it — but it means
# seconds of one side went uncaptured, so it is worth seeing. Audio lost along
# the way is not skew, and is reported above.
skew = max((c.get("start_offset_seconds", 0) for c in checks.values()
            if isinstance(c, dict)), default=0)
if skew > 8:
    warnings.append(f"tracks started {skew:.1f}s apart — that much of the "
                    f"later track was missed (connect headphones before recording)")
if warnings:
    doc["warnings"] = warnings
with open(p, "w") as f:
    json.dump(doc, f, indent=2); f.write("\n")

# Keep the measurements after the recording itself is gone.
#
# The meeting-notes skill deletes the whole session directory once the note is
# written — that is the retention policy, and it is correct for audio. But it
# also takes session.json, so anything learned about the hardware would die with
# every meeting and the drift question could never accumulate an answer. One
# line per session, outside the vault so Obsidian never indexes it, costs
# nothing and means the evidence outlives the recording.
try:
    state = os.environ.get("MR_STATE")
    if state:
        os.makedirs(state, exist_ok=True)
        row = {"session": os.path.basename(d), "started": doc.get("started"),
               "duration_seconds": dur,
               "mic_device": doc.get("mic_device"),
               "output_device": doc.get("output_device")}
        for name in ("mic.wav", "system.wav"):
            c = checks.get(name)
            if isinstance(c, dict):
                row[name] = {k: c.get(k) for k in
                             ("clock_error_ppm", "start_offset_seconds",
                              "peak_dbfs", "audio_seconds", "lost_seconds",
                              "input_sample_rate")}
        if warnings:
            row["warnings"] = warnings
        with open(os.path.join(state, "metrics.jsonl"), "a") as f:
            f.write(json.dumps(row) + "\n")
except Exception:
    pass  # never let bookkeeping fail a stop

for w in warnings:
    print("WARNING: " + w)
