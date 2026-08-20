#!/usr/bin/env bash
# loop/lib/gates.sh — deterministic quality gates (CON-030). Requires common.sh,
# config.sh, state.sh, and the adapters. Expects in the environment:
#   REPO_DIR      directory to run gates in (the worktree)
#   ADAPTERS_DIR  path to the adapters/ directory
# A per-verb override in .loop.yml (gates.<verb>) REPLACES the adapter command.

# The verb vocabulary is defined ONCE in adapters/lib.sh; read it from there.
# (Fallback literals keep the library usable if executing lib.sh ever fails.)
GATE_VERBS_DEFAULT="$(bash "${ADAPTERS_DIR:-adapters}/lib.sh" --verbs 2>/dev/null)"
[ -n "$GATE_VERBS_DEFAULT" ] || GATE_VERBS_DEFAULT="fmt lint typecheck test build securityscan coverage complexity archlint mutation"

# gates_suite_verbs — the verbs the judged suite actually runs, policy-aware:
#   - fmt + the check verbs always;
#   - coverage when a minimum is set or it is required;
#   - complexity when a maximum is set or it is required;
#   - archlint always (skips instantly when the repo has no rules file);
#   - mutation only when the risk profile enables it (expensive).
gates_suite_verbs() {
  local verbs req=" ${LOOP_REQUIRED_GATES:-} "
  verbs="$(bash "${ADAPTERS_DIR:-adapters}/lib.sh" --mutating-verbs 2>/dev/null) $(bash "${ADAPTERS_DIR:-adapters}/lib.sh" --check-verbs 2>/dev/null)"
  [ "${verbs// /}" ] || verbs="fmt lint typecheck test build securityscan"
  if [ "${LOOP_COVERAGE_MIN:-0}" -gt 0 ] 2>/dev/null; then verbs="$verbs coverage"
  else case "$req" in *" coverage "*) verbs="$verbs coverage" ;; esac; fi
  if [ "${LOOP_COMPLEXITY_MAX:-0}" -gt 0 ] 2>/dev/null; then verbs="$verbs complexity"
  else case "$req" in *" complexity "*) verbs="$verbs complexity" ;; esac; fi
  verbs="$verbs archlint"
  [ "${LOOP_MUTATION:-false}" = "true" ] && verbs="$verbs mutation"
  printf '%s' "$verbs"
}

gates_detect_stacks() { bash "$ADAPTERS_DIR/detect.sh" "$REPO_DIR" 2>/dev/null; }

