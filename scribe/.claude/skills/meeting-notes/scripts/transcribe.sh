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
# Picks whisper.cpp (fast, Metal-accelerated) if `whisper-cli` is on PATH,
# else falls back to openai-whisper (`whisper`). Exits non-zero with a clear
# reason if neither engine or the model file is available.
#
# Exit codes: 0 ok · 1 transcribe failed · 2 no engine · 3 model not found
set -euo pipefail

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
    echo "NO_FFMPEG  (brew install ffmpeg)" >&2; exit 2
  fi
  WAV="$OUTDIR/$BASE.16k.wav"
  ffmpeg -nostdin -y -v error -i "$AUDIO" -ar 16000 -ac 1 "$WAV"

  # Locate a ggml model file in common spots.
  MODELFILE=""
  for d in "$HOME/.whisper-models" "/opt/homebrew/share/whisper-cpp/models" \
           "/usr/local/share/whisper-cpp/models" "./models" "."; do
    if [ -f "$d/ggml-$MODEL.bin" ]; then MODELFILE="$d/ggml-$MODEL.bin"; break; fi
  done
  if [ -z "$MODELFILE" ]; then
    echo "MODEL_NOT_FOUND ggml-$MODEL.bin" >&2
    echo "Get it with:" >&2
    echo "  mkdir -p ~/.whisper-models && curl -L -o ~/.whisper-models/ggml-$MODEL.bin \\" >&2
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
  echo "Install one of:" >&2
  echo "  brew install whisper.cpp    # fast, Metal-accelerated (recommended on Apple Silicon)" >&2
  echo "  pip install openai-whisper  # simple, pure Python" >&2
  exit 2
fi

if [ -f "$SRT" ]; then echo "OK $SRT"; else echo "TRANSCRIBE_FAILED" >&2; exit 1; fi
