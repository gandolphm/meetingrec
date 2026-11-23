#!/usr/bin/env bash
# transcribe.sh — turn an audio file into a timestamped SRT transcript.
#
# Usage:
#   transcribe.sh <audio_path> <out_dir> [model] [prompt]
#
#   audio_path : .m4a/.mp3/.wav/.mp4/etc.
#   out_dir    : where <file name>.meetingrec.srt lands (call.m4a.meetingrec.srt)
#   model      : whisper model name (default: small.en)
#   prompt     : optional priming text (names/jargon) to improve recognition
#
# Runs whisper.cpp's `whisper-cli` (Metal-accelerated), the copy install.sh
# downloads or Homebrew's. Exits non-zero with a clear reason if it, ffmpeg or
# the model file is missing.
#
# Exit codes: 0 ok · 1 transcribe failed · 2 no engine or no ffmpeg · 3 model not found
set -euo pipefail

# ffmpeg and whisper-cli are the copies install.sh downloads, kept off the user's
# PATH; Homebrew's are the fallback on a Mac that installed them that way.
PATH="$HOME/.local/share/meetingrec/bin:$PATH:/opt/homebrew/bin:/usr/local/bin"

AUDIO="${1:?audio path required}"
OUTDIR="${2:?output dir required}"
MODEL="${3:-small.en}"
PROMPT="${4:-}"

mkdir -p "$OUTDIR"
# Everything this writes is named after the whole file name plus .meetingrec:
# call.m4a gives call.m4a.meetingrec.srt. Never call.srt, which may be a
# transcript the user dropped in too (a phone app's export); and not
# call.meetingrec.srt, which call.wav beside it would share.
BASE="$(basename "$AUDIO").meetingrec"
SRT="$OUTDIR/$BASE.srt"

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "NO_ENGINE" >&2
  echo "Run meetingrec's install.sh again (or: meetingrec update) to get whisper-cli." >&2
  exit 2
fi

# Located before any audio is converted, so a missing model costs nothing.
MODELFILE=""
for d in "$HOME/.local/share/meetingrec/models" "$HOME/.whisper-models" \
         "/opt/homebrew/share/whisper-cpp/models" \
         "/usr/local/share/whisper-cpp/models" "./models" "."; do
  if [ -f "$d/ggml-$MODEL.bin" ]; then MODELFILE="$d/ggml-$MODEL.bin"; break; fi
done
if [ -z "$MODELFILE" ]; then
  echo "MODEL_NOT_FOUND ggml-$MODEL.bin" >&2
  echo "Get it with:" >&2
  echo "  mkdir -p ~/.local/share/meetingrec/models && curl -L -o ~/.local/share/meetingrec/models/ggml-$MODEL.bin \\" >&2
  echo "    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin" >&2
  exit 3
fi

# whisper-cli needs 16 kHz mono 16-bit PCM WAV. meetingrec's own tracks (and the
# speech-only copies transcribe_session.py makes of them) already are, so they go
# straight in; anything else (an .m4a, a 48 kHz WAV) is converted first.
WAV="$AUDIO"
MADE_WAV=0
if ! python3 -c '
import sys, wave
try:
    with wave.open(sys.argv[1], "rb") as w:
        ok = (w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getcomptype()) == (16000, 1, 2, "NONE")
except Exception:
    sys.exit(1)
sys.exit(0 if ok else 1)' "$AUDIO" 2>/dev/null; then
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "NO_FFMPEG  (run meetingrec's install.sh again, or: meetingrec update)" >&2; exit 2
  fi
  WAV="$OUTDIR/$BASE.16k.wav"
  ffmpeg -nostdin -y -v error -i "$AUDIO" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV"
  MADE_WAV=1
fi

ARGS=(-m "$MODELFILE" -f "$WAV" -osrt -of "$OUTDIR/$BASE")
[ -n "$PROMPT" ] && ARGS+=(--prompt "$PROMPT")
# Inside an agent's sandbox (Codex's sets CODEX_SANDBOX) whisper-cli can't set up
# the GPU, and instead of falling back to the CPU it crashes ("failed to allocate
# Metal buffer"). So in Codex's sandbox it goes straight to the CPU (-ng), and
# anywhere else a failed run is tried once more on the CPU: about 2.4x slower,
# but a transcript instead of a crash.
rc=0
if [ -n "${CODEX_SANDBOX:-}" ]; then
  echo "NO_GPU running in a sandbox, so Whisper runs on the CPU (slower)"
  whisper-cli "${ARGS[@]}" -ng >/dev/null || rc=$?
else
  whisper-cli "${ARGS[@]}" >/dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "NO_GPU whisper-cli failed on the GPU (exit $rc), so it ran again on the CPU (slower)"
    rm -f "$SRT"
    rc=0
    whisper-cli "${ARGS[@]}" -ng >/dev/null || rc=$?
  fi
fi
# Only ever the converted copy: when the input went straight in, WAV is the input.
[ "$MADE_WAV" -eq 1 ] && rm -f "$WAV"
[ "$rc" -eq 0 ] || { echo "TRANSCRIBE_FAILED (whisper-cli exited $rc)" >&2; exit 1; }

if [ -f "$SRT" ]; then echo "OK $SRT"; else echo "TRANSCRIBE_FAILED" >&2; exit 1; fi
