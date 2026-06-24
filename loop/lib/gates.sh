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
  local reds; reds="$(state_get_raw '.gates' | jq -r '[to_entries[] | select(.value.status=="red")] | length')"
  [ "${reds:-0}" -eq 0 ]
}
