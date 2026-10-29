#!/usr/bin/env bash
#
# install.sh — set up meetingrec on a Mac in one go.
#
#   curl -fsSL https://raw.githubusercontent.com/gandolphm/meetingrec/main/install.sh | bash
#   ./install.sh                      # or run it from a clone
#
# Does the README's manual install steps 1–4 and 6, then walks you through a
# test recording from the menu-bar button and checks it.
#
# Safe to re-run: every step checks whether it's already done and skips it, so
# if anything fails, fix it and run the same command again.
#
# Environment:
#   MEETINGREC_DIR    where to clone the repo when piped from curl (default ~/meetingrec)
#   NO_HAMMERSPOON=1  skip the menu-bar button (use bin/meetingrec from Terminal)
#   AUDIOTEE_FROM_SOURCE=1  build audiotee yourself instead of downloading it
#
set -uo pipefail

REPO_URL="https://github.com/gandolphm/meetingrec.git"
AUDIOTEE_URL="https://github.com/makeusabrew/audiotee.git"
# Prebuilt copies, made by .github/workflows/build-audiotee.yml.
AUDIOTEE_RELEASES="https://github.com/gandolphm/meetingrec/releases/download"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
MODEL_FILE="$HOME/.whisper-models/ggml-small.en.bin"
# From Hugging Face's X-Linked-ETag for that file. A truncated or swapped
# download fails here instead of later, mid-transcription.
MODEL_SHA256="c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
BREW="/opt/homebrew/bin/brew"

# Captured at top level: inside main, BASH_SOURCE no longer says whether we
# were run from a file or piped from curl.
SCRIPT_PATH="${BASH_SOURCE[0]:-}"

if [ -t 1 ]; then
  B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'
else
  B="" G="" Y="" R="" N=""
fi

step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
note() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  {
  printf '\n  %s✗ %s%s\n' "$R" "$*" "$N" >&2
  printf '\n  Fix the problem above, then run the same install command again.\n' >&2
  printf '  Steps that already finished will be skipped.\n' >&2
  exit 1
}

# Add a line to a shell startup file unless it's already there.
add_line() {
  local file="$1" line="$2"
  touch "$file"
  grep -qxF "$line" "$file" || printf '\n%s\n' "$line" >> "$file"
}

# ---------------------------------------------------------------------------

check_mac() {
  step "Checking this Mac"
  [ "$(uname -s)" = "Darwin" ] || die "meetingrec only runs on macOS."
  # sysctl, not uname -m: a Terminal running under Rosetta reports x86_64.
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] || die "meetingrec needs a Mac with Apple silicon (M1 or later)."
  local v major minor
  v="$(sw_vers -productVersion)"
  major="${v%%.*}"; minor="$(printf '%s' "$v" | cut -d. -f2)"; minor="${minor:-0}"
  if [ "$major" -lt 14 ] || { [ "$major" -eq 14 ] && [ "$minor" -lt 2 ]; }; then
    die "macOS $v is too old. System-audio capture needs macOS 14.2 or later."
  fi
  ok "macOS $v on Apple silicon"
}

install_clt() {
  step "Xcode Command Line Tools (git, Swift, python3)"
  if xcode-select -p >/dev/null 2>&1; then
    ok "already installed"
    return
  fi
  xcode-select --install >/dev/null 2>&1
  note "A window opened asking to install the command line developer tools."
  note "Click Install and agree. This takes 5–15 minutes; this script waits for it."
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
  ok "installed"
}

install_brew() {
  step "Homebrew (package manager)"
  if [ ! -x "$BREW" ]; then
    note "Installing Homebrew. It will ask for your Mac password (typing shows nothing; that's normal)."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "Homebrew didn't install."
    [ -x "$BREW" ] || die "Homebrew finished but $BREW isn't there."
    ok "installed"
  else
    ok "already installed"
  fi
  eval "$("$BREW" shellenv)"
  # What the Homebrew installer's "Next steps" ask you to do by hand.
  add_line "$HOME/.zprofile" "eval \"\$($BREW shellenv)\""
}

