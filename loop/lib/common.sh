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

# looks_destructive <command-string>: shared veto for commands that would
# rewrite shared history or nuke the tree (CON-042). This is THE implementation
# — the PreToolUse guard sources this file, so hook and controller can never
# disagree about the same command. Judgement is per simple-command segment
# (split on ; | &) with tokens parsed, so `git -C x reset --hard`, combined
# short flags (-fD), env/sudo prefixes, and a bare --force hiding behind a
# --force-with-lease elsewhere in a compound command are all caught, while
# `echo "git reset --hard"` no longer false-positives.
looks_destructive() {
  local cmd="$1" seg
  # Fork bombs before tokenizing (punctuation soup either way).
  case "${cmd// /}" in *":(){:|:&};:"*) return 0 ;; esac
  while IFS= read -r seg; do
    [ -n "${seg// /}" ] || continue
    _seg_destructive "$seg" && return 0
  done < <(printf '%s\n' "$cmd" | tr '\t' ' ' | sed -E 's/(\|\||&&|[;|&])+/\n/g')
  return 1
}

# _seg_destructive <simple-command> — body runs in a subshell so `set -f`
# (no glob expansion while tokenizing) cannot leak to the caller.
_seg_destructive() (
  set -f
  # shellcheck disable=SC2086
  set -- $1
  # Skip env assignments and common wrappers to reach the real command word.
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*|sudo|command|env|nohup|time|nice) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 1
  local cmd0="$1" t; shift
  case "$cmd0" in
    git)
      # Consume git's global options (some take a value) to find the subcommand.
      local sub=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -C|-c|--git-dir|--work-tree|--namespace) shift 2 2>/dev/null || return 1 ;;
          -*) shift ;;
          *) sub="$1"; shift; break ;;
        esac
      done
      local hard=0 force=0 fflag=0 bigd=0 delete=0 dry=0 plusref=0
      for t in "$@"; do
        case "$t" in
          --hard) hard=1 ;;
          --force) force=1 ;;
          --force-with-lease|--force-with-lease=*) : ;;   # the safe form
          --delete) delete=1 ;;
          --dry-run) dry=1 ;;
          --*) : ;;
          -*) case "$t" in *f*) fflag=1 ;; esac
              case "$t" in *D*) bigd=1 ;; esac
              case "$t" in *n*) dry=1 ;; esac ;;
          +*) plusref=1 ;;                                # +ref is a force refspec
        esac
      done
      case "$sub" in
        reset)  [ $hard -eq 1 ] && return 0 ;;
        push)   { [ $force -eq 1 ] || [ $fflag -eq 1 ] || [ $plusref -eq 1 ]; } && return 0 ;;
        branch) { [ $bigd -eq 1 ] || { [ $delete -eq 1 ] && { [ $force -eq 1 ] || [ $fflag -eq 1 ]; }; }; } && return 0 ;;
        clean)  { [ $force -eq 1 ] || [ $fflag -eq 1 ]; } && [ $dry -eq 0 ] && return 0 ;;
      esac
      return 1 ;;
    rm)
      # Veto only the CATASTROPHIC class: filesystem root, depth-1 system dirs
      # (/usr, /etc), home roots (~, $HOME, /home/<u>), the repo itself (., ..)
      # and .git. Deep scratch paths (rm -rf /tmp/x, rm -rf build/) are routine
      # legitimate cleanup and stay allowed.
      local r=0 f=0
      for t in "$@"; do
        case "$t" in
          --recursive) r=1 ;; --force) f=1 ;;
          --*) : ;;
          -*) case "$t" in *r*|*R*) r=1 ;; esac
              case "$t" in *f*) f=1 ;; esac ;;
        esac
      done
      if [ $r -eq 1 ] && [ $f -eq 1 ]; then
        for t in "$@"; do
          case "$t" in -*) continue ;; esac
          _rm_target_catastrophic "$t" && return 0
        done
      fi
      return 1 ;;
    *) return 1 ;;
  esac
)

