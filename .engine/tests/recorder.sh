#!/usr/bin/env bash
#
# Tests for the recorder's state handling and for clear-input, with ffmpeg,
# system_profiler and osascript replaced by stubs. No microphone, permissions or
# real audio needed, and nothing outside a temporary folder is touched: the repo
# is copied there, so scribe/transcripts and the inboxes are the copy's.
#
#   bash .engine/tests/recorder.sh
#
# Plain bash rather than a test framework, so it runs on any Mac with the
# Command Line Tools, like the rest of meetingrec.
#
set -uo pipefail

SRC="$(cd "$(dirname "$0")/../.." && pwd)"
# Normalized: TMPDIR ends in "/", and a "//" in HOME would never match the clean
# paths meetingrec saves.
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/meetingrec-test.XXXXXX")" && pwd)"
# The path has an apostrophe and a space on purpose: the state file must survive both.
REPO="$T/Alice's Mac/meetingrec"
INBOX="$REPO/scribe/input"
STUBS="$T/home/.local/share/meetingrec/bin"
MR="$REPO/.engine/bin/meetingrec"

export HOME="$T/home"
export XDG_STATE_HOME="$T/state"
export MEETINGREC_CONFIG="$T/config.sh"
STATE_FILE="$XDG_STATE_HOME/meetingrec/current"

mkdir -p "$REPO/scribe/transcripts" "$INBOX" "$REPO/teamnotes/input" "$STUBS"
cp -R "$SRC/.engine" "$REPO/.engine"
# For prepare: the settings templates and the skills (with their starters). Only
# the files git ships: a developer's own personal.md or team.md stays out.
for kind in scribe teamnotes; do
  mkdir -p "$REPO/$kind/settings/profiles"
  cp "$SRC/$kind/settings/"*.example.md "$SRC/$kind/settings/shared.md" "$REPO/$kind/settings/"
  cp -R "$SRC/$kind/.claude" "$REPO/$kind/.claude"
done
cp "$SRC/teamnotes/settings/profiles/"*.example.md "$SRC/teamnotes/settings/profiles/other.md" \
  "$REPO/teamnotes/settings/profiles/"
printf 'OUTPUT_ROOT="%s"\n' "$INBOX" > "$MEETINGREC_CONFIG"

# The background byte-rate checks outlive a test by up to ~30 s. Removing the
# folder (and with it the osascript stub) before they finish would let a real
# notification through, so the cleanup waits for them.
cleanup() {
  "$MR" stop >/dev/null 2>&1
  ( sleep 45; rm -rf "$T" ) >/dev/null 2>&1 &
}
trap cleanup EXIT

# --- stubs -----------------------------------------------------------------

# ffmpeg: writes a valid 16 kHz mono WAV of a quiet tone at the real rate until
# SIGINT or SIGTERM, then fixes the header and exits 0, like the real one. It
# prints the real one's progress lines too. STUB_FFMPEG_KEEP=0.8 keeps only
# that share of the audio while time= runs on at full speed, which is what the
# real one does when it drops microphone buffers.
cat > "$STUBS/ffmpeg" <<'PY'
#!/usr/bin/env python3
import math, os, signal, struct, sys, time
out, rate = sys.argv[-1], 16000
keep = float(os.environ.get("STUB_FFMPEG_KEEP", "1"))
if __import__("os").environ.get("STUB_FFMPEG_FAIL"):
    sys.stderr.write("stub ffmpeg: told to fail\n"); sys.exit(1)
# Like the real one with -nostdin: no -y, an existing output file is an error.
if "-y" not in sys.argv and __import__("os").path.exists(out):
    sys.stderr.write(f"File '{out}' already exists. Exiting.\n"); sys.exit(1)
f = open(out, "wb")
def header(n):
    return (b"RIFF" + struct.pack("<I", 36 + n) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16)
            + b"data" + struct.pack("<I", n))
f.write(header(0)); f.flush()
chunk = struct.pack("<1600h", *[int(3000 * math.sin(2 * math.pi * 440 * i / rate))
                                for i in range(1600)])
