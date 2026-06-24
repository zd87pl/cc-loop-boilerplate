#!/usr/bin/env bash
# loop/lib/common.sh — logging, timestamps, small utilities. Source this.

# Colorize only on a TTY and when NO_COLOR is unset.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_DIM=$'\033[2m';  C_RST=$'\033[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_BLU=; C_DIM=; C_RST=
fi

log()  { printf '%s\n' "$*" >&2; }
info() { printf '%s[loop]%s %s\n' "$C_BLU" "$C_RST" "$*" >&2; }
warn() { printf '%s[warn]%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
err()  { printf '%s[err ]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
ok()   { printf '%s[ ok ]%s %s\n' "$C_GRN" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ISO-8601 UTC timestamp (second precision).
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Require a command on PATH or die with guidance.
need() { command -v "$1" >/dev/null 2>&1 || die "required tool not found on PATH: $1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Lowercase + dash slug, capped at 40 chars (for branch names).
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40
}

# looks_destructive <command-string>: heuristic veto list shared in spirit with
# the PreToolUse guard. Returns 0 (true) if the command would rewrite shared
# history or nuke the tree (CON-042).
looks_destructive() {
  local c="$1"
  case "$c" in
    *"git push"*"--force"*|*"git push -f"*) return 0 ;;
    *"git push --force-with-lease"*)        return 1 ;;  # explicitly allowed form
    *"git reset --hard"*)                   return 0 ;;
    *"git clean -"*[fF]*[dD]*)              return 0 ;;
    *"rm -rf /"*|*"rm -rf ~"*|*":(){:|:&};:"*) return 0 ;;
    *"git branch -D"*|*"git branch --delete --force"*) return 0 ;;
    *) return 1 ;;
  esac
}
