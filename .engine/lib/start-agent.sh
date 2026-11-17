#!/usr/bin/env bash
#
# start-agent.sh — starts the coding agent that writes up notes, in a skill's
# folder, with the request sent. The scribe and teamnotes commands run it.
#
#   start-agent.sh <scribe|teamnotes> <request> [extra words…]
#
# Which agent is NOTES_AGENT in config.sh: the command that starts it, options
# included, "claude" unless changed. The command's first word says what it is:
#
#   claude   Claude Code      claude [options] "<request>"
#   codex    Codex            codex [options] "<request>"
#   agy      Antigravity      agy [options] -i "<request>"
#   other    anything else    <command> [options] "<request>"
#
# The agent gets the caller's own environment. That's why this isn't a meetingrec
# command: meetingrec replaces PATH with a short fixed one, and an agent needs
# the user's.
set -euo pipefail

folder="$1" request="$2"; shift 2
request="$request${*:+ $*}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"

agent="$("$REPO_ROOT/.engine/bin/meetingrec" config get NOTES_AGENT 2>/dev/null || true)"
# Split on spaces and never handed to a shell; config set refuses quotes.
cmd=()
read -r -a cmd <<<"${agent:-claude}"
[ "${#cmd[@]}" -gt 0 ] || cmd=(claude)
program="${cmd[0]}"
kind="$(basename "$program")"

if [ "$kind" = claude ]; then
  # ~/.local/bin is where Claude Code installs itself. A Terminal window opened
  # before the installer put that folder on PATH doesn't know it yet.
  path="$(command -v "$program" || echo "$HOME/.local/bin/claude")"
  [ -x "$path" ] || { echo "$folder: Claude Code isn't installed. Install it: curl -fsSL https://claude.ai/install.sh | bash" >&2; exit 1; }
else
  # Antigravity's own installer puts agy in ~/.local/bin too.
  path="$(command -v "$program" || { [ "$kind" = agy ] && [ -x "$HOME/.local/bin/agy" ] && echo "$HOME/.local/bin/agy"; } || true)"
  if [ -z "$path" ]; then
    case "$kind" in
      codex) how=" Install it: npm install -g @openai/codex (or brew install --cask codex)." ;;
      agy)   how=" Install it: see https://antigravity.google/docs/getting-started (the CLI tab)." ;;
      *)     how="" ;;
    esac
    echo "$folder: notes are set to be written by \"$agent\", but there's no $program command on this Mac.$how Or go back to Claude Code: meetingrec config set NOTES_AGENT claude" >&2
    exit 1
  fi
fi

# Codex's sandbox lets it write only in the folder it starts in (and /tmp). The
# agent writes the note itself, with its own file tool, so a notes folder
# elsewhere needs --add-dir; so does the recordings folder, which clear-input
# empties, and, for team notes, scribe/transcripts, where a kept transcript
# goes. Only folders outside the start folder, and only ones that exist.
if [ "$kind" = codex ]; then
  mr="$REPO_ROOT/.engine/bin/meetingrec" start="$REPO_ROOT/$folder" dirs=()
  if [ "$folder" = scribe ]; then
    dirs+=("$("$mr" config get NOTES_VAULT 2>/dev/null || true)")
    dirs+=("$("$mr" config get OUTPUT_ROOT 2>/dev/null || true)")
  else
    dirs+=("$("$mr" config get TEAM_VAULT 2>/dev/null || true)")
    dirs+=("$REPO_ROOT/scribe/transcripts")
  fi
  for d in "${dirs[@]}"; do
    # Resolved the way REPO_ROOT is (pwd -P), so the two compare.
    [ -n "$d" ] && d="$(cd "$d" 2>/dev/null && pwd -P)" || continue
    case "$d/" in "$start/"*) continue ;; esac
    cmd+=(--add-dir "$d")
  done
fi

# Antigravity takes the request to start with after -i. The others take it as
# the last word.
[ "$kind" = agy ] && cmd+=(-i)
cmd[0]="$path"

cd "$REPO_ROOT/$folder"
exec "${cmd[@]}" "$request"
