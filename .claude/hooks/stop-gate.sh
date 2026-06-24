#!/usr/bin/env bash
# Stop hook — run the quality gates before the turn ends (CON-030). If a gate is
# red, exit 2 to block the stop and feed the failures back to the model so it
# fixes them. A per-session block counter prevents a stuck session from being
# wedged (we lack a documented stop_hook_active field in this CLI version).
#
#   Disable entirely:        LOOP_STOP_GATE=0
#   Max consecutive blocks:  LOOP_STOP_GATE_MAX_BLOCKS (default 3)
#
# Note: this runs the suite on every turn end, so it is most valuable for small/
# medium repos and for the headless loop. Disable it if your test suite is slow.
set -uo pipefail
input="$(cat)"
[ "${LOOP_STOP_GATE:-1}" = "0" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
ADAPTERS="${CLAUDE_PLUGIN_ROOT:-$ROOT}/adapters"
[ -d "$ADAPTERS" ] || ADAPTERS="$ROOT/adapters"
[ -d "$ADAPTERS" ] || exit 0

stacks="$(bash "$ADAPTERS/detect.sh" "$ROOT" 2>/dev/null)"
[ -z "$stacks" ] && exit 0

fails=""
for verb in lint typecheck test build securityscan; do
  for s in $stacks; do
    a="$ADAPTERS/stacks/$s.sh"; [ -f "$a" ] || continue
    ( cd "$ROOT" && bash "$a" "$verb" ) >/dev/null 2>&1 || fails="$fails $s:$verb"
  done
done

sid="nosession"
command -v jq >/dev/null 2>&1 && sid="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
cdir="$ROOT/.loop/state"; mkdir -p "$cdir" 2>/dev/null || true
cf="$cdir/stopgate.${sid}"

if [ -z "$fails" ]; then
  rm -f "$cf" 2>/dev/null || true
  exit 0
fi

n=$(( $(cat "$cf" 2>/dev/null || echo 0) + 1 ))
max="${LOOP_STOP_GATE_MAX_BLOCKS:-3}"
if [ "$n" -le "$max" ]; then
  echo "$n" > "$cf" 2>/dev/null || true
  printf 'Stop gate: failing gates ->%s. Fix them before ending the turn (block %d/%d).\n' "$fails" "$n" "$max" >&2
  exit 2
fi

rm -f "$cf" 2>/dev/null || true
printf 'Stop gate: gates still failing ->%s after %d blocks; allowing stop to avoid wedging. Address manually.\n' "$fails" "$max" >&2
exit 0
