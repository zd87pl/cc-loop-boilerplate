#!/usr/bin/env bash
# PreToolUse guard — exit code 2 DENIES the tool call. Four jobs, in order:
#   1) veto destructive commands (CON-042) — via the SAME looks_destructive
#      the controller uses (loop/lib/common.sh), so hook and loop can never
#      disagree about the same command
#   2) veto writes that touch a protected path (CON-045) — inside controller-
#      spawned stage sessions (LOOP_STAGE set) the guardrail chain (hooks,
#      settings, constitution, .loop.yml) is not editable; a human running a
#      self-hosting loop escapes with LOOP_ALLOW_PROTECTED=1. Interactive
#      sessions are human-supervised and stay free to maintain these files —
#      the pre-merge diff barrier (gate_check_protected_paths) still audits
#      every loop branch regardless.
#   3) scope stage writes (CON-072) — stages other than implement/fix may
#      write only into the run dir / .loop/, not the repo (tool omission
#      never stopped Bash redirects)
#   4) veto writes/commands that would expose a secret (CON-043) — across
#      every write surface (Edit/Write/MultiEdit/NotebookEdit/Bash), honoring
#      .loop.yml secret_scan / secret_scanner
# Degrades gracefully: works without jq (raw-stdin scan) and without the lib
# (inline fallback patterns). Wired for Edit|MultiEdit|NotebookEdit|Write|Bash.
set -uo pipefail
input="$(cat)"

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
LIB="${CLAUDE_PLUGIN_ROOT:-$ROOT}/loop/lib/common.sh"
[ -f "$LIB" ] || LIB="$ROOT/loop/lib/common.sh"
HAVE_LIB=0
# shellcheck disable=SC1090
if [ -f "$LIB" ] && . "$LIB" 2>/dev/null; then HAVE_LIB=1; fi

deny() { printf 'BLOCKED by pretool-guard: %s\n' "$1" >&2; exit 2; }

# Inline fallback when the shared lib is unavailable (vendored partially).
if [ "$HAVE_LIB" -ne 1 ]; then
  looks_destructive() {
    local c="$1" cf="${1//--force-with-lease/}"
    case "$cf" in *"git push"*"--force"*|*"git push -f"*|*"git push"*" -f "*|*"git push"*" -f") return 0 ;; esac
    case "$c" in
      *"git reset --hard"*|*"git branch -D"*|*"git clean -f"*) return 0 ;;
      *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf .git"*|*":(){:|:&};:"*) return 0 ;;
      *) return 1 ;;
    esac
  }
  LOOP_PROTECTED_DEFAULT=".claude/settings.json .claude/settings.local.json .claude/hooks/* specs/constitution.md .loop.yml"
  protected_paths_effective() { printf '%s' "${LOOP_PROTECTED_PATHS:-$LOOP_PROTECTED_DEFAULT}"; }
  protected_path_match() {
    local p="${1#./}" pat
    for pat in $(protected_paths_effective); do
      # shellcheck disable=SC2254
      case "$p" in $pat) return 0 ;; esac
    done; return 1
  }
fi

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

# yml_scalar <key> — best-effort top-level scalar from .loop.yml (used only
# when the controller has not exported the corresponding LOOP_* variable).
yml_scalar() {
  [ -f "$ROOT/.loop.yml" ] || return 0
  sed -n -E "s/^${1}:[[:space:]]*\"?([A-Za-z0-9._-]+)\"?.*/\1/p" "$ROOT/.loop.yml" 2>/dev/null | head -1
}