n, began = 0, time.time()
def progress():
    t = time.time() - began
    clock = "%02d:%02d:%05.2f" % (t // 3600, t % 3600 // 60, t % 60)
    sys.stderr.write("size=%8dKiB time=%s bitrate= 256.0kbits/s speed=   1x elapsed=%s    \r"
                     % ((44 + n) // 1024, clock, clock[1:]))
    sys.stderr.flush()
def stop(*_):
    progress()
    f.seek(0); f.write(header(n)); f.close(); sys.exit(0)
# Set explicitly: a background job inherits SIGINT as ignored.
signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)
# Paced by the clock, not by counting sleeps: the rate checks measure it.
while True:
    while n + len(chunk) <= (time.time() - began) * rate * 2 * keep:
        f.write(chunk); n += len(chunk)
    f.flush(); progress(); time.sleep(0.1)
PY

cat > "$STUBS/system_profiler" <<'EOF'
#!/bin/sh
echo '{"SPAudioDataType":[{"_items":[
  {"_name":"Test Mic","coreaudio_default_audio_input_device":"spaudio_yes"},
  {"_name":"Test Speakers","coreaudio_default_audio_output_device":"spaudio_yes"}]}]}'
EOF

cat > "$STUBS/osascript" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/notifications.log"
EOF

