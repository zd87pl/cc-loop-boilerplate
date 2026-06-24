#!/usr/bin/env bash
# adapters/lib.sh — shared helpers for stack adapters.
#
# SOURCE this from an adapter (stacks/<name>.sh); do not execute it directly.
# It defines no top-level side effects beyond function definitions, so sourcing
# it is safe and does not enable `set -e` in the caller.

# The six-verb contract every stacks/<name>.sh must satisfy.
ADAPTER_VERBS="fmt lint typecheck test build securityscan"

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
