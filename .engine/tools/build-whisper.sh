#!/usr/bin/env bash
#
# build-whisper.sh VERSION OUTDIR — build whisper.cpp's whisper-cli for Apple silicon.
#
# Run by .github/workflows/build-whisper.yml, and by hand to try a new version.
# Writes OUTDIR/whisper-cli and OUTDIR/LICENSE-whisper.cpp.txt. Needs cmake.
#
# whisper.cpp publishes a Mac library (an xcframework) but no Mac command-line
# program, so it's built here: one file, with the Metal (GPU) code embedded and
# nothing linked beyond what macOS provides.
set -euo pipefail

version="${1:?usage: build-whisper.sh VERSION OUTDIR}"
mkdir -p "${2:?usage: build-whisper.sh VERSION OUTDIR}"
out="$(cd "$2" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$version" \
  https://github.com/ggml-org/whisper.cpp.git "$work/src" 2>"$work/clone.log" \
  || { cat "$work/clone.log"; exit 1; }

# GGML_NATIVE=OFF: tuned for the build machine's own chip, the binary could use
# instructions an older M1 lacks.
cmake -S "$work/src" -B "$work/build" -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.2 >"$work/cmake.log" 2>&1 \
  || { tail -30 "$work/cmake.log"; exit 1; }
cmake --build "$work/build" --config Release -j"$(sysctl -n hw.ncpu)" --target whisper-cli \
  >"$work/build.log" 2>&1 || { tail -30 "$work/build.log"; exit 1; }
cp "$work/build/bin/whisper-cli" "$out/whisper-cli"

{
  echo "whisper-cli from whisper.cpp $version, built unmodified from"
  echo "https://github.com/ggml-org/whisper.cpp/tree/$version"
  echo "Build script: .engine/tools/build-whisper.sh in https://github.com/gandolphm/meetingrec"
  echo
  cat "$work/src/LICENSE"
} > "$out/LICENSE-whisper.cpp.txt"