chmod +x "$STUBS"/*

# --- helpers ---------------------------------------------------------------

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
exist()  { local f; for f; do [ -e "$f" ] || return 1; done; }
absent() { local f; for f; do [ ! -e "$f" ] || return 1; done; }
has()    { printf '%s' "$1" | grep -q "$2"; }

# shellcheck source=/dev/null
state() { ( . "$STATE_FILE"; eval "printf '%s' \"\${$1:-}\"" ); }
secs() { python3 -c 'import time; print(time.time())'; }

# --- tests -----------------------------------------------------------------

echo "mic-only start / status / stop"
out="$("$MR" start "Weekly sync" --mic-only 2>&1)" || bad "start succeeds" "$out"
check "status says recording" [ "$("$MR" status | cut -d' ' -f1)" = recording ]
check "state file keeps the apostrophe path" \
  [ "$(dirname "$(state SESSION_DIR)")" = "$INBOX" ]
dir="$(state SESSION_DIR)"
t0="$(secs)"
out="$("$MR" stop 2>&1)" || bad "stop succeeds" "$out"
t1="$(secs)"
check "stop returns in under 3 s (no 10 s wait on SYS_FF_PID=0)" \
  python3 -c "import sys; sys.exit(0 if $t1 - $t0 < 3 else 1)"
check "status is idle after stop" [ "$("$MR" status)" = idle ]
check "mic.wav and session.json written" exist "$dir/mic.wav" "$dir/session.json"

echo "a crashed mic-only session doesn't wedge the tool"
"$MR" start "Crash test" --mic-only >/dev/null 2>&1
kill -9 "$(state MIC_PID)" 2>/dev/null; sleep 0.3
check "status reports the stale session as idle" has "$("$MR" status)" '^idle'
out="$("$MR" start "After crash" --mic-only 2>&1)"
check "a new start clears the stale state and records" has "$out" '^recording:'
"$MR" stop >/dev/null 2>&1

# What the menu does when its tick finds the recorder dead.
"$MR" start "Crash then stop" --mic-only >/dev/null 2>&1
dir="$(state SESSION_DIR)"
kill -9 "$(state MIC_PID)" 2>/dev/null; sleep 0.3
check "status says stale, which is what the menu looks for" has "$("$MR" status)" 'stale'
t0="$(secs)"
"$MR" stop >/dev/null 2>&1; rc=$?
t1="$(secs)"
check "stop on the dead session succeeds" [ "$rc" -eq 0 ]
check "...in under 3 s" python3 -c "import sys; sys.exit(0 if $t1 - $t0 < 3 else 1)"
check "...records when it ended" has "$(cat "$dir/session.json")" '"ended"'
check "...and leaves the tool idle" [ "$("$MR" status)" = idle ]

# A recording that has already ended, made by hand: tracks of exactly the given
# lengths, closed at exactly the given times, with ffmpeg logs that say how long
# each one was capturing. stop then runs its checks on it. No waiting, and the
# numbers are exact.
#   fake_session <dir> <track> <audio s> <captured s> <closed at, epoch s> ...
fake_session() {
  python3 - "$@" <<'PY'
import os, sys, wave
d, rest = sys.argv[1], sys.argv[2:]
os.makedirs(d)
for name, audio, span, closed in zip(rest[0::4], rest[1::4], rest[2::4], rest[3::4]):
    audio, span, closed = float(audio), float(span), float(closed)
    wav = os.path.join(d, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes(b"\x10\x20" * int(audio * 16000))
    with open(os.path.join(d, name + "-ffmpeg.log"), "w") as log:
        log.write("Input #0, avfoundation, from ':default':\n"
                  "  Stream #0:0: Audio: pcm_f32le, 48000 Hz, mono, flt, 1536 kb/s\n")
        t = 0.0
        while t <= span:
            # Loses nothing in the first half of the capture, everything it is
            # going to lose in the second: the merge has to follow that.
            got = min(t, span / 2) + max(0.0, t - span / 2) * (audio - span / 2) / (span / 2)
            log.write("size=%8dKiB time=%02d:%02d:%05.2f bitrate= 256.0kbits/s speed=   1x "
                      "elapsed=0:00:00.00    \r" % (got * 32000 / 1024, t // 3600, t % 3600 // 60, t % 60))
            t += 0.5
    os.utime(wav, (closed, closed))
PY
  mkdir -p "$(dirname "$STATE_FILE")"
  printf 'SESSION_DIR=%q\nAUDIOTEE_PID=0\nSYS_FF_PID=0\nMIC_PID=0\nSTARTED_EPOCH=%d\nTRACKS=mic,system\n' \
    "$1" "$(( $(date +%s) - 100 ))" > "$STATE_FILE"
}
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["checks"][sys.argv[2]].get(sys.argv[3]))' "$@"; }

echo "a track that lost audio is not a track that started late"
s="$T/sessions/lossy"
# Both captured for 100 s and the mic closed 1 s after system, so it started 1 s
# after it. But its file holds only 80 s: 20 s went missing along the way.
fake_session "$s" mic 80 100 1001 system 100 100 1000
out="$("$MR" stop 2>&1)"
check "the mic started 1 s after system, not 21 s" [ "$(field "$s/session.json" mic.wav start_offset_seconds)" = 1.0 ]
check "...and lost 20 s" [ "$(field "$s/session.json" mic.wav lost_seconds)" = 20.0 ]
check "stop says how much was lost" has "$out" 'WARNING: mic.wav lost 20% of its audio (20s of 100s)'
check "...and doesn't call it a late start" bash -c '! grep -q "tracks started" <<< "$1"' _ "$out"
check "the timeline ends on the totals" \
  python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["checks"]["mic.wav"]["timeline"]; sys.exit(0 if t[0]==[0.0,0.0] and t[-1]==[80.0,100.0] else 1)' "$s/session.json"
check "...and follows the loss: none of it in the first half" \
  python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["checks"]["mic.wav"]["timeline"]; sys.exit(0 if any(abs(a-30)<0.1 and abs(c-30)<0.1 for a,c in t) and any(abs(a-56)<0.1 and abs(c-60)<0.1 for a,c in t) else 1)' "$s/session.json"
check "the track that lost nothing gets no timeline" [ "$(field "$s/session.json" system.wav timeline)" = None ]
check "the mic's input rate is kept" [ "$(field "$s/session.json" mic.wav input_sample_rate)" = 48000 ]
check "the lost seconds reach metrics.jsonl" has "$(tail -1 "$XDG_STATE_HOME/meetingrec/metrics.jsonl")" '"lost_seconds": 20.0'

s="$T/sessions/late"
# The same two files, but the mic was only capturing for 80 s: a real late start.
fake_session "$s" mic 80 80 1001 system 100 100 1000
out="$("$MR" stop 2>&1)"
check "a real late start is still one" [ "$(field "$s/session.json" mic.wav start_offset_seconds)" = 21.0 ]
check "...and still warned about" has "$out" 'WARNING: tracks started 21.0s apart'
check "...with nothing lost" bash -c '! grep -q "lost" <<< "$1"' _ "$out"

s="$T/sessions/unfinished"
# ffmpeg died without rewriting the header: the length field still holds its
# placeholder, which reads as 37 hours of audio.
fake_session "$s" mic 100 100 1000 system 100 100 1000
python3 - "$s/mic.wav" <<'PY'
import os, struct, sys
st = os.stat(sys.argv[1])
with open(sys.argv[1], "r+b") as f:
    f.seek(40); f.write(struct.pack("<I", 0xFFFFFFFF))
os.utime(sys.argv[1], (st.st_mtime, st.st_mtime))
PY
"$MR" stop >/dev/null 2>&1
check "an unfinished header doesn't read as 37 hours" [ "$(field "$s/session.json" mic.wav audio_seconds)" = 100.0 ]
check "...or as a track that started 37 hours late" [ "$(field "$s/session.json" system.wav start_offset_seconds)" = 0.0 ]

echo "a mic that is losing audio is caught while recording"
: > "$T/notifications.log"
STUB_FFMPEG_KEEP=0.8 "$MR" start "Lossy live" --mic-only >/dev/null 2>&1
dir="$(state SESSION_DIR)"
for _ in $(seq 1 40); do grep -q '^mic ' "$dir/format-check.txt" 2>/dev/null && break; sleep 0.5; done
check "the startup check says SHORT, not OK" has "$(cat "$dir/format-check.txt" 2>/dev/null)" '^mic SHORT (.* B/s, [78][0-9]% of the expected 32000'
check "...and notifies" has "$(cat "$T/notifications.log")" 'mic track is losing audio'
out="$("$MR" stop 2>&1)"
check "stop reports the loss from the real progress lines" has "$out" 'WARNING: mic.wav lost [12][0-9]% of its audio'
"$MR" start "Healthy live" --mic-only >/dev/null 2>&1
dir="$(state SESSION_DIR)"
for _ in $(seq 1 20); do grep -q '^mic ' "$dir/format-check.txt" 2>/dev/null && break; sleep 0.5; done
check "a healthy mic still reads OK" has "$(cat "$dir/format-check.txt" 2>/dev/null)" '^mic OK '
out="$("$MR" stop 2>&1)"
check "...and stop has nothing to say about it" bash -c '! grep -q "WARNING" <<< "$1"' _ "$out"

echo "two starts in the same minute with the same title"
"$MR" start "Dup" --mic-only >/dev/null 2>&1; "$MR" stop >/dev/null 2>&1
out="$("$MR" start "Dup" --mic-only 2>&1)"
check "the second start succeeds" has "$out" '^recording:'
"$MR" stop >/dev/null 2>&1
check "two folders ending in _dup" [ "$(ls -1d "$INBOX"/*_dup | wc -l | tr -d ' ')" = 2 ]

echo "clear-input"
note="$T/note.md"; echo "# a note" > "$note"
"$MR" start "Live" --mic-only >/dev/null 2>&1
live="$(state SESSION_DIR)"
"$MR" clear-input "$live" --delete --note "$note" >/dev/null 2>&1; rc=$?
check "refuses the session that's still recording" [ "$rc" -ne 0 ]
check "...and leaves it in place" exist "$live/mic.wav"
"$MR" stop >/dev/null 2>&1

s="$INBOX/2026-01-01T10-00_keep"
mkdir -p "$s"; for f in merged.txt mic.srt session.json mic.wav; do echo "$f" > "$s/$f"; done
out="$("$MR" clear-input "$s" --keep-transcript --note "$note" 2>&1)"
kept="$REPO/scribe/transcripts/2026-01-01T10-00_keep"
check "--keep-transcript keeps the text and session.json" \
  exist "$kept/merged.txt" "$kept/mic.srt" "$kept/session.json"
check "--keep-transcript drops the audio and the recording" absent "$kept/mic.wav" "$s"

s="$INBOX/2026-01-02T10-00_broken"
mkdir -p "$s"; for f in merged.txt mic.srt mic.wav; do echo "$f" > "$s/$f"; done
chmod 000 "$s/mic.srt"
out="$("$MR" clear-input "$s" --keep-transcript --note "$note" 2>&1)"
rc=$?
chmod 644 "$s/mic.srt"
check "a copy that fails exits non-zero" [ "$rc" -ne 0 ]
check "...and leaves every source file in place" exist "$s/merged.txt" "$s/mic.srt" "$s/mic.wav"
check "...and leaves no half-kept folder" absent "$REPO/scribe/transcripts/2026-01-02T10-00_broken"

s="$INBOX/2026-01-03T10-00_notext"
mkdir -p "$s"; echo x > "$s/mic.wav"
"$MR" clear-input "$s" --keep-transcript --note "$note" >/dev/null 2>&1; rc=$?
check "no transcript: refuses" [ "$rc" -ne 0 ]
check "...and keeps the recording" exist "$s/mic.wav"

echo "silence detection"
out="$(STUB_FFMPEG_FAIL=1 python3 -c '
import sys; sys.path.insert(0, sys.argv[1])
import transcribe_session as t
t.speech_regions("whatever.wav", 60.0)
print("returned")' "$REPO/.engine/lib" 2>&1)"
rc=$?
check "a failed ffmpeg run stops the transcription" [ "$rc" -ne 0 ]
check "...and says why" has "$out" 'silence detection failed'

echo "a missing recordings folder"
# Its own config: the folder is chosen in the config, not the environment.
gone="$T/Unplugged drive/Recordings"
printf 'OUTPUT_ROOT="%s"\n' "$gone" > "$T/config-gone.sh"
out="$(MEETINGREC_CONFIG="$T/config-gone.sh" "$MR" start "Gone" --mic-only 2>&1)"; rc=$?
check "start refuses a custom folder that's missing" [ "$rc" -ne 0 ]
check "...says what to do" has "$out" 'choose the folder again'
check "...and doesn't re-create it" absent "$T/Unplugged drive"
check "...and isn't left recording" [ "$("$MR" status)" = idle ]
"$MR" stop >/dev/null 2>&1
# No OUTPUT_ROOT saved: the default inbox, which start creates when it's missing.
default_inbox="$REPO/scribe/input"
mv "$default_inbox" "$T/inbox-aside"
: > "$T/config-default.sh"
out="$(MEETINGREC_CONFIG="$T/config-default.sh" "$MR" start "Default" --mic-only 2>&1)" \
  || bad "start re-creates the default inbox" "$out"
check "start re-creates the default inbox" exist "$default_inbox"
MEETINGREC_CONFIG="$T/config-default.sh" "$MR" stop >/dev/null 2>&1
rm -rf "$default_inbox"; mv "$T/inbox-aside" "$default_inbox"

echo "prepare and the starter files"
vault="$T/My Vault"
mkdir -p "$vault"
"$MR" config set NOTES_VAULT "$vault" >/dev/null
out="$("$MR" prepare scribe 2>&1)"
check "prepare prints STARTERS" has "$out" '^STARTERS=.*/scribe/.claude/skills/meeting-notes/assets$'
check "...where the starter Tasks.md is" exist "$REPO/scribe/.claude/skills/meeting-notes/assets/Tasks.md"
check "a vault without Tasks.md says NO DASHBOARD" has "$out" '^NO DASHBOARD$'
check "...and gets the starter notes table" \
  cmp -s "$vault/index.base" "$REPO/scribe/.claude/skills/meeting-notes/assets/index.base"
