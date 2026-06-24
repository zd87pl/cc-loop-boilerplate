#!/usr/bin/env bash
# PreToolUse guard — exit code 2 DENIES the tool call (CON-042, CON-043).
# Two jobs:
#   1) veto destructive commands (rewriting shared history, nuking the tree)
#   2) veto writes/commands that would expose a secret or credential
# Self-contained and portable: needs only coreutils + grep; uses jq when present
# and falls back to a raw scan of stdin otherwise. Wired for Edit|Write|Bash.
set -uo pipefail
input="$(cat)"

deny() { printf 'BLOCKED by pretool-guard: %s\n' "$1" >&2; exit 2; }

# --- secret patterns, assembled from fragments so this guard never flags its
#     own source or documentation that merely describes the patterns ----------
AWS_AKID='AKIA[0-9A-Z]{16}'
PK_BEGIN='-----BEGIN'
PK_REST='PRIVATE KEY-----'
GH_TOKEN='gh[pousr]_[0-9A-Za-z]{20,}'
GOOGLE_KEY='AIza[0-9A-Za-z_-]{35}'
SLACK='xox[baprs]-[0-9A-Za-z-]{8,}'
JWT='eyJ[A-Za-z0-9_=-]{8,}\.eyJ[A-Za-z0-9_=-]{6,}\.[A-Za-z0-9_.+/=-]{6,}'
GENERIC='(secret|token|passwd|password|api[_-]?key|access[_-]?key|private[_-]?key)["'"'"' ]*[:=]["'"'"' ]*[0-9A-Za-z/+_=.-]{16,}'

secret_hit() { # 0 if the text looks like it contains a secret
  local t="$1"
  printf '%s' "$t" | grep -Eq  "$AWS_AKID"                && return 0
  printf '%s' "$t" | grep -Eq -e "${PK_BEGIN}[A-Z ]*${PK_REST}" && return 0
  printf '%s' "$t" | grep -Eq  "$GH_TOKEN"                && return 0
  printf '%s' "$t" | grep -Eq  "$GOOGLE_KEY"              && return 0
  printf '%s' "$t" | grep -Eq  "$SLACK"                   && return 0
  printf '%s' "$t" | grep -Eq  "$JWT"                     && return 0
  printf '%s' "$t" | grep -Eiq "$GENERIC"                 && return 0
  return 1
}

# --- extract tool name + the text we care about ---------------------------
tool=""; cmd=""; payload="$input"
if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  cmd="$( printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  payload="$(printf '%s' "$input" | jq -r '
      [.tool_input.command, .tool_input.content, .tool_input.new_string,
       .tool_input.file_text]
      | map(select(. != null)) | join("\n")' 2>/dev/null)"
fi

# --- 1) destructive command veto ------------------------------------------
if [ "$tool" = "Bash" ] || [ -n "$cmd" ]; then
  c="${cmd:-$payload}"
  # Strip the safe '--force-with-lease' form so a SEPARATE --force in a compound
  # command (a && b) cannot hide behind it.
  c_force="${c//--force-with-lease/}"
  case "$c" in
    *"rm -rf /"*|*"rm -fr /"*|*"rm -rf ~"*|*"rm -fr ~"*|*":(){:|:&};:"*|*":(){ :|:& };:"*) deny "destructive filesystem command" ;;
    *"git reset --hard"*) deny "git reset --hard" ;;
    *"git branch -D"*)    deny "force branch delete" ;;
  esac
  case "$c_force" in
    *"git push"*"--force"*|*"git push -f"*|*"git push"*" -f "*) deny "force-push to shared history" ;;
  esac
  case "$c" in
    *"git clean"*)
      if   printf '%s' "$c" | grep -Eq -- '(^|[^a-z])(-n|--dry-run)([^a-z]|$)'; then : # dry run is safe
      elif printf '%s' "$c" | grep -Eq -- 'git[[:space:]]+clean[^;&|]*-[a-z]*f';  then
        deny "git clean -f (wipes untracked files)"
      fi ;;
  esac
fi

# --- 2) secret scan (prefer gitleaks; else builtin patterns) ---------------
if [ -n "$payload" ]; then
  if command -v gitleaks >/dev/null 2>&1; then
    printf '%s' "$payload" | gitleaks stdin --no-banner >/dev/null 2>&1 || deny "gitleaks flagged a secret"
  elif secret_hit "$payload"; then
    deny "potential secret/credential detected (builtin scan)"
  fi
fi

exit 0
