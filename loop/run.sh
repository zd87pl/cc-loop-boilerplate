#!/usr/bin/env bash
# loop/run.sh — the spec-driven engineering-loop controller.
#
#   SPEC+PRD+ADR -> specify -> plan -> tasks -> implement -> review -> fix
#   -> verify -> (human pre-merge) -> PR.   Never auto-merges.
#
# Deterministic control flow interprets exit codes, so we intentionally do NOT
# use `set -e` here (many helpers return non-zero as a signal). We do catch
# unset vars and pipe failures.
set -uo pipefail

LOOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$LOOP_DIR/.." && pwd)"
ADAPTERS_DIR="$ROOT_DIR/adapters"
SCHEMA_FILE="$LOOP_DIR/state.schema.json"
export ADAPTERS_DIR

# shellcheck source=lib/common.sh
. "$LOOP_DIR/lib/common.sh"
. "$LOOP_DIR/lib/config.sh"
. "$LOOP_DIR/lib/state.sh"
. "$LOOP_DIR/lib/events.sh"
. "$LOOP_DIR/lib/git.sh"
. "$LOOP_DIR/lib/gates.sh"
. "$LOOP_DIR/lib/claude.sh"
. "$LOOP_DIR/lib/report.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: loop/run.sh [options]

  --spec <dir>     Spec directory to run (overrides .loop.yml spec_dir).
  --dry-run        Walk the full state machine without calling the model or
                   mutating git history. Produces a populated report + matrix.
  --yes, -y        Auto-approve human gates (non-interactive / CI).
  --resume <id>    Resume a previous run id (skips already-passed stages).
  -h, --help       Show this help.

Most configuration lives in .loop.yml. See ONBOARDING.md for a 5-minute start.
USAGE
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
DRY_RUN=false; ASSUME_YES=false; SPEC_DIR_ARG=""; RESUME_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY_RUN=true ;;
    --yes|-y)   ASSUME_YES=true ;;
    --spec)     SPEC_DIR_ARG="${2:-}"; shift ;;
    --resume)   RESUME_ID="${2:-}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          err "unknown argument: $1"; usage; exit 64 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Prerequisites & config
# ---------------------------------------------------------------------------
need git; need jq; need yq
$DRY_RUN || need "${CLAUDE_BIN:-claude}"

cd "$ROOT_DIR"
config_load "$ROOT_DIR/.loop.yml"

SPEC_DIR="${SPEC_DIR_ARG:-$(cfg '.spec_dir' 'specs/')}"
BRANCH_PREFIX="$(cfg '.branch_prefix' 'loop/')"
MAX_ITER="$(cfg '.max_iterations' '6')"
export COST_CEILING_USD="$(cfg '.cost_ceiling_usd' '5.00')"
USE_WORKTREE="$(cfg_bool '.use_worktree' true)"
OPEN_PR="$(cfg_bool '.open_pr' true)"
PR_DRAFT="$(cfg_bool '.pr_draft' true)"
RUNS_DIR="$ROOT_DIR/$(cfg '.runs_dir' '.loop/runs')"
HUMAN_GATES="$(cfg_list '.require_human_gates' | tr '\n' ' ')"
export PROTECTED_BRANCHES="$(cfg_list '.protected_branches' | tr '\n' ' ')"
[ -z "${PROTECTED_BRANCHES// /}" ] && export PROTECTED_BRANCHES="main master"

model_for() { cfg ".models.$1" "${2:-sonnet}"; }
gate_type()  { case " $HUMAN_GATES " in *" $1 "*) echo human ;; *) echo auto ;; esac; }