team="$T/Team Vault"
mkdir -p "$team"
"$MR" config set TEAM_VAULT "$team" >/dev/null
out="$("$MR" prepare teamnotes 2>&1)"
check "team prepare prints its own STARTERS" \
  has "$out" '^STARTERS=.*/teamnotes/.claude/skills/team-notes/assets$'
check "...where the starter Action Items.md is" \
  exist "$REPO/teamnotes/.claude/skills/team-notes/assets/Action Items.md"
check "...and the team vault gets the team's notes table" \
  cmp -s "$team/index.base" "$REPO/teamnotes/.claude/skills/team-notes/assets/index.base"

# The rest run against a config of their own, starting empty.
CFG="$T/config-cfg.sh"
: > "$CFG"
mrc() { MEETINGREC_CONFIG="$CFG" "$MR" "$@"; }

echo "config"
out="$(mrc config get NOTES_VAULT)"; rc=$?
check "an unsaved notes folder prints the default" has "$out" '/scribe$'
check "...and exits 2, so the skill knows to ask" [ "$rc" -eq 2 ]
out="$(mrc config set NOTES_VAULT "$T/nowhere" 2>&1)"; rc=$?
check "a folder that doesn't exist is refused" [ "$rc" -ne 0 ]
check "...saying so" has "$out" "doesn't exist"
mkdir -p "$HOME/Notes Vault" "$HOME/Team Notes"
# shellcheck disable=SC2088  # a literal ~, the way someone types it
mrc config set NOTES_VAULT "~/Notes Vault" >/dev/null
# shellcheck disable=SC2016  # the saved line holds a literal $HOME
check "a folder in the home folder is saved as \$HOME/…" grep -qxF 'NOTES_VAULT="$HOME/Notes Vault"' "$CFG"
check "...and read back as the full path" [ "$(mrc config get NOTES_VAULT)" = "$HOME/Notes Vault" ]
out="$(mrc config set TEAM_VAULT "$HOME/Notes Vault" 2>&1)"; rc=$?
check "team notes can't share the personal notes folder" [ "$rc" -ne 0 ]
check "...saying why" has "$out" 'separate folders'
mrc config set TEAM_VAULT "$HOME/Team Notes" >/dev/null
mkdir -p "$T/say \"hi\""
out="$(mrc config set OUTPUT_ROOT "$T/say \"hi\"" 2>&1)"; rc=$?
check "a folder name with a quote is refused" [ "$rc" -ne 0 ]
out="$(mrc config set AUTO_UPDATE_CHECK maybe 2>&1)"; rc=$?
check "on/off settings refuse anything else" [ "$rc" -ne 0 ]
mrc config set AUTO_UPDATE_CHECK off >/dev/null
check "...and save on or off" [ "$(mrc config get AUTO_UPDATE_CHECK)" = off ]
out="$(mrc config list)"
check "list marks a changed setting custom" has "$out" $'^AUTO_UPDATE_CHECK\toff\tcustom$'
check "...and an unchanged one default" has "$out" $'^USE_HOMEBREW\toff\tdefault$'
check "write-ups open in the app by default" [ "$(mrc config get WRITEUP_IN)" = app ]
out="$(mrc config set WRITEUP_IN on 2>&1)"; rc=$?
check "WRITEUP_IN refuses anything but app or terminal" [ "$rc" -ne 0 ]
check "...saying which" has "$out" 'must be app or terminal'
mrc config set WRITEUP_IN terminal >/dev/null
check "...and saves terminal" [ "$(mrc config get WRITEUP_IN)" = terminal ]
mrc config set WRITEUP_IN "" >/dev/null
check "...and an empty value goes back to the app" [ "$(mrc config get WRITEUP_IN)" = app ]

