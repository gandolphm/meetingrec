#!/usr/bin/env bash
#
# install.sh — set up meetingrec on a Mac in one go.
#
#   curl -fsSL https://raw.githubusercontent.com/gandolphm/meetingrec/main/.engine/install.sh | bash
#   .engine/install.sh                # or run it from a clone
#   .engine/install.sh --update             # what `meetingrec update` runs after pulling
#
# Does the steps in .engine/docs/manual-install.md, then walks you through a
# test recording from the menu-bar button and checks it.
#
# Safe to re-run: every step checks whether it's already done and skips it, so
# if anything fails, fix it and run the same command again.
#
# Environment:
#   MEETINGREC_DIR    where to clone the repo when piped from curl, instead of asking
#                     (default ~/meetingrec)
#   NO_HAMMERSPOON=1  skip the menu-bar button (use the meetingrec command from Terminal)
#   AUDIOTEE_FROM_SOURCE=1  build audiotee yourself instead of downloading it
#   USE_HOMEBREW=1    use Homebrew's ffmpeg, whisper.cpp and Hammerspoon instead of
#                     meetingrec's pinned downloads. Remembered in config.sh, so
#                     updates keep doing it; USE_HOMEBREW=0 switches back.
#
set -uo pipefail

REPO_URL="https://github.com/gandolphm/meetingrec.git"
AUDIOTEE_URL="https://github.com/makeusabrew/audiotee.git"
# Prebuilt audiotee, ffmpeg and whisper-cli, made by .github/workflows/build-*.yml.
RELEASES="https://github.com/gandolphm/meetingrec/releases/download"
# Everything the installer downloads or builds lives in one folder, so
# `meetingrec uninstall` can remove it in one go and the home folder stays tidy.
DATA_DIR="$HOME/.local/share/meetingrec"
# ffmpeg, whisper-cli and audiotee go here, off the PATH, so someone who uses a
# fuller ffmpeg from Homebrew for other work keeps getting that one.
# meetingrec's own scripts look here first.
TOOLS_DIR="$DATA_DIR/bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
MODEL_FILE="$DATA_DIR/models/ggml-small.en.bin"
# What this installer added that wasn't there before, one "<what> <detail>" per
# line, so uninstall removes those and never something you already had.
RECORD="$DATA_DIR/install-record"
# From Hugging Face's X-Linked-ETag for that file. A truncated or swapped
# download fails here instead of later, mid-transcription.
MODEL_SHA256="c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
# Used when USE_HOMEBREW is on, and as a fallback on a Mac that already has it.
BREW="/opt/homebrew/bin/brew"

# Captured at top level: inside main, BASH_SOURCE no longer says whether we
# were run from a file or piped from curl.
SCRIPT_PATH="${BASH_SOURCE[0]:-}"

# --update: re-check every step after `meetingrec update` pulled new code, minus
# the parts that only make sense once (the test recording, the welcome text).
# --from-menu: the menu bar started the update and reloads itself afterwards, so
# Hammerspoon must not be restarted underneath it.
UPDATE="" FROM_MENU=""
for arg in "$@"; do
  case "$arg" in
    --update)    UPDATE=1 ;;
    --from-menu) FROM_MENU=1 ;;
  esac
done
# NO_HAMMERSPOON isn't saved anywhere, so an update infers it: no app, no menu bar.
[ -n "$UPDATE" ] && [ ! -d /Applications/Hammerspoon.app ] && [ ! -d "$HOME/Applications/Hammerspoon.app" ] \
  && NO_HAMMERSPOON=1

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
  if [ -n "$UPDATE" ]; then
    printf '\n  Fix the problem above, then run the update again.\n' >&2
  else
    printf '\n  Fix the problem above, then run the same install command again.\n' >&2
  fi
  printf '  Steps that already finished will be skipped.\n' >&2
  exit 1
}

