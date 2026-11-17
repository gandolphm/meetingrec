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
  path="$(command -v "$program" || true)"
  [ -n "$path" ] || { echo "$folder: notes are set to be written by \"$agent\", but there's no $program command on this Mac. Install it, or go back to Claude Code: meetingrec config set NOTES_AGENT claude" >&2; exit 1; }
fi

# Antigravity takes the request to start with after -i. The others take it as
# the last word.
[ "$kind" = agy ] && cmd+=(-i)
cmd[0]="$path"

cd "$REPO_ROOT/$folder"
exec "${cmd[@]}" "$request"