# --- extract tool name + targets + the text we care about -------------------
tool=""; cmd=""; target=""; payload="$input"
if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  cmd="$( printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  target="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
  # Every NEW content field across the write surfaces. old_string is data being
  # REPLACED and stays out on purpose: removing a leaked secret must not be
  # blocked by the secret it removes.
  payload="$(printf '%s' "$input" | jq -r '
      [.tool_input.command, .tool_input.content, .tool_input.new_string,
       .tool_input.file_text, .tool_input.new_source]
      + [(.tool_input.edits // [])[] | .new_string]
      + [(.tool_input.cells // [])[] | .source]
      | map(select(. != null)) | join("\n")' 2>/dev/null)"
  # Unknown write-shaped tool matched by a broader matcher: scan everything.
  if [ -z "$payload" ] && [ -z "$cmd" ] && [ -z "$target" ]; then
    payload="$(printf '%s' "$input" | jq -r '.tool_input // {} | tostring' 2>/dev/null)"
  fi
fi

# rel_path <path> — repo-relative form for protected/scope matching.
rel_path() {
  local p="$1"
  case "$p" in "$ROOT"/*) p="${p#"$ROOT"/}" ;; esac
  printf '%s' "${p#./}"
}

# --- 1) destructive command veto (CON-042) ---------------------------------
if [ "$tool" = "Bash" ] || [ -n "$cmd" ]; then
  looks_destructive "${cmd:-$payload}" \
    && deny "destructive command (rewrites shared history or nukes the tree, CON-042)"
fi

# --- 2) protected paths (CON-045) — stage sessions only ---------------------
if [ -n "${LOOP_STAGE:-}" ] && [ "${LOOP_ALLOW_PROTECTED:-0}" != "1" ]; then
  if [ -n "$target" ] && protected_path_match "$(rel_path "$target")" "$ROOT/.loop.yml"; then
    deny "'$(rel_path "$target")' is a protected path (guardrail chain, CON-045); a human can run the loop with LOOP_ALLOW_PROTECTED=1 to change it"
  fi
  # Bash heuristic: a mutating form aimed at a protected path. Reads are fine
  # (sed only counts with -i / --in-place).
  if [ -n "$cmd" ]; then
    for pat in $(protected_paths_effective "$ROOT/.loop.yml"); do
      prefix="${pat%%[\*\?]*}"; [ -n "$prefix" ] || continue
      case "$cmd" in *"$prefix"*) : ;; *) continue ;; esac
      pre_re="$(printf '%s' "$prefix" | sed -E 's/[][^$.*+?(){}|]/\\&/g')"
      if printf '%s' "$cmd" | grep -Eq ">>?[[:space:]]*[\"']?(\./)?${pre_re}" \
         || printf '%s' "$cmd" | grep -Eq "(^|[;&|][[:space:]]*|[[:space:]])(tee|rm|mv|cp|truncate|chmod|patch|install)([[:space:]][^;&|]*)?[[:space:]][\"']?(\./)?${pre_re}" \
         || printf '%s' "$cmd" | grep -Eq "sed[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-[A-Za-z]*i[A-Za-z]*|--in-place)[^;&|]*[[:space:]][\"']?(\./)?${pre_re}"; then
        deny "command writes to protected path '$prefix…' (CON-045); a human can run the loop with LOOP_ALLOW_PROTECTED=1 to change it"
      fi
    done
  fi
fi

# --- 3) stage-scoped writes (CON-072) ---------------------------------------
# Only active inside controller-spawned stage sessions (LOOP_STAGE set by the
# loop; unset in interactive sessions). Stages whose contract is read-the-repo
# (spec, review, verify, …) may write run artifacts but not the repo itself.
case "${LOOP_STAGE:-}" in
  ""|implement|fix) : ;;
  *)
    if [ -n "$target" ]; then
      t_ok=0
      case "$target" in
        "${LOOP_RUN_DIR:-/nonexistent}"|"${LOOP_RUN_DIR:-/nonexistent}"/*) t_ok=1 ;;
        /*) case "$target" in "$ROOT"/*) : ;; *) t_ok=1 ;; esac ;;   # outside the repo: not ours to scope
      esac
      if [ "$t_ok" -ne 1 ]; then
        case "$(rel_path "$target")" in .loop/*) t_ok=1 ;; esac
      fi
      [ "$t_ok" -eq 1 ] || deny "stage '$LOOP_STAGE' is repo-read-only (CON-072): write '$(rel_path "$target")' under the run dir (${LOOP_RUN_DIR:-.loop/runs/<id>}) instead, or route code edits through implement/fix"
    fi ;;
esac

# --- 4) secret scan (CON-043) — configurable, closed over all surfaces ------
sscan="${LOOP_SECRET_SCAN:-$(yml_scalar secret_scan)}"
case "${sscan:-true}" in false|no|off|0) exit 0 ;; esac
scanner="${LOOP_SECRET_SCANNER:-$(yml_scalar secret_scanner)}"
scanner="${scanner:-auto}"

if [ -n "$payload" ]; then
  ran_external=0
  if [ "$scanner" = "gitleaks" ] || { [ "$scanner" = "auto" ] && command -v gitleaks >/dev/null 2>&1; }; then
    if command -v gitleaks >/dev/null 2>&1; then
      # --exit-code makes findings distinguishable from usage errors; an old
      # gitleaks that lacks the flag exits differently and we fall through to
      # the builtin scan instead of denying legitimate writes.
      printf '%s' "$payload" | gitleaks stdin --no-banner --exit-code 99 >/dev/null 2>&1
      rc=$?
      [ "$rc" -eq 99 ] && deny "gitleaks flagged a secret (CON-043)"
      [ "$rc" -eq 0 ] && ran_external=1
    fi
  elif [ "$scanner" = "trufflehog" ] || { [ "$scanner" = "auto" ] && command -v trufflehog >/dev/null 2>&1; }; then
    if command -v trufflehog >/dev/null 2>&1; then
      tdir="$(mktemp -d "${TMPDIR:-/tmp}/loop.guard.XXXXXX")" && {
        printf '%s' "$payload" > "$tdir/payload"
        trufflehog filesystem "$tdir" --no-update --fail >/dev/null 2>&1
        rc=$?
        rm -rf "$tdir"
        [ "$rc" -eq 183 ] && deny "trufflehog flagged a secret (CON-043)"   # 183 = findings
        [ "$rc" -eq 0 ] && ran_external=1
      }
    fi
  fi
  if [ "$ran_external" -ne 1 ] && secret_hit "$payload"; then
    deny "potential secret/credential detected (builtin scan, CON-043)"
  fi
fi

exit 0