# Whether either zsh startup file already mentions something. Missing files are
# skipped: grep given a missing file reports an error even when the other matches.
in_shell_startup() {
  cat "$HOME/.zprofile" "$HOME/.zshrc" 2>/dev/null | grep -qF -- "$1"
}

# Note something in the install record (see RECORD), once.
record() {
  mkdir -p "$DATA_DIR"
  grep -qxF "$*" "$RECORD" 2>/dev/null || printf '%s\n' "$*" >> "$RECORD"
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
  step "Xcode Command Line Tools (git, python3)"
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

# A pinned value from the repo's config.example.sh.
pin() {
  sed -n "s/^$1=\"\(.*\)\"/\1/p" "$REPO/.engine/config.example.sh"
}

# Download URL to DEST only if its SHA-256 matches, so a truncated or swapped
# file never replaces anything.
download_verified() {
  local url="$1" sha256="$2" dest="$3"
  curl -fsSL -o "$dest.part" "$url" || { rm -f "$dest.part"; return 1; }
  if [ "$(shasum -a 256 "$dest.part" | cut -d' ' -f1)" != "$sha256" ]; then
    rm -f "$dest.part"
    return 1
  fi
  mv "$dest.part" "$dest"
}

# install_tool NAME RELEASE-PATH SHA256 HOMEBREW-FORMULA
install_tool() {
  local name="$1" asset="$2" sha256="$3" formula="$4" dest="$TOOLS_DIR/$1"
  if [ -n "$sha256" ]; then
    if [ -x "$dest" ] && [ "$(shasum -a 256 "$dest" | cut -d' ' -f1)" = "$sha256" ]; then
      ok "$name already installed"
      return
    fi
    if download_verified "$RELEASES/$asset" "$sha256" "$dest" && chmod +x "$dest"; then
      ok "$name downloaded (verified)"
      return
    fi
    note "couldn't download a verified $name"
  fi
  # No prebuilt copy yet, or the download failed: Homebrew, if this Mac has it.
  if [ -x "$BREW" ]; then
    brew_formula "$formula"
    return
  fi
  die "Couldn't download $name. Check your internet connection, then run this again."
}

# Whether to use Homebrew instead of the pinned downloads. USE_HOMEBREW given
# to this run is saved first, so later runs and updates keep the choice.
choose_tool_source() {
  local want=""
  case "${USE_HOMEBREW:-}" in
    1|on|yes|true)  want=on ;;
    0|off|no|false) want=off ;;
    "") ;;
    *) die "USE_HOMEBREW must be 1 (use Homebrew) or 0 (use meetingrec's downloads)." ;;
  esac
  # env -u: this script's own USE_HOMEBREW=1 would otherwise read as the saved value.
  if [ -n "$want" ]; then
    env -u USE_HOMEBREW "$REPO/.engine/bin/meetingrec" config set USE_HOMEBREW "$want" >/dev/null \
      || die "Couldn't save USE_HOMEBREW to your config."
  fi
  HOMEBREW_TOOLS="$(env -u USE_HOMEBREW "$REPO/.engine/bin/meetingrec" config get USE_HOMEBREW)"
}

# Homebrew itself, for USE_HOMEBREW. Its installer asks for a password, which a
# menu-bar update has no way to show.
need_brew() {
  if [ ! -x "$BREW" ]; then
    [ -t 0 ] || die "USE_HOMEBREW is on but Homebrew isn't installed. Run the install command in Terminal."
    note "Installing Homebrew. It will ask for your Mac password (typing shows nothing; that's normal)."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "Homebrew didn't install."
    [ -x "$BREW" ] || die "Homebrew finished but $BREW isn't there."
    ok "Homebrew installed"
  fi
  eval "$("$BREW" shellenv)"
  # What the Homebrew installer's "Next steps" ask you to do by hand, unless
  # it's done already (e.g. in .zshrc).
  in_shell_startup "brew shellenv" || add_line "$HOME/.zprofile" "eval \"\$($BREW shellenv)\""
}