# gate_skip_disallowed <verb> — true when the risk profile marks this verb
# mandatory (skip counts as red): e.g. securityscan on a 'sensitive' change.
gate_skip_disallowed() {
  case " ${LOOP_SKIP_IS_RED:-} " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# gate_log_write <verb> <output> — persist bounded gate output (CON-037) so a
# red gate leaves actionable diagnostics in the run dir, not just an exit code.
# Output is redacted on the way in (CON-090): tool output can echo env/config.
gate_log_write() {
  local verb="$1" cap="${LOOP_GATE_LOG_BYTES:-20000}"
  [ -n "${LOOP_GATE_LOG_DIR:-}" ] || return 0
  mkdir -p "$LOOP_GATE_LOG_DIR" 2>/dev/null || return 0
  printf '%s\n' "$2" | redact_stream | tail -c "$cap" \
    > "$LOOP_GATE_LOG_DIR/$(printf '%s' "$verb" | tr ':' '_').log" 2>/dev/null || true
}

# gate_run_verb <verb> — returns 0 if green/skipped, non-zero if a command failed.
# The fmt verb runs in CHECK mode here (LOOP_FMT_CHECK=1): the judging suite
# must never mutate the tree it judges (CON-038); in-place formatting belongs
# to the PostToolUse hook and `make fmt`.
gate_run_verb() {
  local verb="$1" override out rc=0 fmt_check=0
  [ "$verb" = "fmt" ] && fmt_check=1
  override="$(cfg ".gates.$verb" "")"

  if [ -n "$override" ]; then
    info "gate:$verb (override) -> $override"
    out="$( cd "$REPO_DIR" && LOOP_FMT_CHECK="$fmt_check" bash -c "$override" 2>&1 )"; rc=$?
    [ -n "$out" ] && printf '%s\n' "$out" | redact_stream >&2
    gate_log_write "$verb" "$out"
    if [ $rc -eq 0 ]; then gate_update "$verb" "green" 0 "$override"
    else gate_update "$verb" "red" "$rc" "$override"; fi
    return $rc
  fi

  local stacks; stacks="$(gates_detect_stacks)"
  if [ -z "$stacks" ]; then
    if gate_skip_disallowed "$verb"; then
      err "gate:$verb -> no stack detected, but this gate is MANDATORY for risk '${LOOP_RISK_CLASS:-standard}' (skip counts as red)"
      gate_update "$verb" "red" 1 "skip-not-allowed (risk=${LOOP_RISK_CLASS:-standard})"
      return 1
    fi
    info "gate:$verb -> no stack detected (skipped)"
    gate_update "$verb" "skipped" 0 "(no stack)"
    return 0
  fi

  local stack adapter crc ran=0 skipped_all=1 all_out=""
  for stack in $stacks; do
    adapter="$ADAPTERS_DIR/stacks/$stack.sh"
    [ -f "$adapter" ] || { warn "no adapter for stack '$stack'"; continue; }
    info "gate:$verb ($stack)"
    out="$( cd "$REPO_DIR" && LOOP_FMT_CHECK="$fmt_check" bash "$adapter" "$verb" 2>&1 )"; crc=$?
    [ -n "$out" ] && printf '%s\n' "$out" | redact_stream >&2
    all_out="$all_out== $stack ==
$out
"
    ran=1
    [ $crc -ne 0 ] && rc=$crc
    printf '%s' "$out" | grep -q '\[skip\]' || skipped_all=0
  done
  gate_log_write "$verb" "$all_out"

  if   [ $rc -ne 0 ];                              then gate_update "$verb" "red" "$rc" "adapters"
  elif [ $ran -eq 1 ] && [ $skipped_all -eq 1 ];   then
    if gate_skip_disallowed "$verb"; then
      err "gate:$verb skipped everywhere, but this gate is MANDATORY for risk '${LOOP_RISK_CLASS:-standard}' (skip counts as red)"
      gate_update "$verb" "red" 1 "skip-not-allowed (risk=${LOOP_RISK_CLASS:-standard})"
      return 1
    fi
    gate_update "$verb" "skipped" 0 "adapters"
  else                                                  gate_update "$verb" "green" 0 "adapters"; fi
  return $rc
}

# gate_run_custom <name> <command> — a repo-specific gate from .loop.yml
# (gates.custom.<name>). Recorded as custom:<name>; usable in required_gates.
gate_run_custom() {
  local name="$1" cmd="$2" out rc=0
  info "gate:custom:$name -> $cmd"
  out="$( cd "$REPO_DIR" && bash -c "$cmd" 2>&1 )"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | redact_stream >&2
  gate_log_write "custom:$name" "$out"
  if [ $rc -eq 0 ]; then gate_update "custom:$name" "green" 0 "$cmd"
  else gate_update "custom:$name" "red" "$rc" "$cmd"; fi
  return $rc
}

# gates_run_suite [verbs] — run the policy-aware verb set (or an explicit
# subset), then every custom gate from .loop.yml. Returns 0 only if none are red.
gates_run_suite() {
  local verbs="${1:-$(gates_suite_verbs)}" v overall=0
  info "running gate suite: $verbs"
  for v in $verbs; do
    gate_run_verb "$v" || overall=1
  done
  # Repo-specific custom gates: .loop.yml gates.custom.<name>: "<command>"
  local cname ccmd
  while IFS= read -r cname; do
    [ -n "$cname" ] || continue
    ccmd="$(cfg ".gates.custom[\"$cname\"]" "")"
    [ -n "$ccmd" ] || continue
    gate_run_custom "$cname" "$ccmd" || overall=1
  done < <(printf '%s' "${LOOP_CFG_JSON:-{}}" | jq -r '.gates.custom // {} | keys[]' 2>/dev/null)
  if [ $overall -eq 0 ]; then ok "gate suite: no failures"; else err "gate suite: failures present"; fi
  return $overall
}

# gate_check_protected_paths <base-sha> — model-independent backstop for
# CON-045: red when the branch diff (base..worktree, uncommitted included)
# touches a protected path. The write-time PreToolUse veto is the first line;
# this catches anything that slipped past it (hook disabled, git plumbing,
# tools the matcher never saw). Live runs only — a dry run executes in the
# source checkout, where the operator's own uncommitted edits are none of our
# business.
gate_check_protected_paths() {
  local base="${1:-}" f bad=""
  if [ -z "$base" ] || [ "$base" = "null" ]; then
    gate_update "protected-paths" "skipped" 0 "(no base sha)"; return 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    protected_path_match "$f" && bad="$bad $f"
  done < <(git -C "$REPO_DIR" diff --name-only "$base" 2>/dev/null)
  if [ -n "$bad" ]; then
    err "gate:protected-paths -> branch modifies protected file(s):$bad (CON-045)"
    gate_log_write "protected-paths" "modified protected path(s):$bad
The guardrail chain (hooks, settings, constitution, .loop.yml) is not editable
from inside the loop. Revert these files or have a human apply the change."
    gate_update "protected-paths" "red" 1 "protected paths"
    return 1
  fi
  gate_update "protected-paths" "green" 0 "protected paths"
  return 0
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