echo "note-path"
notes="$HOME/Notes Vault/meeting-notes"
mkdir -p "$notes" "$HOME/Team Notes/meeting-notes" "$HOME/Team Notes/share"
check "a colon becomes a dash" \
  [ "$(mrc note-path scribe "Acme: check-in")" = "$notes/Acme - check-in.md" ]
check "characters Finder refuses become -" \
  [ "$(mrc note-path scribe "Q3/Q4 plan?")" = "$notes/Q3-Q4 plan-.md" ]
touch "$notes/Acme - check-in.md"
out="$(mrc note-path scribe "Acme: check-in" 2>&1)"; rc=$?
check "a taken name without --date is refused" [ "$rc" -ne 0 ]
check "...asking for the date" has "$out" 'give the meeting'
check "with --date it gets the date" \
  [ "$(mrc note-path scribe "Acme: check-in" --date 2026-11-05)" = "$notes/Acme - check-in (2026-11-05).md" ]
touch "$notes/Acme - check-in (2026-11-05).md"
check "...and a number when that's taken too" \
  [ "$(mrc note-path scribe "Acme: check-in" --date 2026-11-05)" = "$notes/Acme - check-in (2026-11-05) 2.md" ]
touch "$HOME/Team Notes/share/Team — 2026-11-05.md"
check "a team name taken in share/ counts as taken" \
  [ "$(mrc note-path teamnotes "Team — 2026-11-05")" = "$HOME/Team Notes/meeting-notes/Team — 2026-11-05 2.md" ]
