#!/usr/bin/env bash
#
# build-ffmpeg.sh VERSION OUTDIR — build the small ffmpeg meetingrec needs.
#
# Run by .github/workflows/build-ffmpeg.yml, and by hand to try a new version.
# Writes OUTDIR/ffmpeg, OUTDIR/LICENSE-ffmpeg.txt and a copy of each patch.
#
# FFmpeg's source is changed by the ffmpeg-*.patch files beside this script,
# and by nothing else. Each one says at its top what it fixes and why. A patch
# that no longer applies stops the build: read what changed in FFmpeg before
# touching it, because the fix may have arrived there, or moved.
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
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "n$version" \
  https://github.com/FFmpeg/FFmpeg.git "$work/src" 2>"$work/clone.log" \
  || { cat "$work/clone.log"; exit 1; }
cd "$work/src"

patches=()
for patch in "$here"/ffmpeg-*.patch; do
  [ -e "$patch" ] || continue
  git apply "$patch" || { echo "$(basename "$patch") doesn't apply to FFmpeg n$version"; exit 1; }
  cp "$patch" "$out/"
  patches+=("$(basename "$patch")")
done

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
  if [ "${#patches[@]}" -eq 0 ]; then
    echo "ffmpeg $version, built unmodified from https://github.com/FFmpeg/FFmpeg/tree/n$version"
  else
    echo "ffmpeg $version, built from https://github.com/FFmpeg/FFmpeg/tree/n$version"
    echo "with these changes to its source, each published next to this file and in"
    echo ".engine/tools/ in https://github.com/gandolphm/meetingrec:"
    printf '  %s\n' "${patches[@]}"
  fi
  echo "Configured with: ./configure ${flags[*]}"
  echo "Build script: .engine/tools/build-ffmpeg.sh in https://github.com/gandolphm/meetingrec"
  echo
  echo "FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later."
  echo "Its full text follows."
  echo
  cat COPYING.LGPLv2.1
} > "$out/LICENSE-ffmpeg.txt"