install_formulae() {
  step "ffmpeg and whisper.cpp"
  local f
  for f in ffmpeg whisper-cpp; do
    if brew list --formula "$f" >/dev/null 2>&1; then
      ok "$f already installed"
    else
      note "installing $f (a few minutes)…"
      brew install --quiet "$f" || die "brew install $f failed."
      ok "$f installed"
    fi
  done
}

install_hammerspoon_app() {
  [ -n "${NO_HAMMERSPOON:-}" ] && return
  step "Hammerspoon (menu-bar button)"
  if [ -d /Applications/Hammerspoon.app ]; then
    ok "already installed"
  else
    brew install --quiet --cask hammerspoon || die "brew install --cask hammerspoon failed."
    ok "installed"
  fi
}

get_repo() {
  step "meetingrec"
  local here=""
  [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ] && here="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  if [ -n "$here" ] && [ -f "$here/bin/meetingrec" ]; then
    REPO="$here"
    ok "using this copy: $REPO"
  else
    REPO="${MEETINGREC_DIR:-$HOME/meetingrec}"
    if [ -f "$REPO/bin/meetingrec" ]; then
      # Not pulled: re-running the installer never changes the code under you.
      ok "already downloaded: $REPO"
    elif [ -e "$REPO" ]; then
      die "$REPO already exists and isn't meetingrec. Move it, or set MEETINGREC_DIR to another folder."
    else
      git clone --quiet "$REPO_URL" "$REPO" || die "Couldn't download meetingrec from $REPO_URL."
      ok "downloaded to $REPO"
    fi
  fi
  chmod +x "$REPO"/bin/*
}

install_model() {
  step "Whisper model (small.en, 465 MB)"
  if [ -f "$MODEL_FILE" ]; then
    ok "already downloaded"
    return
  fi
  mkdir -p "$(dirname "$MODEL_FILE")"
  curl -fL --progress-bar -o "$MODEL_FILE.part" "$MODEL_URL" || die "Model download failed (check your internet connection)."
  if [ "$(shasum -a 256 "$MODEL_FILE.part" | cut -d' ' -f1)" != "$MODEL_SHA256" ]; then
    rm -f "$MODEL_FILE.part"
    die "The downloaded model is corrupt (checksum mismatch)."
  fi
  mv "$MODEL_FILE.part" "$MODEL_FILE"
  ok "downloaded and verified"
}

install_audiotee() {
  step "audiotee (system-audio capture)"
  # The pinned commit lives in config.example.sh, so the build and the
  # version recorded in session.json can't drift apart.
  local sha sha256 bin="$HOME/bin/audiotee"
  sha="$(sed -n 's/^AUDIOTEE_SHA="\(.*\)"/\1/p' "$REPO/config.example.sh")"
  sha256="$(sed -n 's/^AUDIOTEE_SHA256="\(.*\)"/\1/p' "$REPO/config.example.sh")"
  [ -n "$sha" ] || die "Couldn't read AUDIOTEE_SHA from $REPO/config.example.sh."
  mkdir -p "$HOME/bin"

  if [ -n "$sha256" ] && [ -z "${AUDIOTEE_FROM_SOURCE:-}" ]; then
    if [ -x "$bin" ] && [ "$(shasum -a 256 "$bin" | cut -d' ' -f1)" = "$sha256" ]; then
      ok "already installed at commit $sha"
      return
    fi
    if download_audiotee "$sha" "$sha256" "$bin"; then
      ok "downloaded commit $sha (verified) → $bin"
      return
    fi
    note "couldn't download a verified copy; building it here instead"
  fi
  build_audiotee "$sha" "$bin"
}

# The download is checked against AUDIOTEE_SHA256 before it replaces anything,
# so a truncated or swapped file never ends up in ~/bin.
download_audiotee() {
  local sha="$1" sha256="$2" bin="$3"
  curl -fsSL -o "$bin.part" "$AUDIOTEE_RELEASES/audiotee-$sha/audiotee" || { rm -f "$bin.part"; return 1; }
  if [ "$(shasum -a 256 "$bin.part" | cut -d' ' -f1)" != "$sha256" ]; then
    rm -f "$bin.part"
    return 1
  fi
  chmod +x "$bin.part" && mv "$bin.part" "$bin"
}

build_audiotee() {
  local sha="$1" bin="$2" src="$HOME/src/audiotee"
  if [ -x "$bin" ] && [ "$(git -C "$src" rev-parse --short=7 HEAD 2>/dev/null)" = "$sha" ]; then
    ok "already built at commit $sha"
    return
  fi
  mkdir -p "$HOME/src"
  if [ ! -d "$src/.git" ]; then
    git clone --quiet "$AUDIOTEE_URL" "$src" || die "Couldn't download audiotee."
  fi
  git -C "$src" fetch --quiet origin || die "Couldn't update audiotee."
  git -C "$src" -c advice.detachedHead=false checkout --quiet "$sha" || die "Couldn't check out audiotee commit $sha."
  note "building (a minute or two)…"
  (cd "$src" && swift build -c release >"$src/build.log" 2>&1) \
    || die "audiotee didn't build. The compiler output is in $src/build.log."
  cp "$src/.build/release/audiotee" "$bin" || die "Couldn't copy audiotee to $bin."
  ok "built commit $sha → $bin"
}

install_config() {
  step "Recorder config"
  local cfg="$HOME/.config/meetingrec/config.sh"
  if [ -f "$cfg" ]; then
    ok "keeping your existing $cfg"
  else
    mkdir -p "$(dirname "$cfg")"
    cp "$REPO/config.example.sh" "$cfg"
    ok "created $cfg"
  fi
}

install_personal_files() {
  step "Your name tables and team profile"
  # Git ignores these, so they can't come down with the clone: each is copied
  # from its tracked template. The skills do the same on first run, so this
  # only saves a step. Existing copies are never touched.
  local tmpl copy made=0
  for tmpl in \
      "$REPO/scribe/.claude/skills/meeting-notes/reference/names.local.example.md" \
      "$REPO/teamnotes/.claude/skills/team-notes/reference/names.local.example.md" \
      "$REPO/teamnotes/.claude/skills/team-notes/profiles/team.example.md"; do
    copy="${tmpl%.example.md}.md"
    [ -f "$copy" ] && continue
    cp "$tmpl" "$copy" || die "Couldn't create $copy."
    made=1
  done
  if [ "$made" -eq 1 ]; then
    ok "created. Claude fills them in the first time you write up a meeting"
  else
    ok "keeping your existing files"
  fi
}

install_claude() {
  step "Claude Code"
  if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
    ok "already installed"
  else
    curl -fsSL https://claude.ai/install.sh | bash || die "Claude Code didn't install."
    ok "installed"
  fi
  if [ -x "$HOME/.local/bin/claude" ] \
     && ! grep -qs '\.local/bin' "$HOME/.zprofile" "$HOME/.zshrc"; then
    add_line "$HOME/.zprofile" 'export PATH="$HOME/.local/bin:$PATH"'
  fi
}

install_hammerspoon_config() {
  [ -n "${NO_HAMMERSPOON:-}" ] && return
  step "Menu-bar button config"
  local dir="$HOME/.hammerspoon" target
  mkdir -p "$dir"
  # Never overwrite someone's own Hammerspoon config: load ours from it instead.
  if [ ! -f "$dir/init.lua" ] || grep -q '^-- MeetingRec menu bar' "$dir/init.lua"; then
    target="$dir/init.lua"
  else
    target="$dir/meetingrec.lua"
    add_line "$dir/init.lua" 'require("meetingrec")'
    note "you already had a Hammerspoon config; added require(\"meetingrec\") to it"
  fi
  sed "s|^local REPO = .*|local REPO = \"$REPO\"|" "$REPO/hammerspoon/init.lua" > "$target"
  ok "wrote $target"

  # Restart so the new config loads. killall rather than osascript: telling
  # another app to quit would trigger an Automation permission prompt.
  if pgrep -x Hammerspoon >/dev/null; then
    killall Hammerspoon 2>/dev/null
    sleep 1
  fi
  open -a Hammerspoon
  ok "started Hammerspoon. A ○ should appear in your menu bar"
  note "If Hammerspoon asks for Accessibility access, you can click Deny. It isn't needed."
}

test_recording() {
  [ -n "${NO_HAMMERSPOON:-}" ] && return
  # No keyboard to answer with (e.g. CI): skip rather than hang.
  [ -t 0 ] || return

  step "Test recording (gives the menu-bar button its permissions)"
  cat <<EOF
  macOS asks for permission the first time Hammerspoon records audio.
  Do a short test now so the prompts don't appear during a real call:

    1. Click ○ in the menu bar → Start recording…
    2. Type ${B}test${N} as the title and click Start.
    3. Click ${B}Allow${N} on the Microphone and System Audio Recording prompts.
    4. Play a YouTube video and talk for about 15 seconds.
    5. Click the ● in the menu bar → Stop.

EOF
  local reply
  while :; do
    read -r -p "  Press Enter when you've clicked Stop (or type s to skip): " reply
    if [ "$reply" = "s" ]; then
      note "skipped. Do it later; see step 6 of the README."
      return
    fi
    # Checking (and deleting) a session that's still recording would lose it.
    case "$("$REPO/bin/meetingrec" status 2>/dev/null)" in
      recording*) note "It's still recording. Click the ● in the menu bar → Stop first." ;;
      *) break ;;
    esac
  done

  local inbox="$REPO/scribe/input" session
  session="$(ls -1d "$inbox"/*_test 2>/dev/null | tail -n 1)"
  if [ -z "$session" ] || [ ! -f "$session/session.json" ]; then
    note "No finished test recording found in $inbox."
    note "Do the test later; see step 6 of the README."
    return
  fi

  local warnings
  warnings="$(python3 -c 'import json,sys; [print(w) for w in json.load(open(sys.argv[1])).get("warnings", [])]' \
    "$session/session.json" 2>/dev/null)"
  if [ -n "$warnings" ]; then
    printf '%s\n' "$warnings" | sed "s/^/  ${R}✗${N} /"
    cat <<EOF

  A permission is probably missing. Open System Settings → Privacy & Security:
    • Microphone → turn on Hammerspoon
    • Screen & System Audio Recording → under "System Audio Recording Only",
      add and turn on Hammerspoon
  Then quit Hammerspoon, reopen it, and run this installer again to repeat the test.
  The test recording was kept for reference: $session
EOF
    return
  fi
  rm -rf "$session"
  ok "both tracks recorded audio. Test recording deleted"
}

finish() {
  cat <<EOF

${G}${B}Done.${N} meetingrec is installed in ${B}$REPO${N}

What's left (see the README for details):
  1. Open a ${B}new${N} Terminal window, run ${B}claude${N} once and sign in.
  2. Set up Obsidian (README step 7).

The first time you write up a meeting, Claude asks your name (and, for team
notes, your team's roster) and saves it for next time.

To write notes after a meeting:  cd "$REPO/scribe" && claude   then type: scribe
EOF
}

main() {
  check_mac
  install_clt
  install_brew
  install_formulae
  install_hammerspoon_app
  get_repo
  install_model
  install_audiotee
  install_config
  install_personal_files
  install_claude
  install_hammerspoon_config
  test_recording
  finish
}

# Everything is in functions so a partly downloaded script does nothing.
# Under `curl | bash` stdin is the script itself, so prompts read the keyboard.
if [ -t 0 ] || ! (: </dev/tty) 2>/dev/null; then
  main "$@"
else
  main "$@" </dev/tty
fi