brew_formula() {
  if "$BREW" list --formula "$1" >/dev/null 2>&1; then
    ok "using Homebrew's $1"
  else
    note "installing $1 with Homebrew (a few minutes)…"
    "$BREW" install --quiet "$1" || die "brew install $1 failed."
    record brew-formula "$1"
    ok "$1 installed with Homebrew"
  fi
}

install_tools() {
  step "ffmpeg and whisper.cpp"
  if [ "$HOMEBREW_TOOLS" = on ]; then
    note "USE_HOMEBREW is on: using Homebrew's versions"
    need_brew
    brew_formula ffmpeg
    brew_formula whisper-cpp
    # The scripts look in meetingrec's folder first, so its own copies would
    # still win. Remove just those two; nothing else of the user's.
    rm -f "$TOOLS_DIR/ffmpeg" "$TOOLS_DIR/whisper-cli"
    return
  fi
  mkdir -p "$TOOLS_DIR"
  install_tool ffmpeg "ffmpeg-$(pin FFMPEG_VERSION)/ffmpeg" "$(pin FFMPEG_SHA256)" ffmpeg
  install_tool whisper-cli "whisper-cli-$(pin WHISPER_CPP_VERSION)/whisper-cli" \
    "$(pin WHISPER_CLI_SHA256)" whisper-cpp
}

