#!/usr/bin/env bash
# adapters/lib.sh — shared helpers for stack adapters.
#
# SOURCE this from an adapter (stacks/<name>.sh); do not execute it directly.
# It defines no top-level side effects beyond function definitions, so sourcing
# it is safe and does not enable `set -e` in the caller.

# The adapter verb contract — THE single source of truth for the gate
# vocabulary. Consumers (loop/lib/gates.sh, .claude/hooks/stop-gate.sh, the
# Makefile) read these lists by EXECUTING this file (see the footer) instead of
# keeping their own copies, so adding a verb here is the whole change.
#   mutating:  rewrites the tree (fmt) — excluded from the judged suite's
#              default check set (the suite must not mutate what it judges).
#   check:     the classic six-minus-fmt deterministic checks.
#   extended:  higher-order gates from the agentic-code-quality alignment —
#              coverage (threshold via $LOOP_COVERAGE_MIN), complexity
#              (threshold via $LOOP_COMPLEXITY_MAX), archlint (architecture /
#              import-boundary rules; runs only when the repo has a rules
#              file), mutation (mutation testing; expensive, profile-gated).
# A verb a stack does not implement is dispatched to `skip` automatically, so
# extending the list never breaks an existing adapter.
ADAPTER_VERBS_MUTATING="fmt"
ADAPTER_VERBS_CHECK="lint typecheck test build securityscan"
ADAPTER_VERBS_EXTENDED="coverage complexity archlint mutation"
ADAPTER_VERBS="$ADAPTER_VERBS_MUTATING $ADAPTER_VERBS_CHECK $ADAPTER_VERBS_EXTENDED"

# have <cmd>: true if an executable is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# run <cmd...>: echo the command (to stderr) then execute it, preserving exit
# status. The only place adapters should launch a tool, so every gate command is
# visible in the run log.
run() {
  printf '    + %s\n' "$*" >&2
  "$@"
}

# skip <reason>: the tool needed for this verb is unavailable or unconfigured.
# Print a clear, greppable line and succeed (exit 0) so a missing OPTIONAL tool
# never hard-fails the loop. Skips are surfaced by `make doctor` and counted in
# the run report, so they are visible — not silently masked.
skip() {
  printf '    [skip] %s\n' "$*" >&2
  return 0
}

# note <msg>: informational line (does not affect exit status).
note() { printf '    [note] %s\n' "$*" >&2; }

# coverage_compare <measured-pct> <min-pct>: 0 when measured >= min. Shared so
# adapters that compute a percentage themselves apply one comparison rule.
coverage_compare() { awk -v m="${1:-0}" -v n="${2:-0}" 'BEGIN{exit !(m+0 >= n+0)}'; }

# complexity_grade <max-ccn>: map a numeric cyclomatic threshold onto the
# radon/xenon letter scale (used by the python adapter).
complexity_grade() {
  local n="${1:-10}"
  if   [ "$n" -le 5 ];  then echo A
  elif [ "$n" -le 10 ]; then echo B
  elif [ "$n" -le 20 ]; then echo C
  elif [ "$n" -le 30 ]; then echo D
  elif [ "$n" -le 40 ]; then echo E
  else echo F; fi
}

# adapter_dispatch <verb>: validate and invoke verb_<verb>. Called by each
# adapter's footer when the file is executed (not sourced).
adapter_dispatch() {
  local verb="${1:-}"
  case " $ADAPTER_VERBS " in
    *" $verb "*) : ;;
    *)
      printf 'usage: %s <%s>\n' "${0##*/}" "${ADAPTER_VERBS// /|}" >&2
      return 64
      ;;
  esac
  if declare -F "verb_$verb" >/dev/null 2>&1; then
    "verb_$verb"
  else
    skip "verb '$verb' not implemented by ${0##*/}"
  fi
}

# Executed mode: print the canonical verb lists so other layers (gates.sh, the
# Stop hook, the Makefile) consume ONE definition instead of keeping copies.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    --verbs)          printf '%s\n' "$ADAPTER_VERBS" ;;
    --check-verbs)    printf '%s\n' "$ADAPTER_VERBS_CHECK" ;;
    --extended-verbs) printf '%s\n' "$ADAPTER_VERBS_EXTENDED" ;;
    --mutating-verbs) printf '%s\n' "$ADAPTER_VERBS_MUTATING" ;;
    *) printf 'usage: %s --verbs|--check-verbs|--extended-verbs|--mutating-verbs\n' "${0##*/}" >&2; exit 64 ;;
  esac
fi