# _rm_target_catastrophic <token> — see the rm branch above.
_rm_target_catastrophic() {
  local t="$1"
  case "$t" in
    /|/.|.|./|..|~|~/*|\$HOME*|\$\{HOME\}*|.git|.git/*) return 0 ;;
    /home/*|/Users/*) case "${t#/}" in */*/*) return 1 ;; *) return 0 ;; esac ;;  # a home ROOT; deeper is ok
    /*)               case "${t#/}" in */*)   return 1 ;; *) return 0 ;; esac ;;  # depth-1 absolute (/usr, /etc)
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Protected paths (CON-045) — the guardrail chain itself. Writable by humans
# (LOOP_ALLOW_PROTECTED=1), never by the loop. Space-separated case-globs.
# ---------------------------------------------------------------------------
LOOP_PROTECTED_DEFAULT=".claude/settings.json .claude/settings.local.json .claude/hooks/* specs/constitution.md .loop.yml"

# protected_paths_effective [loop-yml] — resolution order: LOOP_PROTECTED_PATHS
# env (exported by the controller from .loop.yml) > a best-effort parse of the
# given .loop.yml (interactive sessions) > the built-in default set.
protected_paths_effective() {
  if [ -n "${LOOP_PROTECTED_PATHS:-}" ]; then printf '%s' "$LOOP_PROTECTED_PATHS"; return; fi
  local f="${1:-}"
  if [ -n "$f" ] && [ -f "$f" ] && grep -q '^protected_paths:' "$f" 2>/dev/null; then
    sed -n '/^protected_paths:/,/^[A-Za-z_]/p' "$f" \
      | sed -n -E 's/^[[:space:]]*-[[:space:]]*"?([^"#]+[^"# ])"?.*$/\1/p' | tr '\n' ' '
    return
  fi
  printf '%s' "$LOOP_PROTECTED_DEFAULT"
}

# protected_path_match <path> [loop-yml] — true if the (repo-relative) path
# matches a protected glob. `*` in a case pattern crosses `/`, so
# `.claude/hooks/*` covers nested files too.
protected_path_match() {
  local p="${1#./}" pat
  for pat in $(protected_paths_effective "${2:-}"); do
    # shellcheck disable=SC2254
    case "$p" in $pat) return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# Redaction (CON-090) — scrub secret/PII shapes from text that lands in gate
# logs and the report. Builtin patterns cover the same shapes the PreToolUse
# secret veto knows; extras come newline-separated in LOOP_REDACT_PATTERNS
# (exported by the controller from .loop.yml redact_patterns). Patterns are
# assembled from fragments so this file never flags or redacts its own source.
# ---------------------------------------------------------------------------
_redact_builtin() {
  local b='-----BEGIN' e='PRIVATE KEY-----'
  printf '%s\n' \
    'AKIA[0-9A-Z]{16}' \
    'gh[pousr]_[0-9A-Za-z]{20,}' \
    'AIza[0-9A-Za-z_-]{35}' \
    'xox[baprs]-[0-9A-Za-z-]{8,}' \
    'eyJ[A-Za-z0-9_=-]{8,}\.eyJ[A-Za-z0-9_=-]{6,}\.[A-Za-z0-9_.+/=-]{6,}' \
    "${b}[A-Z ]*${e}"
}

# redact_stream: stdin -> stdout with every pattern occurrence replaced by
# [REDACTED]. perl handles full PCRE (including `(?i)`); the sed fallback is
# best-effort — it strips a leading `(?i)` and applies the rest as ERE.
redact_stream() {
  local pats
  pats="$(_redact_builtin; printf '%s\n' "${LOOP_REDACT_PATTERNS:-}")"
  if have perl; then
    _REDACT_PATTERNS="$pats" perl -pe '
      BEGIN { @p = grep { length } split /\n/, ($ENV{_REDACT_PATTERNS} // "") }
      for my $r (@p) { eval { s/$r/[REDACTED]/g }; }'
  else
    local script="" p
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      p="${p#(?i)}"
      case "$p" in *'|'*) continue ;; esac   # | would break the s||| delimiter
      script="${script}s|${p}|[REDACTED]|g;"
    done <<<"$pats"
    if [ -n "$script" ]; then sed -E "$script" 2>/dev/null || cat; else cat; fi
  fi
}