# ---------------------------------------------------------------------------
# Resolve the active spec
# ---------------------------------------------------------------------------
resolve_spec_path() {
  local d="$1"
  [ -d "$d" ] || { printf ''; return; }
  if [ -f "$d/spec.md" ]; then printf '%s' "$d/spec.md"; return; fi
  find "$d" -name spec.md -type f 2>/dev/null | sort | head -1
}
case "$SPEC_DIR" in /*) SPEC_ABS="$SPEC_DIR" ;; *) SPEC_ABS="$ROOT_DIR/$SPEC_DIR" ;; esac
SPEC_PATH="$(resolve_spec_path "$SPEC_ABS")"
[ -n "$SPEC_PATH" ] || die "no spec.md found under '$SPEC_DIR' (looked in $SPEC_ABS)"
SPEC_ID="$(grep -oE 'SPEC-[0-9]+' "$SPEC_PATH" | head -1 || true)"
[ -n "$SPEC_ID" ] || SPEC_ID="SPEC-$(slugify "$(basename "$(dirname "$SPEC_PATH")")")"

# ---------------------------------------------------------------------------
# Run directory + state
# ---------------------------------------------------------------------------
if [ -n "$RESUME_ID" ]; then
  RUN_ID="$RESUME_ID"
else
  RUN_ID="run-$(date -u +%Y%m%d-%H%M%S)-$(printf '%04x' $RANDOM)"
fi
RUN_DIR="$RUNS_DIR/$RUN_ID"
STATE_FILE="$RUN_DIR/state.json"
EVENTS_FILE="$RUN_DIR/events.jsonl"
export RUN_DIR STATE_FILE EVENTS_FILE
mkdir -p "$RUN_DIR"
: > "$EVENTS_FILE" 2>/dev/null || EVENTS_FILE="$RUN_DIR/events.jsonl"
[ -f "$EVENTS_FILE" ] || : > "$EVENTS_FILE"

BASE_BRANCH="$(cfg '.base_branch' '')"; [ -n "$BASE_BRANCH" ] || BASE_BRANCH="$(git_default_base)"
BRANCH="${BRANCH_PREFIX}$(slugify "$SPEC_ID")-$(printf '%04x' $RANDOM)"
[ -n "$RESUME_ID" ] && [ -f "$STATE_FILE" ] && BRANCH="$(state_get '.git.branch')"

# Safety, demonstrated read-only before any mutation (CON-041).
git_assert_safe_branch "$BRANCH"
if git_is_protected "$BASE_BRANCH"; then
  warn "base branch '$BASE_BRANCH' is protected; the loop will branch off it but never write to it"
fi

REPO_DIR="$ROOT_DIR"; WORKTREE="null"

seed_state() {
  local stages
  stages="$(jq -n \
    --arg g_spec "$(gate_type spec)" \
    --arg g_verify "$(gate_type premerge)" \
    '[
      {name:"spec",     owner:"architect",                       gate:$g_spec,  status:"pending",attempts:0,started_at:null,ended_at:null,artifact:null},
      {name:"plan",     owner:"architect",                       gate:"auto",   status:"pending",attempts:0,started_at:null,ended_at:null,artifact:null},
      {name:"tasks",    owner:"architect",                       gate:"auto",   status:"pending",attempts:0,started_at:null,ended_at:null,artifact:null},
      {name:"implement",owner:"implementer",                     gate:"auto",   status:"pending",attempts:0,started_at:null,ended_at:null,artifact:null},
      {name:"review",   owner:"reviewer+security-auditor",       gate:"auto",   status:"pending",attempts:0,started_at:null,ended_at:null,artifact:null},
      {name:"fix",      owner:"implementer",                     gate:"auto",   status:"pending",attempts:0,started_at:null,ended_at:null,artifact:null},
      {name:"verify",   owner:"verifier",                        gate:$g_verify,status:"pending",attempts:0,started_at:null,ended_at:null,artifact:null}
    ]')"
  jq -n \
    --arg run_id "$RUN_ID" --arg created "$(now_utc)" --argjson dry "$DRY_RUN" \
    --arg spec_dir "$SPEC_DIR" --arg spec_path "$SPEC_PATH" --arg spec_id "$SPEC_ID" \
    --arg base_branch "$BASE_BRANCH" --arg branch "$BRANCH" \
    --arg cfg_hash "$(config_hash)" --argjson max_iter "$MAX_ITER" \
    --argjson cost_ceil "$COST_CEILING_USD" \
    --arg m_spec "$(model_for spec opus)" --arg m_plan "$(model_for plan opus)" \
    --arg m_tasks "$(model_for tasks sonnet)" --arg m_impl "$(model_for implement sonnet)" \
    --arg m_review "$(model_for review opus)" --arg m_fix "$(model_for fix sonnet)" \
    --arg m_verify "$(model_for verify opus)" \
    --arg os "$(uname -s)" --arg versions "$(report_tool_versions)" \
    --argjson stages "$stages" \
    '{
      run_id:$run_id, schema_version:1, status:"pending",
      created_at:$created, updated_at:$created, dry_run:$dry,
      halt_reason:null, current_stage:null, iteration:0,
      spec:{dir:$spec_dir, path:$spec_path, id:$spec_id},
      git:{base_branch:$base_branch, branch:$branch, worktree:null, base_sha:null, head_sha:null},
      config:{hash:$cfg_hash, max_iterations:$max_iter, cost_ceiling_usd:$cost_ceil},
      models:{spec:$m_spec, plan:$m_plan, tasks:$m_tasks, implement:$m_impl, review:$m_review, fix:$m_fix, verify:$m_verify},
      cost:{spent_usd:0, input_tokens:0, output_tokens:0},
      stages:$stages, gates:{}, clarifications:[],
      pr:{opened:false, draft:true, url:null},
      environment:{os:$os, versions:$versions}
    }' > "$STATE_FILE"
}

if [ -n "$RESUME_ID" ] && [ -f "$STATE_FILE" ]; then
  info "resuming run $RUN_ID"
else
  seed_state
fi

ITER="$(state_get '.iteration' 2>/dev/null || echo 0)"

# Render a report no matter how we exit (safety net for the audit trail).
finish() {
  local rc=$?
  [ -f "${STATE_FILE:-/nonexistent}" ] || exit $rc
  local st; st="$(state_get '.status' 2>/dev/null || echo unknown)"
  if [ "$st" = "running" ] || [ "$st" = "pending" ]; then
    state_set_str '.status' "halted"
    state_set_str '.halt_reason' "process exited unexpectedly (rc=$rc)"
    event "controller" "halt" "$(jq -nc --arg r "rc=$rc" '{reason:$r}')"
  fi
  [ -f "$RUN_DIR/traceability.md" ] || report_write_traceability "$SPEC_PATH" "$DRY_RUN" 2>/dev/null || true
  report_render 2>/dev/null || true
}
trap finish EXIT

# ---------------------------------------------------------------------------
# Branch / worktree isolation
# ---------------------------------------------------------------------------
state_set_str '.status' "running"
event "controller" "start" "$(jq -nc --arg b "$BRANCH" --argjson d "$DRY_RUN" '{branch:$b, dry_run:$d}')"
info "spec=$SPEC_PATH  id=$SPEC_ID  branch=$BRANCH  base=$BASE_BRANCH  dry_run=$DRY_RUN"

if $DRY_RUN; then
  info "[dry-run] would create isolated branch '$BRANCH' off '$BASE_BRANCH' (not mutating git)"
  REPO_DIR="$ROOT_DIR"
elif $USE_WORKTREE; then
  WORKTREE="$RUNS_DIR/worktrees/$(slugify "$BRANCH")"
  mkdir -p "$(dirname "$WORKTREE")"
  git_setup_worktree "$BRANCH" "$WORKTREE" || die "failed to create worktree"
  REPO_DIR="$WORKTREE"; state_set_str '.git.worktree' "$WORKTREE"
else
  git_make_feature_branch "$BRANCH"
  git -C "$ROOT_DIR" checkout "$BRANCH" >/dev/null 2>&1 || die "could not checkout $BRANCH"
  REPO_DIR="$ROOT_DIR"
fi
export REPO_DIR
state_set_str '.git.base_sha' "$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo '')"

# ---------------------------------------------------------------------------
# Stage primitives
# ---------------------------------------------------------------------------
bump_attempts() {
  jq --arg n "$1" --arg now "$(now_utc)" \
     '(.stages[]|select(.name==$n)|.attempts) += 1 | .updated_at=$now' "$STATE_FILE" | state_write
}

scan_clarifications() { # returns 0 if a NEEDS CLARIFICATION marker was found
  local text="$1" found=1 line
  while IFS= read -r line; do
    case "$line" in
      *"NEEDS CLARIFICATION:"*) clarification_add "$line"; found=0 ;;
    esac
  done <<EOF
$text
EOF
  return $found
}

halt() { # halt <reason> <status>
  local reason="$1" status="${2:-halted}"
  err "HALT: $reason"
  state_set_str '.status' "$status"
  state_set_str '.halt_reason' "$reason"
  event "controller" "halt" "$(jq -nc --arg r "$reason" --arg s "$status" '{reason:$r, status:$s}')"
}

budget_ok() { awk -v c="$COST_CEILING_USD" -v s="$(cost_spent)" 'BEGIN{exit !(s<c)}'; }

human_gate() { # human_gate <gate-name> <prompt>
  local name="$1" prompt="$2"
  case " $HUMAN_GATES " in *" $name "*) : ;; *) return 0 ;; esac
  event "$name" "human_gate_wait"
  if $DRY_RUN || $ASSUME_YES; then
    info "[auto-approve] human gate '$name' ($($DRY_RUN && echo dry-run || echo --yes))"
    event "$name" "human_gate_auto_approved"; return 0
  fi
  if [ ! -t 0 ]; then
    warn "human gate '$name' needs approval but stdin is not a TTY (CON-060/061)"
    return 1
  fi
  printf '%s%s%s [y/N] ' "$C_YEL" "$prompt" "$C_RST" >&2; read -r ans
  case "${ans:-}" in
    y|Y|yes|YES) event "$name" "human_gate_approved"; return 0 ;;
    *)           event "$name" "human_gate_declined"; return 1 ;;
  esac
}

# Real-model invocation for a stage (skipped entirely in dry-run).
PERM_MODE="${LOOP_PERMISSION_MODE:-acceptEdits}"
tools_for() {
  case "$1" in
    implement|fix) echo "Read Grep Glob Edit Write Bash Task TodoWrite" ;;
    *)             echo "Read Grep Glob Bash Task" ;;  # spec/plan/tasks/review/verify: no Edit/Write
  esac
}
stage_prompt() { # stage_prompt <name>
  local n="$1"
  local common="Constitution: $ROOT_DIR/specs/constitution.md. Active spec: $SPEC_PATH (and sibling prd.md/adr-*.md). Run dir for artifacts: $RUN_DIR. If anything is ambiguous or under-specified, emit a line starting 'NEEDS CLARIFICATION:' and stop — do not guess."
  case "$n" in
    spec)      echo "/spec-init $common Write the normalized EARS spec back to $SPEC_PATH and an open-questions list to $RUN_DIR/open-questions.md." ;;
    plan)      echo "/plan $common Write the technical plan to $RUN_DIR/plan.md." ;;
    tasks)     echo "/tasks $common Read $RUN_DIR/plan.md. Write an ordered, independently testable task list to $RUN_DIR/tasks.md." ;;
    implement) echo "/implement $common Read $RUN_DIR/tasks.md. Implement the next unfinished task with a test, on branch $BRANCH in $REPO_DIR. Commit per task." ;;
    review)    echo "/review $common Adversarially review the diff on $BRANCH and run a security pass. Write findings (with severities + CWE where applicable) to $RUN_DIR/findings.json as {\"findings\":[...]}, and write the count to $RUN_DIR/findings.count." ;;
    fix)       echo "/fix $common Read $RUN_DIR/findings.json. Apply the smallest fixes that resolve the findings, re-running gates. Update $RUN_DIR/findings.count." ;;
    verify)    echo "/verify $common Build the SPEC/PRD/ADR ⇄ code ⇄ test traceability matrix to $RUN_DIR/traceability.md, report drift and coverage. Do not edit code." ;;
  esac
}

read_findings_count() {
  local f="$RUN_DIR/findings.count"
  [ -f "$f" ] && tr -dc '0-9' < "$f" || echo 0
}

# stage_run <name> — advance one stage. Honors resume (skips passed stages),
# dry-run (stubs artifacts + runs real gates), and clarification halts.
stage_run() {
  local name="$1"
  local cur; cur="$(stage_status "$name")"
  if [ "$cur" = "passed" ] && [ -n "$RESUME_ID" ]; then
    info "stage ⏭  $name (already passed; resume)"; return 0
  fi

  state_set_str '.current_stage' "$name"
  stage_update_str "$name" status running
  stage_update_str "$name" started_at "$(now_utc)"
  bump_attempts "$name"
  event "$name" "start"
  info "stage ▶ $name  (model=$(model_for "$name"))"

  local rc=0 text=""
  if $DRY_RUN; then
    stage_dryrun "$name"; rc=$?
  else
    text="$(claude_stage "$name" "$(model_for "$name")" "$PERM_MODE" "$(tools_for "$name")" "$(stage_prompt "$name")")"; rc=$?
    if scan_clarifications "$text"; then
      stage_update_str "$name" status blocked
      stage_update_str "$name" ended_at "$(now_utc)"
      event "$name" "needs_clarification"
      halt "stage '$name' emitted NEEDS CLARIFICATION" "needs_clarification"
      return 10
    fi
  fi
  event_cost "$name"

  if [ $rc -ne 0 ]; then
    stage_update_str "$name" status failed
    stage_update_str "$name" ended_at "$(now_utc)"
    event "$name" "failed" "$(jq -nc --argjson rc "$rc" '{rc:$rc}')"
    warn "stage ✘ $name (rc=$rc)"
    return $rc
  fi
  stage_update_str "$name" status passed
  stage_update_str "$name" ended_at "$(now_utc)"
  event "$name" "passed"
  ok "stage ✔ $name"
  return 0
}

# Dry-run behavior per stage: produce a stub artifact and exercise real gates.
stage_dryrun() {
  local name="$1"
  case "$name" in
    spec)
      # Honor the contract: if the real spec carries open questions, halt.
      if grep -q 'NEEDS CLARIFICATION:' "$SPEC_PATH"; then
        clarification_add "$(grep 'NEEDS CLARIFICATION:' "$SPEC_PATH" | head -1)"
        return 0  # caller's scan handles real runs; for dry-run we note + continue example has none
      fi
      printf '# Normalized spec (dry-run stub)\nSee %s\n' "$SPEC_PATH" > "$RUN_DIR/spec.normalized.md" ;;
    plan)      printf '# Technical plan (dry-run stub)\nDerived from %s\n' "$SPEC_PATH" > "$RUN_DIR/plan.md" ;;
    tasks)     printf '# Tasks (dry-run stub)\n- T1: implement parser core\n- T2: error handling\n- T3: CLI wrapper\n' > "$RUN_DIR/tasks.md" ;;
    implement)
      printf '# Implement (dry-run stub) — no code generated\n' > "$RUN_DIR/implement.md"
      gates_run_suite >/dev/null 2>&1 || true ;;          # run the REAL gate suite
    review)
      if [ -f "$RUN_DIR/.dry_fixed" ]; then echo 0 > "$RUN_DIR/findings.count"
      else echo 1 > "$RUN_DIR/findings.count"
           printf '{"findings":[{"id":"F1","severity":"low","cwe":"CWE-20","title":"dry-run synthetic finding"}]}\n' > "$RUN_DIR/findings.json"
      fi ;;
    fix)
      touch "$RUN_DIR/.dry_fixed"; echo 0 > "$RUN_DIR/findings.count"
      gates_run_suite >/dev/null 2>&1 || true ;;
    verify)
      report_write_traceability "$SPEC_PATH" "true" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Drive the state machine
# ---------------------------------------------------------------------------
stage_run spec      || exit $?
human_gate spec     "Approve the normalized spec and proceed to PLAN?" || { halt "spec gate declined" halted; exit 0; }

stage_run plan      || exit $?
stage_run tasks     || exit $?
stage_run implement || exit $?

# review <-> fix loop (CON-031, CON-050, CON-052)
stage_run review || exit $?
findings="$(read_findings_count)"; prev=-1
while [ "${findings:-0}" -gt 0 ]; do
  if [ "$ITER" -ge "$MAX_ITER" ]; then halt "max_iterations ($MAX_ITER) reached" partial; break; fi
  if ! budget_ok; then halt "cost ceiling (\$$COST_CEILING_USD) reached" partial; break; fi
  if [ "$findings" -eq "$prev" ]; then halt "no measurable progress (findings stuck at $findings)" halted; break; fi
  prev="$findings"
  stage_run fix || exit $?
  gates_run_suite >/dev/null 2>&1 || warn "gates red after fix"
  ITER=$((ITER+1)); state_set '.iteration' "$ITER"
  event "controller" "iteration" "$(jq -nc --argjson i "$ITER" '{iteration:$i}')"
  stage_run review || exit $?
  findings="$(read_findings_count)"
done

# If we halted inside the loop, stop here (report rendered by trap).
case "$(state_get '.status')" in halted|partial|needs_clarification) exit 0 ;; esac

# Final gate suite must be green before verify's human pre-merge gate (CON-031).
gates_run_suite >/dev/null 2>&1
if ! gates_all_green; then
  halt "quality gates are red; cannot proceed to pre-merge" partial; exit 0
fi

stage_run verify || exit $?
report_write_traceability "$SPEC_PATH" "$DRY_RUN"

human_gate premerge "Approve the traceability matrix and open a PR (never auto-merge)?" \
  || { halt "pre-merge gate declined" halted; exit 0; }

# ---------------------------------------------------------------------------
# Finalize: head SHA, status, PR (never merge)
# ---------------------------------------------------------------------------
state_set_str '.git.head_sha' "$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo '')"
state_set_str '.status' "completed"
event "controller" "completed"

open_pr() {
  $OPEN_PR || { info "open_pr disabled in .loop.yml"; return 0; }
  if $DRY_RUN; then
    info "[dry-run] would open a$($PR_DRAFT && echo ' draft') PR for '$BRANCH' -> '$BASE_BRANCH' (never auto-merge)"
    return 0
  fi
  if ! have gh; then
    warn "gh not installed/authenticated — not opening a PR."
    warn "Manual: git -C '$REPO_DIR' push -u origin '$BRANCH' && open a PR against '$BASE_BRANCH'."
    return 0
  fi
  local args=(pr create --title "loop: $SPEC_ID" --body-file "$RUN_DIR/report.md" --base "$BASE_BRANCH" --head "$BRANCH")
  $PR_DRAFT && args+=(--draft)
  local url
  if url="$( cd "$REPO_DIR" && git push -u origin "$BRANCH" >/dev/null 2>&1 && gh "${args[@]}" 2>/dev/null )"; then
    state_set_str '.pr.url' "$url"; state_set '.pr.opened' true
    ok "PR opened: $url"
  else
    warn "could not open PR automatically; push '$BRANCH' and open one manually."
  fi
}
open_pr

ok "loop complete: status=$(state_get '.status')"
info "report: $RUN_DIR/report.md"
exit 0