out="$(mrc note-path scribe "   " 2>&1)"; rc=$?
check "an empty name is refused" [ "$rc" -ne 0 ]

echo "session-info"
s="$T/sessions/2026-01-02T12-00_acme-check-in"
mkdir -p "$s"
cat > "$s/session.json" <<'EOF'
{"title": "Acme check-in", "started": "2026-01-02T12:00:00Z", "tracks": ["mic", "system"],
 "checks": {"mic": {"peak_dbfs": -18.5, "audio_seconds": 1800},
            "system": {"peak_dbfs": -91.0, "audio_seconds": 1800}},
 "warnings": ["tracks started 3 s apart"]}
EOF
out="$(mrc session-info "$s")"
check "prints the title typed at record time" has "$out" '^TITLE=Acme check-in$'
check "...the date" has "$out" '^DATE=2026-01-02$'
check "...and the tracks" has "$out" '^TRACKS=mic,system$'
check "a track below -60 dBFS is SILENT" has "$out" '^SILENT system$'
check "...and a healthy one isn't" bash -c '! grep -q "^SILENT mic$" <<< "$1"' _ "$out"
check "warnings are passed on" has "$out" '^WARNING tracks started 3 s apart$'
s="$T/sessions/2026-01-03T09-00_weekly-sync"
mkdir -p "$s"; : > "$s/mic.wav"
out="$(mrc session-info "$s")"
check "no session.json: says so" has "$out" '^NO SESSION FILE$'
check "...and works the title, date and tracks out from the folder" \
  bash -c 'grep -qx "TITLE=weekly sync" <<< "$1" && grep -qx "DATE=2026-01-03" <<< "$1" && grep -qx "TRACKS=mic" <<< "$1"' _ "$out"

