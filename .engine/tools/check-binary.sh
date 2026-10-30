#!/usr/bin/env bash
#
# check-binary.sh FILE — refuse a build that wouldn't run on every Mac
# meetingrec supports: arm64 only, macOS 14.2 or later, and linked against
# nothing but macOS itself (a Homebrew library would be missing on most Macs).
set -euo pipefail
f="${1:?usage: check-binary.sh FILE}"

lipo -archs "$f" | grep -qx arm64 || { echo "$f: not an arm64-only binary"; exit 1; }
minos="$(vtool -show-build "$f" | awk '/minos/ { print $2; exit }')"
[ "$minos" = "14.2" ] || { echo "$f: minimum macOS is $minos, expected 14.2"; exit 1; }
other="$(otool -L "$f" | tail -n +2 | awk '{ print $1 }' | grep -vE '^(/usr/lib/|/System/Library/)' || true)"
[ -z "$other" ] || { echo "$f: links libraries macOS doesn't have:"; echo "$other"; exit 1; }
echo "$f: arm64, macOS $minos+, $(du -h "$f" | cut -f1 | tr -d ' '), system libraries only"