install_hammerspoon_app() {
  [ -n "${NO_HAMMERSPOON:-}" ] && return
  step "Hammerspoon (menu-bar button)"
  local dir
  for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/Hammerspoon.app" ]; then
      ok "already installed"
      return
    fi
  done
  if [ "$HOMEBREW_TOOLS" = on ]; then
    need_brew
    "$BREW" install --quiet --cask hammerspoon || die "brew install --cask hammerspoon failed."
    record hammerspoon-app brew
    ok "installed with Homebrew"
    return
  fi
  # The zip Hammerspoon's developers publish: signed and notarised by Apple, and
  # it updates itself. Applications needs an administrator; anyone else gets
  # ~/Applications, which works the same.
  local version sha256 tmp dest=/Applications
  version="$(pin HAMMERSPOON_VERSION)"; sha256="$(pin HAMMERSPOON_SHA256)"
  [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
  tmp="$(mktemp -d)"
  download_verified "https://github.com/Hammerspoon/hammerspoon/releases/download/$version/Hammerspoon-$version.zip" \
    "$sha256" "$tmp/Hammerspoon.zip" \
    || { rm -rf "$tmp"; die "Couldn't download Hammerspoon. Check your internet connection, then run this again."; }
  ditto -x -k "$tmp/Hammerspoon.zip" "$dest" || { rm -rf "$tmp"; die "Couldn't unpack Hammerspoon into $dest."; }
  rm -rf "$tmp"
  record hammerspoon-app "$dest/Hammerspoon.app"
  ok "installed in $dest"
}

# A folder as typed at a prompt, as an absolute path: ~ expanded, a relative
# path taken from the home folder, no trailing slash.
expand_folder() {
  local f="${1%/}"
  case "$f" in
    "~")    f="$HOME" ;;
    "~/"*)  f="$HOME/${f#"~/"}" ;;
    /*)     ;;
    *)      f="$HOME/$f" ;;
  esac
  printf '%s\n' "$f"
}

# Where to clone meetingrec when piped from curl. MEETINGREC_DIR answers ahead
# of time; with no keyboard to answer with, the default is used.
choose_repo_dir() {
  local default="$HOME/meetingrec" link reply
  # Re-running after a finished install: offer the folder it's already in.
  link="$(readlink "$HOME/.local/bin/meetingrec" 2>/dev/null)"
  # The link is <folder>/.engine/bin/meetingrec.
  [ -n "$link" ] && [ -f "$link" ] && default="$(dirname "$(dirname "$(dirname "$link")")")"
  REPO="${MEETINGREC_DIR:-$default}"
  [ -n "${MEETINGREC_DIR:-}" ] && return
  [ -t 0 ] || return
  read -r -p "  Where should meetingrec go? Press Enter for ${default/#$HOME/~}, or type a folder: " reply
  [ -n "$reply" ] || return
  reply="$(expand_folder "$reply")"
  # These would break the menu-bar config, which has the path written into it.
  case "$reply" in
    *[\"\|\\\$\`]*) die "Pick a folder whose path has none of these characters: \" | \\ \$ \`" ;;
  esac
  # A folder that already holds other things, like ~/Projects: go inside it.
  if [ -d "$reply" ] && [ ! -f "$reply/.engine/bin/meetingrec" ] && [ -n "$(ls -A "$reply")" ]; then
    reply="$reply/meetingrec"
  fi
  REPO="$reply"
}

get_repo() {
  step "meetingrec"
  local here=""
  [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ] && here="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  # This script lives in <folder>/.engine/.
  if [ -n "$here" ] && [ -f "$here/bin/meetingrec" ]; then
    REPO="$(dirname "$here")"
    ok "using this copy: $REPO"
  else
    choose_repo_dir
    if [ -f "$REPO/.engine/bin/meetingrec" ]; then
      # Not pulled: re-running the installer never changes the code under you.
      ok "already downloaded: $REPO"
    elif [ -e "$REPO" ] && [ -n "$(ls -A "$REPO" 2>/dev/null)" ]; then
      die "$REPO already exists and isn't meetingrec. Move it, or pick another folder."
    else
      git clone --quiet "$REPO_URL" "$REPO" || die "Couldn't download meetingrec from $REPO_URL."
      ok "downloaded to $REPO"
    fi
  fi
  chmod +x "$REPO"/.engine/bin/*
}

# Older installs put audiotee in ~/bin, its source in ~/src and the model in
# ~/.whisper-models. Move them into DATA_DIR instead of downloading them again,
# and drop those folders if that leaves them empty.
move_old_downloads() {
  local cfg="$HOME/.config/meetingrec/config.sh" moved=0
  carry_over() {
    { [ -e "$1" ] && [ ! -e "$2" ]; } || return 0
    [ "$moved" -eq 1 ] || step "Moving downloads into ${DATA_DIR/#$HOME/~}"
    moved=1
    mkdir -p "$(dirname "$2")" && mv "$1" "$2" || die "Couldn't move $1 to $2."
    ok "${1/#$HOME/~} → ${2/#$HOME/~}"
    rmdir "$(dirname "$1")" 2>/dev/null
    return 0
  }
  carry_over "$HOME/.whisper-models/ggml-small.en.bin" "$MODEL_FILE"
  carry_over "$HOME/bin/audiotee" "$TOOLS_DIR/audiotee"
  carry_over "$HOME/bin/audiotee.commit" "$TOOLS_DIR/audiotee.commit"
  carry_over "$HOME/src/audiotee" "$DATA_DIR/src/audiotee"
  # config.sh has the old default written into it.
  if grep -qxF 'AUDIOTEE_BIN="$HOME/bin/audiotee"' "$cfg" 2>/dev/null; then
    sed -i '' 's|^AUDIOTEE_BIN="\$HOME/bin/audiotee"$|AUDIOTEE_BIN="$HOME/.local/share/meetingrec/bin/audiotee"|' "$cfg" \
      || die "Couldn't update AUDIOTEE_BIN in $cfg."
  fi
  return 0
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
  local sha sha256 bin="$TOOLS_DIR/audiotee"
  sha="$(sed -n 's/^AUDIOTEE_SHA="\(.*\)"/\1/p' "$REPO/.engine/config.example.sh")"
  sha256="$(sed -n 's/^AUDIOTEE_SHA256="\(.*\)"/\1/p' "$REPO/.engine/config.example.sh")"
  [ -n "$sha" ] || die "Couldn't read AUDIOTEE_SHA from $REPO/.engine/config.example.sh."
  mkdir -p "$TOOLS_DIR"

  if [ -n "$sha256" ] && [ -z "${AUDIOTEE_FROM_SOURCE:-}" ]; then
    if [ -x "$bin" ] && [ "$(shasum -a 256 "$bin" | cut -d' ' -f1)" = "$sha256" ]; then
      ok "already installed at commit $sha"
    elif download_verified "$RELEASES/audiotee-$sha/audiotee" "$sha256" "$bin" && chmod +x "$bin"; then
      ok "downloaded commit $sha (verified) → $bin"
    else
      note "couldn't download a verified copy; building it here instead"
      build_audiotee "$sha" "$bin"
    fi
  else
    build_audiotee "$sha" "$bin"
  fi
  # bin/meetingrec reads this into session.json. Unlike the copy in config.sh,
  # it's rewritten whenever an update installs a different commit.
  printf '%s\n' "$sha" > "$bin.commit"
}

build_audiotee() {
  local sha="$1" bin="$2" src="$DATA_DIR/src/audiotee"
  if [ -x "$bin" ] && [ "$(git -C "$src" rev-parse --short=7 HEAD 2>/dev/null)" = "$sha" ]; then
    ok "already built at commit $sha"
    return
  fi
  mkdir -p "$(dirname "$src")"
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
    cp "$REPO/.engine/config.example.sh" "$cfg"
    ok "created $cfg"
  fi
}

# Where personal notes go, saved as NOTES_VAULT: the same question the
# meeting-notes skill asks on its first run, which it then skips. Team notes
# are left to the team-notes skill, since many people never use them.
choose_notes_dir() {
  [ -n "$UPDATE" ] && return
  local mr="$REPO/.engine/bin/meetingrec" current reply out yn
  if current="$("$mr" config get NOTES_VAULT)"; then
    step "Your notes"
    ok "notes go in ${current/#$HOME/~}/meeting-notes"
    return
  fi
  # No keyboard: the skill asks on the first write-up instead.
  [ -t 0 ] || return
  step "Your notes"
  cat <<EOF
  Where should your meeting notes go?
    Press Enter for meetingrec's scribe folder (${current/#$HOME/~}).
    It's already an Obsidian vault with a notes table and a to-do dashboard.
    Or type the folder of an Obsidian vault you already use. Notes go in a
    meeting-notes folder inside it.

EOF
  while :; do
    read -r -p "  > " reply
    if [ -z "$reply" ]; then
      "$mr" config set NOTES_VAULT "" >/dev/null || die "Couldn't save NOTES_VAULT to your config."
      ok "notes go in ${current/#$HOME/~}/meeting-notes"
      return
    fi
    reply="$(expand_folder "$reply")"
    case "$reply" in
      *[\"\$\`\\]*) note "the folder name can't contain \", \$, \` or \\. Try another."; continue ;;
    esac
    if [ ! -d "$reply" ]; then
      read -r -p "  ${reply/#$HOME/~} doesn't exist. Create it? [Y/n] " yn
      case "$yn" in [nN]*) continue ;; esac
      mkdir -p "$reply" || { note "couldn't create ${reply/#$HOME/~}. Try another folder."; continue; }
    fi
    # config set checks the rest (characters, the team-notes folder) and says why.
    if out="$("$mr" config set NOTES_VAULT "$reply" 2>&1)"; then
      reply="$("$mr" config get NOTES_VAULT)"
      ok "notes go in ${reply/#$HOME/~}/meeting-notes"
      [ -d "$reply/.obsidian" ] || note "Open ${reply/#$HOME/~} in Obsidian once (Open folder as vault)."
      return
    fi
    out="${out#meetingrec: config: }"
    note "${out//TEAM_VAULT folder/team-notes folder}"
  done
}

install_personal_files() {
  step "Your settings and team profile"
  # Git ignores these, so they can't come down with the clone: each is copied
  # from its tracked template. The skills do the same on first run, so this
  # only saves a step. Existing copies are never touched, and a names.local.md
  # from before personal.md existed is left for the skill to carry over.
  local tmpl copy made=0
  for tmpl in \
      "$REPO/scribe/.claude/skills/meeting-notes/reference/personal.example.md" \
      "$REPO/teamnotes/.claude/skills/team-notes/reference/personal.example.md" \
      "$REPO/teamnotes/.claude/skills/team-notes/profiles/team.example.md"; do
    copy="${tmpl%.example.md}.md"
    [ -f "$copy" ] && continue
    [ -f "$(dirname "$tmpl")/names.local.md" ] && continue
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
  elif [ -n "$UPDATE" ]; then
    # Claude Code updates itself; an update shouldn't install it behind someone's back.
    note "not installed. To install it: curl -fsSL https://claude.ai/install.sh | bash"
  else
    curl -fsSL https://claude.ai/install.sh | bash || die "Claude Code didn't install."
    record claude-code
    ok "installed"
  fi
  if [ -x "$HOME/.local/bin/claude" ] && ! in_shell_startup ".local/bin"; then
    add_line "$HOME/.zprofile" 'export PATH="$HOME/.local/bin:$PATH"'
  fi
}

install_commands() {
  step "Commands: meetingrec, scribe, teamnotes"
  # ~/.local/bin is where Claude Code installs itself, so it's normally on PATH
  # already. Links rather than copies, so updates reach them.
  local dir="$HOME/.local/bin" name target old made=() kept=() already=()
  mkdir -p "$dir"
  for name in meetingrec scribe teamnotes; do
    target="$dir/$name"
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$REPO/.engine/bin/$name" ]; then
      already+=("$name"); continue
    elif [ -L "$target" ]; then
      old="$(readlink "$target")"
      # Re-point a link to another meetingrec copy, or to one that's gone (moved
      # in Finder); leave anything else alone.
      if [ ! -f "$(dirname "$old")/meetingrec" ] \
          && { [ -e "$old" ] || [ "${old%/bin/$name}" = "$old" ]; }; then
        kept+=("$name"); continue
      fi
    elif [ -e "$target" ]; then
      kept+=("$name"); continue
    fi
    ln -sfn "$REPO/.engine/bin/$name" "$target" || die "Couldn't link $target."
    made+=("$name")
  done
  if ! in_shell_startup ".local/bin"; then
    add_line "$HOME/.zprofile" 'export PATH="$HOME/.local/bin:$PATH"'
    note "added ~/.local/bin to your PATH. Open a new Terminal window to use the commands."
  fi
  [ ${#made[@]} -gt 0 ] && ok "${made[*]} → $dir"
  [ ${#already[@]} -gt 0 ] && ok "already set up: ${already[*]}"
  [ ${#kept[@]} -gt 0 ] && note "left alone, because $dir already has something else with that name: ${kept[*]}"
  return 0
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
  local new
  new="$(sed "s|^local REPO = .*|local REPO = \"$REPO\"|" "$REPO/.engine/hammerspoon/init.lua")"
  if [ -n "$UPDATE" ] && [ "$(cat "$target" 2>/dev/null)" = "$new" ]; then
    ok "already up to date: $target"
    return
  fi
  printf '%s\n' "$new" > "$target"
  ok "wrote $target"
  if [ -n "$FROM_MENU" ]; then
    ok "the menu bar reloads itself when the update finishes"
    return
  fi

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

# Hammerspoon's Info.plist has no NSAudioCaptureUsageDescription, so macOS
# never shows a System Audio Recording prompt for it: it silently denies, and
# the system track records silence. The only way in is turning it on by hand.
grant_system_audio() {
  step "System audio permission"
  local dir=/Applications
  [ -d "$dir/Hammerspoon.app" ] || dir="$HOME/Applications"
  cat <<EOF
  Hammerspoon can't ask for this permission itself, so macOS never shows a
  prompt for it. Turn it on by hand in System Settings (opening now):

    1. Under ${B}System Audio Recording Only${N}, click ${B}+${N}.
    2. Choose ${B}Hammerspoon${N} in ${dir/#$HOME/~} and click Open.
    3. Make sure its switch is on.

  If Hammerspoon is already listed there and on, there's nothing to do.

EOF
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null \
    || note "Open System Settings → Privacy & Security → Screen & System Audio Recording."
  local reply
  read -r -p "  Press Enter when Hammerspoon is on (or type s to skip): " reply
  if [ "$reply" = "s" ]; then
    note "skipped. The system-audio track will be silent until it's on."
    return
  fi
  # The permission applies from Hammerspoon's next start.
  killall Hammerspoon 2>/dev/null
  sleep 1
  open -a Hammerspoon
  ok "restarted Hammerspoon so the permission takes effect"
}

test_recording() {
  [ -n "${NO_HAMMERSPOON:-}" ] && return
  # No keyboard to answer with (e.g. CI): skip rather than hang.
  [ -t 0 ] || return

  grant_system_audio

  step "Test recording (gives the menu-bar button its permissions)"
  cat <<EOF
  macOS asks for microphone permission the first time Hammerspoon records.
  Do a short test now so the prompt doesn't appear during a real call:

    1. Click ○ in the menu bar → Start recording…
    2. Type ${B}test${N} as the title and click Start.
    3. Click ${B}Allow${N} on the Microphone prompt.
    4. Play a YouTube video and talk for about 15 seconds.
    5. Click the ● in the menu bar → Stop.

EOF
  local reply
  while :; do
    read -r -p "  Press Enter when you've clicked Stop (or type s to skip): " reply
    if [ "$reply" = "s" ]; then
      note "skipped. To do it later, run this installer again."
      return
    fi
    # Checking (and deleting) a session that's still recording would lose it.
    case "$("$REPO/.engine/bin/meetingrec" status 2>/dev/null)" in
      recording*) note "It's still recording. Click the ● in the menu bar → Stop first." ;;
      *) break ;;
    esac
  done

  local inbox="$REPO/scribe/input" session
  session="$(ls -1d "$inbox"/*_test 2>/dev/null | tail -n 1)"
  if [ -z "$session" ] || [ ! -f "$session/session.json" ]; then
    note "No finished test recording found in $inbox."
    note "To do the test later, run this installer again."
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
  1. Open a ${B}new${N} Terminal window, run ${B}claude${N} once, sign in, then type ${B}/exit${N}.
     The menu bar's "Write up notes…" works only after that first session ends.
  2. Set up Obsidian ("Set up Obsidian" in the README).

The first time you write up a meeting, Claude asks your name, where your notes
should go (meetingrec's folder, or an Obsidian vault you already use) and, for
team notes, your team's roster. It saves the answers for next time.

To write notes after a meeting: click ○ in the menu bar → Write up notes…
(or type  scribe  in Terminal; team notes:  teamnotes).
EOF
}

finish_update() {
  printf '\n%s%sUpdate finished.%s Your recordings, notes, names and settings were not changed.\n' "$G" "$B" "$N"
}

main() {
  check_mac
  install_clt
  get_repo
  install_config
  choose_notes_dir
  choose_tool_source
  move_old_downloads
  install_model
  install_tools
  install_audiotee
  install_hammerspoon_app
  install_personal_files
  install_claude
  install_commands
  install_hammerspoon_config
  if [ -n "$UPDATE" ]; then
    finish_update
  else
    test_recording
    finish
  fi
}

# Everything is in functions so a partly downloaded script does nothing.
# Under `curl | bash` stdin is the script itself, so prompts read the keyboard.
if [ -t 0 ] || ! (: </dev/tty) 2>/dev/null; then
  main "$@"
else
  main "$@" </dev/tty
fi
