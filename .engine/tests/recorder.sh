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
T="$(mktemp -d "${TMPDIR:-/tmp}/meetingrec-test.XXXXXX")"
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
# For prepare: the settings templates and the skills (with their starters).
for kind in scribe teamnotes; do
  mkdir -p "$REPO/$kind/settings/profiles"
  cp "$SRC/$kind/settings/"*.md "$REPO/$kind/settings/"
  cp -R "$SRC/$kind/.claude" "$REPO/$kind/.claude"
done
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
# SIGINT or SIGTERM, then fixes the header and exits 0, like the real one.
cat > "$STUBS/ffmpeg" <<'PY'
#!/usr/bin/env python3
import math, signal, struct, sys, time
out, rate = sys.argv[-1], 16000
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
n = 0
def stop(*_):
    f.seek(0); f.write(header(n)); f.close(); sys.exit(0)
# Set explicitly: a background job inherits SIGINT as ignored.
signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)
while True:
    f.write(chunk); f.flush(); n += len(chunk); time.sleep(0.1)
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

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
