#!/usr/bin/env bash
# Stop hook — run the quality gates before the turn ends (CON-030). If a gate is
# red, exit 2 to block the stop and feed the FAILING OUTPUT back to the model so
# it can fix the cause without re-running the suite to find out what broke
# (CON-037). A per-session block counter prevents a stuck session from being
# wedged; when the hook gives up it records that durably (CON-083) instead of
# vanishing without a trace.
#
# Gate commands resolve exactly like the loop controller's: .loop.yml
# gates.<verb> overrides are honored by sourcing loop/lib/gates.sh, so the hook
# layer and the loop layer can no longer disagree about the same commit. When
# the loop libs or jq are unavailable, falls back to invoking the raw adapters.
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
LOOPLIB="${CLAUDE_PLUGIN_ROOT:-$ROOT}/loop/lib"
[ -d "$LOOPLIB" ] || LOOPLIB="$ROOT/loop/lib"

# The verb list comes from the single source in adapters/lib.sh.
verbs="$(bash "$ADAPTERS/lib.sh" --check-verbs 2>/dev/null)"
[ -n "$verbs" ] || verbs="lint typecheck test build securityscan"

# --- run the suite --------------------------------------------------------
# Preferred path: the controller's own gate resolution (config overrides,
# identical verdicts). Fallback: raw adapters, as before.
fails=""; feedback=""
if command -v jq >/dev/null 2>&1 && [ -f "$LOOPLIB/gates.sh" ]; then
  # shellcheck source=/dev/null
  . "$LOOPLIB/common.sh" 2>/dev/null
  # shellcheck source=/dev/null
  . "$LOOPLIB/config.sh" 2>/dev/null
  # shellcheck source=/dev/null
  . "$LOOPLIB/state.sh" 2>/dev/null
  # shellcheck source=/dev/null
  . "$LOOPLIB/gates.sh" 2>/dev/null
  config_load "$ROOT/.loop.yml" >/dev/null 2>&1 || LOOP_CFG_JSON="{}"
  REPO_DIR="$ROOT"; ADAPTERS_DIR="$ADAPTERS"; export REPO_DIR ADAPTERS_DIR
  unset STATE_FILE 2>/dev/null || true   # gate_update becomes a no-op
  for verb in $verbs; do
    out="$( { gate_run_verb "$verb"; } 2>&1 )" || {
      fails="$fails $verb"
      feedback="$feedback
--- gate:$verb (last 20 lines) ---
$(printf '%s\n' "$out" | tail -n 20)"
    }
  done
else
  stacks="$(bash "$ADAPTERS/detect.sh" "$ROOT" 2>/dev/null)"
  [ -z "$stacks" ] && exit 0
  for verb in $verbs; do
    for s in $stacks; do
      a="$ADAPTERS/stacks/$s.sh"; [ -f "$a" ] || continue
      out="$( cd "$ROOT" && bash "$a" "$verb" 2>&1 )" || {
        fails="$fails $s:$verb"
        feedback="$feedback
--- gate:$verb ($s, last 20 lines) ---
$(printf '%s\n' "$out" | tail -n 20)"
      }
    done
  done
fi

# --- block / give-up bookkeeping -------------------------------------------
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
  {
    printf 'Stop gate: failing gates ->%s. Fix them before ending the turn (block %d/%d).\n' "$fails" "$n" "$max"
    printf '%s\n' "$feedback"
  } >&2
  exit 2
fi

# Giving up must leave a durable trace (CON-083), not silently reset.
rm -f "$cf" 2>/dev/null || true
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
rec="{\"ts\":\"$ts\",\"event\":\"stopgate_gave_up\",\"session\":\"$sid\",\"fails\":\"${fails# }\",\"blocks\":$max}"
printf '%s\n' "$rec" >> "$cdir/stopgate.events.jsonl" 2>/dev/null || true
[ -n "${EVENTS_FILE:-}" ] && [ -f "$EVENTS_FILE" ] && printf '%s\n' "$rec" >> "$EVENTS_FILE" 2>/dev/null
printf 'Stop gate: gates still failing ->%s after %d blocks; allowing stop to avoid wedging. Recorded in %s.\n' "$fails" "$max" "$cdir/stopgate.events.jsonl" >&2
exit 0