echo "prepare"
inbox2="$T/inbox-prepare"
mkdir -p "$inbox2/2026-01-04T10-00_standup"
: > "$inbox2/phone call.m4a"; : > "$inbox2/agenda.pdf"
mrc config set OUTPUT_ROOT "$inbox2" >/dev/null
out="$(mrc prepare scribe 2>&1)"
check "a saved notes folder says VAULT_SAVED=yes" has "$out" '^VAULT_SAVED=yes$'
check "a fresh personal.md asks for the name" has "$out" '^NAME NEEDED$'
check "session folders are listed" has "$out" '^INPUT session .*_standup$'
check "...before single files" \
  bash -c '[ "$(grep -n "^INPUT session" <<< "$1" | cut -d: -f1)" -lt "$(grep -n "^INPUT file" <<< "$1" | cut -d: -f1)" ]' _ "$out"
check "...and files that aren't audio or text aren't" bash -c '! grep -q "agenda.pdf" <<< "$1"' _ "$out"
rm -rf "$inbox2"
out="$(mrc prepare scribe 2>&1)"
check "a missing inbox says MISSING INBOX" has "$out" '^MISSING INBOX$'
out="$(mrc prepare teamnotes 2>&1)"
check "no team.md yet: PROFILE team NOT SET UP" has "$out" '^PROFILE team NOT SET UP$'
check "...and the other profile is listed" has "$out" '^PROFILE other '

echo "transcribe: the names prompt"
long="$(python3 -c 'print(", ".join(["Siobhan Ó Súilleabháin"] * 40))')"
out="$(mrc transcribe "$T/missing.wav" --prompt "$long" 2>&1)"
check "a prompt over Whisper's budget gets a warning" has "$out" 'names prompt is about'
check "...before the usual error" has "$out" 'no such file'
out="$(mrc transcribe "$T/missing.wav" --prompt "Alice, Bob, Acme Health" 2>&1)"
check "a short prompt doesn't" bash -c '! grep -q "names prompt" <<< "$1"' _ "$out"
: > "$T/already.txt"
out="$(mrc transcribe "$T/already.txt" --prompt "$long" 2>&1)"
check "a transcript doesn't, since Whisper isn't run" bash -c '! grep -q "names prompt" <<< "$1"' _ "$out"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
