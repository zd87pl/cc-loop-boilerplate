#!/usr/bin/env bash
# adapters/stacks/_template.sh — the adapter contract + a copy-me starting point.
#
# HOW ADAPTERS WORK
#   The gate runner EXECUTES an adapter as a subprocess, passing one verb:
#       bash adapters/stacks/<name>.sh <verb>
#   so each adapter runs in its own process — its `set -euo pipefail` and helpers
#   never leak into the orchestrator. The footer at the bottom dispatches the
#   verb to the matching verb_<verb> function.
#
# THE CONTRACT — the core verbs every adapter should implement:
#   fmt          format the code IN PLACE (idempotent). Used by the PostToolUse
#                hook and the gate suite. CI follows with a `git diff` check.
#   lint         static analysis / style. Non-zero exit fails the gate.
#   typecheck    static type checking (or the nearest equivalent).
#   test         run the test suite. Non-zero exit fails the gate.
#   build        compile / package. Non-zero exit fails the gate.
#   securityscan dependency / SAST scan. Best-effort; non-zero fails the gate.
#
# EXTENDED verbs (optional — an unimplemented verb auto-dispatches to `skip`):
#   coverage     measure test coverage; when $LOOP_COVERAGE_MIN > 0, fail if
#                the measured percentage is below it (use coverage_compare, and
#                print the measured figure so humans/agents can see it).
#   complexity   fail when any function exceeds $LOOP_COMPLEXITY_MAX cyclomatic
#                complexity; skip when the threshold is 0/unset.
#   archlint     enforce the repo's architecture / import-boundary rules; run
#                only when the repo carries a rules file, otherwise skip.
#   mutation     mutation testing (expensive; the loop enables it per risk
#                profile). Non-zero exit (surviving mutants) fails the gate.
# The canonical verb lists live at the top of adapters/lib.sh — never copy them.
#
# RULES
#   * A verb whose tool is unavailable or unconfigured must call `skip` and
#     succeed (exit 0). NEVER hard-fail just because an OPTIONAL tool is missing —
#     `make doctor` reports skips so they stay visible.
#   * A verb whose tool runs and reports a real problem must return that tool's
#     non-zero exit so the gate fails.
#   * Resolve everything relative to the current directory (the repo/worktree
#     root); the gate runner cd's there first.
#   * Any verb can be overridden per-repo via `.loop.yml` -> gates.<verb>.
#
# To add a stack: copy this file to stacks/<name>.sh, implement the verbs, and
# add a detection rule to adapters/detect.sh.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

verb_fmt()          { skip "fmt not implemented for this stack"; }
verb_lint()         { skip "lint not implemented for this stack"; }
verb_typecheck()    { skip "typecheck not implemented for this stack"; }
verb_test()         { skip "test not implemented for this stack"; }
verb_build()        { skip "build not implemented for this stack"; }
verb_securityscan() { skip "securityscan not implemented for this stack"; }

# --- dispatch footer (fires when executed, not when sourced) ------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
