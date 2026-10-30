#!/usr/bin/env bash
#
# build-ffmpeg.sh VERSION OUTDIR — build the small ffmpeg meetingrec needs.
#
# Run by .github/workflows/build-ffmpeg.yml, and by hand to try a new version.
# Writes OUTDIR/ffmpeg and OUTDIR/LICENSE-ffmpeg.txt.
#
# Everything meetingrec asks of ffmpeg is built in: microphone capture
# (avfoundation), raw and WAV audio, resampling, the silencedetect filter, and
# decoding phone recordings (m4a, mp3, mp4…). So no outside libraries are
# linked, and without --enable-gpl the result is LGPL, which may be shared as
# long as the licence and the exact source travel with it. Homebrew's ffmpeg is
# GPL and links eleven libraries; nothing here needs them.
set -euo pipefail

version="${1:?usage: build-ffmpeg.sh VERSION OUTDIR}"
mkdir -p "${2:?usage: build-ffmpeg.sh VERSION OUTDIR}"
out="$(cd "$2" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "n$version" \
  https://github.com/FFmpeg/FFmpeg.git "$work/src" 2>"$work/clone.log" \
  || { cat "$work/clone.log"; exit 1; }
cd "$work/src"

flags=(
  --disable-autodetect          # link nothing that merely happens to be installed
  --enable-avfoundation         # microphone capture
  --disable-ffplay --disable-ffprobe
  --disable-doc --disable-network --disable-debug
  --extra-cflags=-mmacosx-version-min=14.2
  --extra-ldflags=-mmacosx-version-min=14.2
)
./configure "${flags[@]}" >"$work/configure.log" 2>&1 \
  || { tail -30 "$work/configure.log"; exit 1; }
make -j"$(sysctl -n hw.ncpu)" >"$work/make.log" 2>&1 \
  || { tail -30 "$work/make.log"; exit 1; }
cp ffmpeg "$out/ffmpeg"

{
  echo "ffmpeg $version, built unmodified from https://github.com/FFmpeg/FFmpeg/tree/n$version"
  echo "Configured with: ./configure ${flags[*]}"
  echo "Build script: .engine/tools/build-ffmpeg.sh in https://github.com/gandolphm/meetingrec"
  echo
  echo "FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later."
  echo "Its full text follows."
  echo
  cat COPYING.LGPLv2.1
} > "$out/LICENSE-ffmpeg.txt"
