#!/usr/bin/env bash
# loop/lib/gates.sh — deterministic quality gates (CON-030). Requires common.sh,
# config.sh, state.sh, and the adapters. Expects in the environment:
#   REPO_DIR      directory to run gates in (the worktree)
#   ADAPTERS_DIR  path to the adapters/ directory
# A per-verb override in .loop.yml (gates.<verb>) REPLACES the adapter command.

GATE_VERBS_DEFAULT="fmt lint typecheck test build securityscan"

gates_detect_stacks() { bash "$ADAPTERS_DIR/detect.sh" "$REPO_DIR" 2>/dev/null; }

# gate_run_verb <verb> — returns 0 if green/skipped, non-zero if a command failed.
gate_run_verb() {
  local verb="$1" override out rc=0
  override="$(cfg ".gates.$verb" "")"

  if [ -n "$override" ]; then
    info "gate:$verb (override) -> $override"
    out="$( cd "$REPO_DIR" && bash -c "$override" 2>&1 )"; rc=$?
    [ -n "$out" ] && printf '%s\n' "$out" >&2
    if [ $rc -eq 0 ]; then gate_update "$verb" "green" 0 "$override"
    else gate_update "$verb" "red" "$rc" "$override"; fi
    return $rc
  fi

  local stacks; stacks="$(gates_detect_stacks)"
  if [ -z "$stacks" ]; then
    info "gate:$verb -> no stack detected (skipped)"
    gate_update "$verb" "skipped" 0 "(no stack)"
    return 0
  fi

  local stack adapter crc ran=0 skipped_all=1
  for stack in $stacks; do
    adapter="$ADAPTERS_DIR/stacks/$stack.sh"
    [ -f "$adapter" ] || { warn "no adapter for stack '$stack'"; continue; }
    info "gate:$verb ($stack)"
    out="$( cd "$REPO_DIR" && bash "$adapter" "$verb" 2>&1 )"; crc=$?
    [ -n "$out" ] && printf '%s\n' "$out" >&2
    ran=1
    [ $crc -ne 0 ] && rc=$crc
    printf '%s' "$out" | grep -q '\[skip\]' || skipped_all=0
  done

  if   [ $rc -ne 0 ];                              then gate_update "$verb" "red" "$rc" "adapters"
  elif [ $ran -eq 1 ] && [ $skipped_all -eq 1 ];   then gate_update "$verb" "skipped" 0 "adapters"
  else                                                  gate_update "$verb" "green" 0 "adapters"; fi
  return $rc
}

# gates_run_suite [verbs] — run all (or a subset). Returns 0 only if none are red.
gates_run_suite() {
  local verbs="${1:-$GATE_VERBS_DEFAULT}" v overall=0
  info "running gate suite: $verbs"
  for v in $verbs; do
    gate_run_verb "$v" || overall=1
  done
  if [ $overall -eq 0 ]; then ok "gate suite: no failures"; else err "gate suite: failures present"; fi
  return $overall
}

# gates_all_green — true if no gate is red in the current state.
gates_all_green() {
  local reds; reds="$(state_get_raw '.gates // {}' | jq -r '[to_entries[] | select(.value.status=="red")] | length')"
  [ "${reds:-0}" -eq 0 ]
}

# gates_required_ok <required-verbs> <dry_run> — minimum-gates policy (CON-034).
# Every required gate must be GREEN in state: 'skipped' (tool never ran) and
# 'missing' (verb never attempted) fail a LIVE run just like 'red', with a
# message that says how to fix it. In dry-run they only warn: the dry run is the
# zero-cost walk that must work on machines without the target toolchain, and
# its gate results are recorded but advisory.
gates_required_ok() {
  local req="${1:-}" dry="${2:-false}" v st bad=""
  [ -n "${req// /}" ] || return 0
  for v in $req; do
    st="$(state_get_raw ".gates[\"$v\"] // {}" 2>/dev/null | jq -r '.status // "missing"')"
    [ "$st" = "green" ] || bad="$bad $v:$st"
  done
  [ -z "$bad" ] && return 0
  if [ "$dry" = "true" ]; then
    warn "required gate(s) not green (dry-run, advisory):$bad"
    type event >/dev/null 2>&1 && event "gates" "required_gate_not_green_dryrun" \
      "$(jq -nc --arg b "${bad# }" '{gates:$b}')"
    return 0
  fi
  err "required gate(s) not green:$bad — a required gate that never ran is a FAIL, not a pass."
  err "Install the toolchain for it, or point .loop.yml gates.<verb> at your command."
  type event >/dev/null 2>&1 && event "gates" "required_gate_not_green" \
    "$(jq -nc --arg b "${bad# }" '{gates:$b}')"
  return 1
}
