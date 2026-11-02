#!/usr/bin/env bash
# transcribe.sh — turn an audio file into a timestamped SRT transcript.
#
# Usage:
#   transcribe.sh <audio_path> <out_dir> [model] [prompt]
#
#   audio_path : .m4a/.mp3/.wav/.mp4/etc.
#   out_dir    : where the .srt lands
#   model      : whisper model name (default: small.en)
#   prompt     : optional priming text (names/jargon) to improve recognition
#
# Picks whisper.cpp (fast, Metal-accelerated) if `whisper-cli` is found, else
# falls back to openai-whisper (`whisper`). Exits non-zero with a clear
# reason if neither engine or the model file is available.
#
# Exit codes: 0 ok · 1 transcribe failed · 2 no engine · 3 model not found
set -euo pipefail

# ffmpeg and whisper-cli are the copies install.sh downloads, kept off the user's
# PATH; Homebrew's are the fallback on a Mac that installed them that way.
PATH="$HOME/.local/share/meetingrec/bin:$PATH:/opt/homebrew/bin:/usr/local/bin"

AUDIO="${1:?audio path required}"
OUTDIR="${2:?output dir required}"
MODEL="${3:-small.en}"
PROMPT="${4:-}"

mkdir -p "$OUTDIR"
BASE="$(basename "${AUDIO%.*}")"
SRT="$OUTDIR/$BASE.srt"

if command -v whisper-cli >/dev/null 2>&1; then
  # --- whisper.cpp path: needs 16kHz mono WAV ---
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "NO_FFMPEG  (run meetingrec's install.sh again, or: meetingrec update)" >&2; exit 2
  fi
  WAV="$OUTDIR/$BASE.16k.wav"
  ffmpeg -nostdin -y -v error -i "$AUDIO" -ar 16000 -ac 1 "$WAV"

  # Locate a ggml model file in common spots.
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
    rm -f "$WAV"; exit 3
  fi

  ARGS=(-m "$MODELFILE" -f "$WAV" -osrt -of "$OUTDIR/$BASE")
  [ -n "$PROMPT" ] && ARGS+=(--prompt "$PROMPT")
  whisper-cli "${ARGS[@]}" >/dev/null
  rm -f "$WAV"

elif command -v whisper >/dev/null 2>&1; then
  # --- openai-whisper path: handles m4a directly, no manual WAV step ---
  ARGS=("$AUDIO" --model "$MODEL" --output_format srt --output_dir "$OUTDIR")
  [ -n "$PROMPT" ] && ARGS+=(--initial_prompt "$PROMPT")
  whisper "${ARGS[@]}" >/dev/null 2>&1

else
  echo "NO_ENGINE" >&2
  echo "Run meetingrec's install.sh again (or: meetingrec update) to get whisper-cli." >&2
  exit 2
fi

if [ -f "$SRT" ]; then echo "OK $SRT"; else echo "TRANSCRIBE_FAILED" >&2; exit 1; fi
