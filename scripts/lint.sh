#!/usr/bin/env bash
# scripts/lint.sh — the boilerplate lints ITSELF (self-verification): the loop
# that enforces gates on other repos must pass its own. Wired as this repo's
# `gates.lint` override in .loop.yml, so the Stop hook and the controller run
# it; also available as `make lint`.
#
# Checks (each skips honestly when its tool is absent — a skip is reported,
# never silently passed):
#   1) shellcheck --severity=error over every shell script (error severity is
#      the gate; style/info are advisory and do not block)
#   2) every JSON file parses (jq)
#   3) spec-lint --ids-only over the constitution (duplicate rule ids — the
#      exact bug class that shipped once — and unresolved placeholders)
#   4) bash -n over every shell script (always available)
set -uo pipefail
cd "$(dirname "$0")/.."

rc=0
note() { printf '[lint] %s\n' "$*"; }

SCRIPTS="$(ls loop/run.sh loop/lib/*.sh adapters/*.sh adapters/stacks/*.sh \
              scripts/*.sh evals/run.sh .claude/hooks/*.sh 2>/dev/null)"

# Content-hash cache: this gate runs on every Stop-hook fire and every dry run;
# an unchanged tree that linted clean once need not pay for shellcheck again.
# Any byte change to any checked file invalidates it. LOOP_LINT_NO_CACHE=1
# forces a full run.
CACHE=".loop/state/lint.cache"
lint_hash() {
  # shellcheck disable=SC2086
  cat $SCRIPTS specs/constitution.md .claude/settings.json .claude/hooks/hooks.json 2>/dev/null \
    | { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null || cksum; } | awk '{print $1}'
}
if [ "${LOOP_LINT_NO_CACHE:-0}" != "1" ] && [ -f "$CACHE" ] \
   && [ "$(cat "$CACHE" 2>/dev/null)" = "$(lint_hash)" ]; then
  note "clean (cached — no checked file changed since the last clean run)"
  exit 0
fi

# 4 first: syntax is the floor, and needs nothing beyond bash.
for f in $SCRIPTS; do
  bash -n "$f" || { note "syntax error: $f"; rc=1; }
done

if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  if ! shellcheck --severity=error $SCRIPTS; then
    note "shellcheck (severity=error) found problems"; rc=1
  fi
else
  note "[skip] shellcheck not installed — install it to enable shell linting"
fi

if command -v jq >/dev/null 2>&1; then
  while IFS= read -r j; do
    jq -e . "$j" >/dev/null 2>&1 || { note "invalid JSON: $j"; rc=1; }
  done < <(git ls-files '*.json' 2>/dev/null || ls .claude/settings.json .claude/hooks/hooks.json 2>/dev/null)
else
  note "[skip] jq not installed — JSON files not validated"
fi

if [ -f scripts/spec-lint.sh ] && [ -f specs/constitution.md ]; then
  bash scripts/spec-lint.sh specs/constitution.md --ids-only \
    || { note "constitution failed id lint (duplicate rule ids?)"; rc=1; }
fi

if [ "$rc" -eq 0 ]; then
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null && lint_hash > "$CACHE" 2>/dev/null || true
  note "clean"
fi
exit "$rc"
