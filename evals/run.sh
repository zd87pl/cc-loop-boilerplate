#!/usr/bin/env bash
# evals/run.sh — assert the loop's deterministic guardrails on fixtures.
#
# No model calls: every case is deterministic, so this is safe and free to run in
# CI on every PR. It proves the guardrails actually fire — halt-on-ambiguity,
# spec-lint, secret/destructive veto, protected-branch refusal — and that a real
# stack gate executes and passes. Exit 0 only if every case passes.
#
# Model-dependent guardrails (ADR-conflict / drift detection) are not asserted
# here; they require a live `make loop` run and live fixtures.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

pass=0; fail=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31mFAIL\033[0m %s — %s\n' "$1" "$2"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Run the loop in dry-run against a spec dir, isolated from real .loop state, and
# echo the final run status. Honors LOOP_CONFIG / LOOP_DRYRUN_FAULT from the
# caller's environment (fixture injection).
loop_status() {
  LOOP_RUNS_DIR="$TMP/runs" LOOP_MEMORY_FILE="$TMP/mem.md" LOOP_BACKLOG_FILE="$TMP/bk.md" \
  LOOP_TRUST_FILE="$TMP/trust.jsonl" \
    bash loop/run.sh --dry-run --spec "$1" --yes >/dev/null 2>&1 || true
  local sf; sf="$(ls -1dt "$TMP"/runs/run-* 2>/dev/null | head -1)/state.json"
  jq -r '.status // "MISSING"' "$sf" 2>/dev/null || echo "MISSING"
}
# Same, but echo "<status> <exit-code>" so cases can assert the CON-082 mapping.
loop_status_rc() {
  local rc
  LOOP_RUNS_DIR="$TMP/runs" LOOP_MEMORY_FILE="$TMP/mem.md" LOOP_BACKLOG_FILE="$TMP/bk.md" \
  LOOP_TRUST_FILE="$TMP/trust.jsonl" \
    bash loop/run.sh --dry-run --spec "$1" --yes >/dev/null 2>&1; rc=$?
  local sf; sf="$(ls -1dt "$TMP"/runs/run-* 2>/dev/null | head -1)/state.json"
  printf '%s %s' "$(jq -r '.status // "MISSING"' "$sf" 2>/dev/null || echo MISSING)" "$rc"
}
hook_exit() { printf '%s' "$2" | bash ".claude/hooks/$1" >/dev/null 2>&1; echo $?; }

echo "Spec-loop evals (deterministic, no model)"

# 1) a clean spec completes
s="$(loop_status specs/000-example)"
[ "$s" = "completed" ] && ok "clean spec → completed" || no "clean spec" "status='$s'"

# 2) an ambiguous spec (NEEDS CLARIFICATION marker) halts for a human
s="$(loop_status evals/cases/ambiguous-halts)"
[ "$s" = "needs_clarification" ] && ok "ambiguous spec → needs_clarification" || no "ambiguous spec" "status='$s'"

# 3) a lint-failing spec halts before the model review
s="$(loop_status evals/cases/lint-fail)"
[ "$s" = "needs_clarification" ] && ok "lint-failing spec → halts before review" || no "lint-fail spec" "status='$s'"

# 4) spec-lint accepts a good spec
if bash scripts/spec-lint.sh specs/000-example/spec.md >/dev/null 2>&1; then ok "spec-lint accepts the example"; else no "spec-lint good" "expected exit 0"; fi

# 5) spec-lint rejects a broken spec
if bash scripts/spec-lint.sh evals/cases/lint-fail/spec.md >/dev/null 2>&1; then no "spec-lint bad" "expected nonzero"; else ok "spec-lint rejects a broken spec"; fi

# 6) a secret write is vetoed (exit 2). The test key is assembled from fragments
#    at runtime so this file itself carries no matchable secret.
akid="AKIA""IOSFODNN7EXAMPLE"
rc="$(printf '{"tool_name":"Write","tool_input":{"content":"token=%s end"}}' "$akid" | bash .claude/hooks/pretool-guard.sh >/dev/null 2>&1; echo $?)"
[ "$rc" = "2" ] && ok "secret write vetoed (exit 2)" || no "secret veto" "exit=$rc"

# 7) a destructive command is vetoed (exit 2)
rc="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}')"
[ "$rc" = "2" ] && ok "force-push vetoed (exit 2)" || no "destructive veto" "exit=$rc"

# 7b) a private-key block is vetoed (regression: the pattern started with '-' so
#     grep ate it as a flag and the check failed open). Fragments keep this file
#     itself unmatched.
pk="-----BEGIN"" RSA PRIVATE KEY-----"
rc="$(printf '{"tool_name":"Write","tool_input":{"content":"%s body"}}' "$pk" | bash .claude/hooks/pretool-guard.sh >/dev/null 2>&1; echo $?)"
[ "$rc" = "2" ] && ok "private-key write vetoed (exit 2)" || no "private-key veto" "exit=$rc"

# 7c) --force-with-lease alone is allowed; a compound with a bare --force is denied
rc="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin feat"}}')"
[ "$rc" = "0" ] && ok "--force-with-lease allowed (exit 0)" || no "lease allowed" "exit=$rc"
rc="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin a && git push --force origin main"}}')"
[ "$rc" = "2" ] && ok "compound --force behind lease vetoed (exit 2)" || no "compound force" "exit=$rc"

# 7d) git clean with flags in -d -f order is still vetoed
rc="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git clean -df ."}}')"
[ "$rc" = "2" ] && ok "git clean -df vetoed (exit 2)" || no "git clean veto" "exit=$rc"

# 7e) rm veto targets the CATASTROPHIC class only: roots, system depth-1 dirs,
#     homes, .git — while deep scratch cleanup (mktemp dirs) stays allowed.
rc="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"rm -fr /usr"}}')"
r2="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"rm -rf .git"}}')"
r3="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"rm -fr /tmp/x"}}')"
if [ "$rc" = "2" ] && [ "$r2" = "2" ] && [ "$r3" = "0" ]; then
  ok "rm veto: /usr and .git denied, /tmp/x scratch allowed"
else no "rm veto scope" "usr=$rc git=$r2 tmp=$r3"; fi

# 7f) a force-push with the flag at the END of the command is still vetoed
#     (regression: 'git push origin main -f' slipped past the pattern list)
rc="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin main -f"}}')"
[ "$rc" = "2" ] && ok "trailing -f force-push vetoed (exit 2)" || no "trailing -f veto" "exit=$rc"

# 8) protected-branch guard: main refused, a feature branch allowed
if ( . loop/lib/common.sh; . loop/lib/git.sh; PROTECTED_BRANCHES="main master"; git_is_protected main && ! git_is_protected loop/x ); then
  ok "protected-branch guard (main refused, feature allowed)"
else no "protected branch" "guard incorrect"; fi

# 9) a real stack gate executes and passes (not skipped)
if ( cd examples/duration-py && bash ../../adapters/stacks/python.sh test ) >/dev/null 2>&1; then
  ok "real python gate passes"
else no "real gate" "example tests failed"; fi

# 10) an explicit `false` in the config is honored (regression: jq's `// empty`
#     treated false as absent, so no boolean setting could ever be switched off)
if ( . loop/lib/common.sh; . loop/lib/config.sh
     LOOP_CFG_JSON='{"use_worktree":false,"spec_review":{"enabled":false}}'
     [ "$(cfg_bool '.use_worktree' true)" = "false" ] \
  && [ "$(cfg_bool '.spec_review.enabled' true)" = "false" ] \
  && [ "$(cfg_bool '.spec_lint.enabled' true)" = "true" ] ); then
  ok "explicit boolean 'false' in config honored"
else no "config false override" "cfg_bool fell back to the default"; fi

# 11) an empty / comments-only .loop.yml falls back to defaults instead of dying
#     ("an empty or partial file still works" is the documented contract)
printf '# comments only\n' > "$TMP/empty.yml"
if ( . loop/lib/common.sh; . loop/lib/config.sh
     config_load "$TMP/empty.yml" 2>/dev/null
     [ "$(cfg '.max_iterations' 6)" = "6" ] ); then
  ok "empty .loop.yml -> built-in defaults"
else no "empty config" "config_load rejected an empty file"; fi

# 12) constitution rule ids are unique. Skills, agents, and the traceability
#     matrix cite CON-NNN ids, so a duplicate definition breaks the contract's
#     own "individually testable and citable" claim (regression: CON-020/021
#     were each defined twice).
dups="$(grep -oE '^- \*\*CON-[0-9]+\*\*' specs/constitution.md | sort | uniq -d | grep -oE 'CON-[0-9]+' | paste -sd, -)"
[ -z "$dups" ] && ok "constitution CON ids unique" || no "constitution ids" "duplicates: $dups"

# ---------------------------------------------------------------------------
# Fail-closed core (CON-026/033/034/035/036/082)
# ---------------------------------------------------------------------------

# 13) THE load-bearing proof: a RED required gate halts the loop before premerge
#     (status partial, exit 30). Injected via LOOP_CONFIG so no repo file changes.
printf 'gates:\n  test: "false"\nrequired_gates: [test]\n' > "$TMP/red.yml"
sr="$(LOOP_CONFIG="$TMP/red.yml" loop_status_rc specs/000-example)"
[ "$sr" = "partial 30" ] && ok "red required gate halts the loop (partial, exit 30)" \
                         || no "red gate halts" "status/rc='$sr' (want 'partial 30')"

# 14) exit-code mapping (CON-082): clean spec exits 0; ambiguous spec exits 10.
sr="$(loop_status_rc specs/000-example)"
[ "$sr" = "completed 0" ] && ok "clean spec exits 0" || no "exit code clean" "'$sr'"
sr="$(loop_status_rc evals/cases/ambiguous-halts)"
[ "$sr" = "needs_clarification 10" ] && ok "ambiguous spec exits 10" || no "exit code ambiguous" "'$sr'"

# 15) a malformed spec-review verdict fails CLOSED (regression: a missing/garbage
#     verdict used to default to READY and sail on).
sr="$(LOOP_DRYRUN_FAULT=bad_verdict loop_status_rc specs/000-example)"
[ "$sr" = "needs_clarification 10" ] && ok "malformed verdict halts (fail-closed)" \
                                     || no "malformed verdict" "'$sr'"
if ( . loop/lib/common.sh; . loop/lib/artifacts.sh
     printf 'REDDY' > "$TMP/v1"; printf ' READY\n' > "$TMP/v2"
     ! artifact_token "$TMP/v1" READY CAVEATS NOT_READY >/dev/null \
     && [ "$(artifact_token "$TMP/v2" READY CAVEATS NOT_READY)" = "READY" ] \
     && ! artifact_token "$TMP/nonexistent" READY >/dev/null ); then
  ok "artifact_token: whitelist + whitespace + missing-file semantics"
else no "artifact_token" "unit checks failed"; fi

# 16) a CAVEATS verdict proceeds but the caveat is carried to the backlog (CON-019).
: > "$TMP/bk.md"
s="$(LOOP_DRYRUN_FAULT=caveats_verdict loop_status specs/000-example)"
if [ "$s" = "completed" ] && grep -q 'CAVEATS' "$TMP/bk.md" 2>/dev/null; then
  ok "CAVEATS verdict completes + carried to backlog"
else no "caveats carry" "status='$s', backlog: $(grep -c CAVEATS "$TMP/bk.md" 2>/dev/null || echo 0) hits"; fi

# 17) garbage findings fail CLOSED, end-to-end and at the unit level (CON-033):
#     the review loop's control variable is derived from schema-valid JSON, so
#     '3 findings (2 high)' can never be read as the number 32 again.
s="$(LOOP_DRYRUN_FAULT=bad_findings loop_status specs/000-example)"
[ "$s" = "needs_clarification" ] && ok "garbage findings.json halts the run" || no "bad findings e2e" "status='$s'"
s="$(LOOP_DRYRUN_FAULT=missing_findings loop_status specs/000-example)"
[ "$s" = "needs_clarification" ] && ok "missing findings.json halts the run" || no "missing findings e2e" "status='$s'"
if ( . loop/lib/common.sh; . loop/lib/artifacts.sh
     printf '{"findings":"3 findings (2 high)"}' > "$TMP/f1.json"
     printf '{"findings":[{"id":"A","severity":"urgent","title":"x"}]}' > "$TMP/f2.json"
     printf '{"findings":[{"id":"A","severity":"high","title":"a"},{"id":"B","severity":"high","title":"b"},{"id":"C","severity":"low","title":"c"}]}' > "$TMP/f3.json"
     ! findings_validate "$TMP/f1.json" \
     && ! findings_validate "$TMP/f2.json" \
     && [ "$(findings_count "$TMP/f3.json" high)" = "2" ] \
     && [ "$(findings_count "$TMP/f3.json" low)" = "3" ] \
     && [ "$(findings_below "$TMP/f3.json" high | wc -l | tr -d ' ')" = "1" ] ); then
  ok "findings schema + severity-count + deferred-list semantics"
else no "findings units" "validate/count/below checks failed"; fi

# 18) a FAIL verify verdict blocks before premerge (CON-036).
sr="$(LOOP_DRYRUN_FAULT=verify_fail loop_status_rc specs/000-example)"
[ "$sr" = "partial 30" ] && ok "verify FAIL blocks premerge (partial, exit 30)" || no "verify fail" "'$sr'"

# 19) required-gate policy semantics (CON-034): skipped/missing required gates
#     fail a live run, warn in dry-run, and green passes. Unit-tested against a
#     fixture state file.
if ( . loop/lib/common.sh; . loop/lib/config.sh; LOOP_CFG_JSON='{}'
     . loop/lib/state.sh; . loop/lib/gates.sh
     export STATE_FILE="$TMP/gstate.json"
     printf '{"gates":{"test":{"status":"skipped"},"lint":{"status":"green"}}}' > "$STATE_FILE"
     ! gates_required_ok "test" false \
     &&  gates_required_ok "test" true \
     &&  gates_required_ok "lint" false \
     && ! gates_required_ok "test lint" false \
     &&  gates_required_ok "" false ) >/dev/null 2>&1; then
  ok "required-gate policy: skip=fail live, warn dry, green passes"
else no "required gates" "policy semantics wrong"; fi

# 20) the verifier's real traceability matrix is never overwritten by the stub
#     (regression: an unconditional rewrite stamped '_pending verifier_' over the
#     evidence right before the human premerge gate). Source-level pin: the
#     driver-form call (with "$DRY_RUN") must always sit behind a [ -f ... ] ||
#     guard; only the dry-run verify stub (literal "true") may call it bare.
if grep -qE '^[[:space:]]*report_write_traceability "\$SPEC_PATH" "\$DRY_RUN"' loop/run.sh; then
  no "traceability guard" "found an unguarded report_write_traceability call in loop/run.sh"
else
  ok "traceability overwrite is guarded (verifier's matrix preserved)"
fi

# ---------------------------------------------------------------------------
# Gate vocabulary + risk profiles (CON-039)
# ---------------------------------------------------------------------------
latest_state() { printf '%s' "$(ls -1dt "$TMP"/runs/run-* 2>/dev/null | head -1)/state.json"; }

# 21) the verb vocabulary has ONE definition (adapters/lib.sh) and consumers
#     read it from there instead of keeping copies.
verbs="$(bash adapters/lib.sh --verbs 2>/dev/null)"
checkverbs="$(bash adapters/lib.sh --check-verbs 2>/dev/null)"
if [ "$verbs" = "fmt lint typecheck test build securityscan coverage complexity archlint mutation" ] \
   && [ "$checkverbs" = "lint typecheck test build securityscan" ] \
   && ! grep -q 'for v in lint typecheck test build securityscan' Makefile; then
  ok "verb vocabulary single-sourced from adapters/lib.sh"
else no "verb single-source" "verbs='$verbs' check='$checkverbs'"; fi

# 22) sensitive risk class makes the security pass MANDATORY (skip counts as
#     red) and raises the coverage bar — risk calibration is mechanical, not
#     cosmetic. The fixture spec mentions 'password' so the dry-run stub
#     classifies it sensitive; this toolchain-less repo then FAILS the run.
s="$(loop_status evals/cases/sensitive-spec)"
sf="$(latest_state)"
if [ "$s" = "partial" ] \
   && [ "$(jq -r '.spec.risk_class' "$sf")" = "sensitive" ] \
   && [ "$(jq -r '.config.effective_coverage_threshold' "$sf")" = "80" ] \
   && [ "$(jq -r '.gates.securityscan.status' "$sf")" = "red" ]; then
  ok "sensitive profile: mandatory securityscan skip=red halts, coverage bar raised"
else no "sensitive profile" "status='$s' risk=$(jq -r '.spec.risk_class' "$sf" 2>/dev/null) cov=$(jq -r '.config.effective_coverage_threshold' "$sf" 2>/dev/null) sec=$(jq -r '.gates.securityscan.status' "$sf" 2>/dev/null)"; fi

# 23) custom gates from config run in the suite and can block the run.
printf 'gates:\n  custom:\n    hello: "false"\n' > "$TMP/custom-red.yml"
s="$(LOOP_CONFIG="$TMP/custom-red.yml" loop_status specs/000-example)"
[ "$s" = "partial" ] && ok "red custom gate blocks the run" || no "custom gate red" "status='$s'"
printf 'gates:\n  custom:\n    hello: "true"\n' > "$TMP/custom-green.yml"
s="$(LOOP_CONFIG="$TMP/custom-green.yml" loop_status specs/000-example)"
if [ "$s" = "completed" ] && [ "$(jq -r '.gates["custom:hello"].status' "$(latest_state)")" = "green" ]; then
  ok "green custom gate recorded and run completes"
else no "custom gate green" "status='$s'"; fi

# 24) shared helpers: coverage comparison + complexity grade mapping.
if ( . adapters/lib.sh
     coverage_compare 85.5 80 && ! coverage_compare 79 80 && coverage_compare 80 80 \
     && [ "$(complexity_grade 10)" = "B" ] && [ "$(complexity_grade 21)" = "D" ] ); then
  ok "coverage_compare + complexity_grade helpers"
else no "adapter helpers" "comparison/mapping wrong"; fi

# 25) a profile can override max_iterations (bounds calibrate to risk).
printf 'risk_profiles:\n  standard:\n    max_iterations: 0\n' > "$TMP/iter0.yml"
s="$(LOOP_CONFIG="$TMP/iter0.yml" loop_status specs/000-example)"
sf="$(latest_state)"
if [ "$s" = "partial" ] && jq -r '.halt_reason' "$sf" | grep -q 'max_iterations (0)'; then
  ok "profile max_iterations override enforced"
else no "profile max_iter" "status='$s' reason='$(jq -r '.halt_reason' "$sf" 2>/dev/null)'"; fi

# ---------------------------------------------------------------------------
# Feedback quality (CON-037/038/083 + CON-080)
# ---------------------------------------------------------------------------

# 26) a red gate leaves its OUTPUT in the run dir and the report — an exit code
#     with no diagnostics is not actionable feedback (CON-037).
printf 'gates:\n  test: "echo BOOM-DIAGNOSTIC; exit 1"\n' > "$TMP/boom.yml"
s="$(LOOP_CONFIG="$TMP/boom.yml" loop_status specs/000-example)"
rd="$(dirname "$(latest_state)")"
if [ "$s" = "partial" ] && grep -q 'BOOM-DIAGNOSTIC' "$rd/gates/test.log" 2>/dev/null \
   && grep -q 'BOOM-DIAGNOSTIC' "$rd/report.md" 2>/dev/null; then
  ok "red-gate output captured in gates/test.log + report excerpt"
else no "gate output capture" "status='$s' log=$(ls "$rd/gates" 2>/dev/null | paste -sd, -)"; fi

# 27) the Stop hook resolves gates like the controller: .loop.yml overrides are
#     honored, and failure output is fed back to the model before exit 2.
mkdir -p "$TMP/proj/.loop"
printf 'gates:\n  lint: "echo LINT-SAYS-NO; exit 1"\n' > "$TMP/proj/.loop.yml"
serr="$TMP/stopgate.err"
printf '{"session_id":"eval1"}' \
  | CLAUDE_PROJECT_DIR="$TMP/proj" CLAUDE_PLUGIN_ROOT="$PWD" bash .claude/hooks/stop-gate.sh >/dev/null 2>"$serr"
rc=$?
if [ "$rc" = "2" ] && grep -q 'lint' "$serr" && grep -q 'LINT-SAYS-NO' "$serr"; then
  ok "stop hook honors config overrides + feeds failure output back (exit 2)"
else no "stop-gate overrides" "rc=$rc stderr=$(head -c 120 "$serr" 2>/dev/null)"; fi
printf 'gates:\n  lint: "true"\n' > "$TMP/proj/.loop.yml"
rc="$(printf '{"session_id":"eval1"}' \
  | CLAUDE_PROJECT_DIR="$TMP/proj" CLAUDE_PLUGIN_ROOT="$PWD" bash .claude/hooks/stop-gate.sh >/dev/null 2>&1; echo $?)"
[ "$rc" = "0" ] && ok "stop hook passes when the override passes (exit 0)" || no "stop-gate green" "rc=$rc"

# 28) the judged suite runs fmt in CHECK mode — it must not mutate the tree it
#     judges (CON-038). Proven with a PATH-shim ruff that records its args.
mkdir -p "$TMP/bin" "$TMP/fmtproj"
printf '#!/usr/bin/env bash\necho "$@" > "${RUFF_ARGS_FILE:?}"\nexit 0\n' > "$TMP/bin/ruff"
chmod +x "$TMP/bin/ruff"
touch "$TMP/fmtproj/pyproject.toml"
( cd "$TMP/fmtproj" && PATH="$TMP/bin:$PATH" RUFF_ARGS_FILE="$TMP/ruff.args" LOOP_FMT_CHECK=1 \
    bash "$ROOT/adapters/stacks/python.sh" fmt ) >/dev/null 2>&1
( cd "$TMP/fmtproj" && PATH="$TMP/bin:$PATH" RUFF_ARGS_FILE="$TMP/ruff2.args" \
    bash "$ROOT/adapters/stacks/python.sh" fmt ) >/dev/null 2>&1
if grep -q -- '--check' "$TMP/ruff.args" 2>/dev/null && ! grep -q -- '--check' "$TMP/ruff2.args" 2>/dev/null; then
  ok "fmt runs --check under LOOP_FMT_CHECK=1, in-place otherwise"
else no "fmt check-mode" "args: '$(cat "$TMP/ruff.args" 2>/dev/null)' / '$(cat "$TMP/ruff2.args" 2>/dev/null)'"; fi

# 29) stage events carry duration + git SHA (CON-080), and the state file
#     records the resolved risk profile and exit code.
s="$(loop_status specs/000-example)"
rd="$(dirname "$(latest_state)")"
if [ "$s" = "completed" ] \
   && jq -e 'select(.result=="passed" and has("duration_s") and has("head_sha"))' "$rd/events.jsonl" >/dev/null 2>&1 \
   && [ "$(jq -r '.config.risk_profile' "$rd/state.json")" = "standard" ] \
   && [ "$(jq -r '.exit_code' "$rd/state.json")" = "0" ]; then
  ok "events enriched (duration_s, head_sha) + state records profile/exit_code"
else no "events/state enrichment" "status='$s'"; fi

# 30) when the stop gate gives up after N blocks, it records that durably
#     (CON-083) instead of silently resetting.
mkdir -p "$TMP/proj2/.loop"
printf 'gates:\n  lint: "exit 1"\n' > "$TMP/proj2/.loop.yml"
printf '{"session_id":"eval2"}' \
  | CLAUDE_PROJECT_DIR="$TMP/proj2" CLAUDE_PLUGIN_ROOT="$PWD" LOOP_STOP_GATE_MAX_BLOCKS=1 \
    bash .claude/hooks/stop-gate.sh >/dev/null 2>&1
rc="$(printf '{"session_id":"eval2"}' \
  | CLAUDE_PROJECT_DIR="$TMP/proj2" CLAUDE_PLUGIN_ROOT="$PWD" LOOP_STOP_GATE_MAX_BLOCKS=1 \
    bash .claude/hooks/stop-gate.sh >/dev/null 2>&1; echo $?)"
if [ "$rc" = "0" ] && jq -e 'select(.event=="stopgate_gave_up")' "$TMP/proj2/.loop/state/stopgate.events.jsonl" >/dev/null 2>&1; then
  ok "stop-gate give-up is durably recorded (stopgate.events.jsonl)"
else no "stop-gate durable record" "rc=$rc file=$(ls "$TMP/proj2/.loop/state" 2>/dev/null | paste -sd, -)"; fi

# ---------------------------------------------------------------------------
# Guardrail integrity (CON-042/043/045/072/090)
# ---------------------------------------------------------------------------

# guard <json> [K=V ...] — run the PreToolUse guard with a clean guard env.
guard() {
  local json="$1"; shift
  (
    unset LOOP_STAGE LOOP_RUN_DIR LOOP_PROTECTED_PATHS LOOP_ALLOW_PROTECTED \
          LOOP_SECRET_SCAN LOOP_SECRET_SCANNER
    local kv; for kv in "$@"; do export "${kv?}"; done
    printf '%s' "$json" | CLAUDE_PROJECT_DIR="$PWD" bash .claude/hooks/pretool-guard.sh >/dev/null 2>&1
    echo $?
  )
}
bashjson() { jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
writejson() { jq -nc --arg f "$1" --arg c "${2:-hello}" '{tool_name:"Write", tool_input:{file_path:$f, content:$c}}'; }

# 31) hook and controller share ONE destructive-command implementation: verdicts
#     must agree, and match expectations — including forms the old substring
#     matcher missed (git -C, +refspec, combined -fD, sudo/env prefixes) and
#     false positives it used to have (echo "git reset --hard").
ld() { ( . loop/lib/common.sh; looks_destructive "$1" && echo 2 || echo 0 ); }
par_fail=""
while IFS='|' read -r want c; do
  [ -n "$c" ] || continue
  h="$(guard "$(bashjson "$c")")"; l="$(ld "$c")"
  { [ "$h" = "$want" ] && [ "$l" = "$want" ]; } || par_fail="$par_fail [$c: want=$want hook=$h lib=$l]"
done <<'CMDS'
2|git -C sub reset --hard HEAD~1
2|git push --force-with-lease origin x && git push --force origin x
2|git push origin +main
2|git branch -fD topic
2|sudo git clean -fdx
2|FOO=1 git push -f origin main
2|rm -rf .git
0|git push --force-with-lease origin x
0|git clean -n -fd
0|git push origin main
0|rm -rf build/
0|echo git reset --hard is dangerous
0|git log --oneline -5
CMDS
[ -z "$par_fail" ] && ok "destructive veto: hook == controller lib, incl. -C/+ref/-fD/prefix forms" \
  || no "destructive parity" "$par_fail"

# 32) protected paths (CON-045): stage sessions cannot touch the guardrail
#     chain; interactive sessions can; LOOP_ALLOW_PROTECTED=1 lifts it; a
#     custom protected_paths set REPLACES the default.
r1="$(guard "$(writejson .loop.yml)" LOOP_STAGE=implement)"
r2="$(guard "$(writejson .loop.yml)" LOOP_STAGE=implement LOOP_ALLOW_PROTECTED=1)"
r3="$(guard "$(writejson .loop.yml)")"
r4="$(guard "$(bashjson 'echo x >> .claude/settings.json')" LOOP_STAGE=implement)"
r5="$(guard "$(bashjson 'cat .claude/settings.json')" LOOP_STAGE=implement)"
r6="$(guard "$(bashjson "sed -n '1,5p' specs/constitution.md")" LOOP_STAGE=implement)"
r7="$(guard "$(bashjson 'sed -i s/a/b/ .loop.yml')" LOOP_STAGE=implement)"
r8="$(guard "$(writejson docs/x.md)" LOOP_STAGE=implement 'LOOP_PROTECTED_PATHS=docs/*')"
r9="$(guard "$(writejson .loop.yml)" LOOP_STAGE=implement 'LOOP_PROTECTED_PATHS=docs/*')"
if [ "$r1$r2$r3$r4$r5$r6$r7$r8$r9" = "200200220" ]; then
  ok "protected paths: stage-scoped veto, reads pass, sed needs -i, set is overridable"
else no "protected paths" "got $r1$r2$r3$r4$r5$r6$r7$r8$r9 want 200200220"; fi

# 33) stage write scoping (CON-072): non-implement stages write run artifacts
#     and .loop/ only; implement writes the repo; interactive is unscoped.
s1="$(guard "$(writejson "$TMP/rd/findings.json")" LOOP_STAGE=review "LOOP_RUN_DIR=$TMP/rd")"
s2="$(guard "$(writejson src/x.py)" LOOP_STAGE=review "LOOP_RUN_DIR=$TMP/rd")"
s3="$(guard "$(writejson "$PWD/src/x.py")" LOOP_STAGE=review "LOOP_RUN_DIR=$TMP/rd")"
s4="$(guard "$(writejson .loop/memory.md)" LOOP_STAGE=review "LOOP_RUN_DIR=$TMP/rd")"
s5="$(guard "$(writejson src/x.py)" LOOP_STAGE=implement)"
s6="$(guard "$(writejson src/x.py)")"
if [ "$s1$s2$s3$s4$s5$s6" = "022000" ]; then
  ok "stage scoping: review writes run dir/.loop only; implement + interactive unscoped"
else no "stage scoping" "got $s1/$s2/$s3/$s4/$s5/$s6 want 0/2/2/0/0/0"; fi

# 34) the secret scan is closed over every write surface: MultiEdit edits[] and
#     NotebookEdit new_source are scanned; REMOVING a secret (old_string) is not
#     blocked by the secret it removes. (Keys assembled at runtime.)
akid2="AKIA""IOSFODNN7EXAMPLE"
ghp2="ghp_""abcdefghijklmnopqrstuv"
m1="$(guard "$(jq -nc --arg s "$akid2" '{tool_name:"MultiEdit", tool_input:{file_path:"a.txt", edits:[{old_string:"x",new_string:"clean"},{old_string:"y",new_string:("key="+$s)}]}}')")"
m2="$(guard "$(jq -nc --arg s "$ghp2" '{tool_name:"NotebookEdit", tool_input:{notebook_path:"n.ipynb", new_source:("t="+$s)}}')")"
m3="$(guard "$(jq -nc --arg s "$akid2" '{tool_name:"Edit", tool_input:{file_path:"a.txt", old_string:("key="+$s), new_string:"key=REMOVED"}}')")"
if [ "$m1" = "2" ] && [ "$m2" = "2" ] && [ "$m3" = "0" ]; then
  ok "secret scan covers MultiEdit/NotebookEdit; secret REMOVAL is not blocked"
else no "secret closure" "multi=$m1 nb=$m2 removal=$m3"; fi

# 35) .loop.yml secret_scan/secret_scanner are honored (they were documented
#     but ignored): scan off lets a key through; builtin works without tools.
c1="$(guard "$(writejson a.txt "key=$akid2")" LOOP_SECRET_SCAN=false)"
c2="$(guard "$(writejson a.txt "key=$akid2")" LOOP_SECRET_SCANNER=builtin)"
if [ "$c1" = "0" ] && [ "$c2" = "2" ]; then
  ok "secret_scan=false honored; scanner=builtin denies without external tools"
else no "secret config honor" "off=$c1 builtin=$c2"; fi

# 36) redaction (CON-090) is real end-to-end: a gate that echoes a token leaves
#     [REDACTED] — not the token — in the gate log, the report, and state.
printf 'gates:\n  test: "echo url=%s; exit 1"\n' "$ghp2" > "$TMP/leak.yml"
s="$(LOOP_CONFIG="$TMP/leak.yml" loop_status specs/000-example)"
rd="$(dirname "$(latest_state)")"
if [ "$s" = "partial" ] \
   && ! grep -rq "$ghp2" "$rd/gates" "$rd/report.md" "$rd/state.json" 2>/dev/null \
   && grep -q 'REDACTED' "$rd/gates/test.log" 2>/dev/null \
   && grep -q 'REDACTED' "$rd/report.md" 2>/dev/null; then
  ok "token echoed by a gate is redacted in log + report + state"
else no "redaction e2e" "status='$s' leak=$(grep -rl "$ghp2" "$rd" 2>/dev/null | paste -sd, -)"; fi
u="$(printf 'x %s y' "$ghp2" | { . loop/lib/common.sh; redact_stream; })"
case "$u" in *"$ghp2"*) no "redact_stream unit" "token survived" ;; *REDACTED*) ok "redact_stream scrubs builtin token shapes" ;; *) no "redact_stream unit" "no marker: $u" ;; esac

# 37) the protected-paths diff barrier (CON-045 backstop) red-gates a branch
#     that modified the guardrail chain, and passes a clean one.
mkdir -p "$TMP/pp/specs"
( cd "$TMP/pp" && git init -q . \
  && printf 'v1\n' > specs/constitution.md && printf 'code\n' > app.txt \
  && git add -A && git -c user.email=e@x -c user.name=n commit -qm base )
ppbase="$(git -C "$TMP/pp" rev-parse HEAD)"
printf 'tampered\n' >> "$TMP/pp/specs/constitution.md"
p1="$( ( unset STATE_FILE LOOP_GATE_LOG_DIR LOOP_PROTECTED_PATHS
        REPO_DIR="$TMP/pp" ADAPTERS_DIR="$PWD/adapters"
        . loop/lib/common.sh; . loop/lib/state.sh; . loop/lib/gates.sh
        gate_check_protected_paths "$ppbase" >/dev/null 2>&1; echo $? ) )"
git -C "$TMP/pp" checkout -- specs/constitution.md
p2="$( ( unset STATE_FILE LOOP_GATE_LOG_DIR LOOP_PROTECTED_PATHS
        REPO_DIR="$TMP/pp" ADAPTERS_DIR="$PWD/adapters"
        . loop/lib/common.sh; . loop/lib/state.sh; . loop/lib/gates.sh
        gate_check_protected_paths "$ppbase" >/dev/null 2>&1; echo $? ) )"
if [ "$p1" = "1" ] && [ "$p2" = "0" ]; then
  ok "protected-diff barrier: tampered branch red, clean branch green"
else no "protected-diff barrier" "tampered=$p1 clean=$p2"; fi

# 38) settings.json and the plugin hooks.json must wire the SAME PreToolUse
#     surface — matcher drift would silently unguard one install mode.
mset="$(jq -r '.hooks.PreToolUse[0].matcher' .claude/settings.json)"
mplug="$(jq -r '.hooks.PreToolUse[0].matcher' .claude/hooks/hooks.json)"
if [ "$mset" = "$mplug" ] && [ "$mset" = "Edit|MultiEdit|NotebookEdit|Write|Bash" ]; then
  ok "PreToolUse matcher identical in settings.json and hooks.json"
else no "matcher parity" "settings='$mset' plugin='$mplug'"; fi

# ---------------------------------------------------------------------------
# Informed humans, trust ledger, memory hygiene (CON-060/061/062, CON-090)
# ---------------------------------------------------------------------------

# 39) every gate outcome lands in the trust ledger, and the gate PROMPT is
#     preceded by the evidence being signed (a bare y/N is not sign-off).
rm -f "$TMP/trust.jsonl"
LOOP_RUNS_DIR="$TMP/runs" LOOP_MEMORY_FILE="$TMP/mem.md" LOOP_BACKLOG_FILE="$TMP/bk.md" \
LOOP_TRUST_FILE="$TMP/trust.jsonl" \
  bash loop/run.sh --dry-run --spec specs/000-example --yes >/dev/null 2>"$TMP/gates.err" || true
g_spec="$(jq -sr '[.[] | select(.gate=="spec" and .decision=="auto_approved")] | length' "$TMP/trust.jsonl" 2>/dev/null)"
g_pm="$(  jq -sr '[.[] | select(.gate=="premerge" and .decision=="auto_approved")] | length' "$TMP/trust.jsonl" 2>/dev/null)"
if [ "${g_spec:-0}" -ge 1 ] && [ "${g_pm:-0}" -ge 1 ] \
   && grep -q 'spec gate: approving CODE GENERATION' "$TMP/gates.err" \
   && grep -q 'pre-merge gate: approving a PR from this evidence' "$TMP/gates.err" \
   && grep -q 'traceability:' "$TMP/gates.err"; then
  ok "trust ledger records gate outcomes; gates show the evidence being signed"
else no "informed gates + ledger" "spec=$g_spec pm=$g_pm ctx=$(grep -c 'gate:' "$TMP/gates.err" 2>/dev/null)"; fi

# 40) autopass is OPT-IN and conservative: needs enabled+listed+risk<=ceiling+
#     human streak; declines reset it; autopasses never extend it.
ap() { # ap <cfg-json> <ledger-file> <gate> <risk> -> rc
  ( TRUST_FILE="$2"
    . loop/lib/common.sh; . loop/lib/config.sh; . loop/lib/memory.sh
    LOOP_CFG_JSON="$1"
    autopass_ok "$3" "$4" >/dev/null 2>&1; echo $? )
}
CFG_ON='{"human_gates_autopass":{"enabled":true,"gates":["spec"],"max_risk":"standard","min_streak":3}}'
CFG_OFF='{"human_gates_autopass":{"enabled":false,"gates":["spec"],"max_risk":"standard","min_streak":3}}'
printf '%s\n%s\n%s\n' '{"gate":"spec","decision":"approved"}' '{"gate":"spec","decision":"approved"}' '{"gate":"spec","decision":"approved"}' > "$TMP/led3.jsonl"
printf '%s\n%s\n%s\n%s\n' '{"gate":"spec","decision":"approved"}' '{"gate":"spec","decision":"approved"}' '{"gate":"spec","decision":"approved"}' '{"gate":"spec","decision":"declined"}' > "$TMP/led_dec.jsonl"
printf '%s\n%s\n%s\n%s\n%s\n' '{"gate":"spec","decision":"approved"}' '{"gate":"spec","decision":"approved"}' '{"gate":"spec","decision":"autopass"}' '{"gate":"spec","decision":"autopass"}' '{"gate":"spec","decision":"autopass"}' > "$TMP/led_ap.jsonl"
a1="$(ap "$CFG_ON" "$TMP/led3.jsonl" spec low)"          # all conditions met
a2="$(ap "$CFG_ON" "$TMP/led3.jsonl" spec sensitive)"    # risk above ceiling
a3="$(ap "$CFG_ON" "$TMP/led3.jsonl" premerge low)"      # gate not listed
a4="$(ap "$CFG_OFF" "$TMP/led3.jsonl" spec low)"         # not enabled
a5="$(ap "$CFG_ON" "$TMP/led_dec.jsonl" spec low)"       # decline resets streak
a6="$(ap "$CFG_ON" "$TMP/led_ap.jsonl" spec low)"        # autopasses don't count
if [ "$a1$a2$a3$a4$a5$a6" = "011111" ]; then
  ok "autopass: opt-in only, risk-capped, human-streak-fed, decline-reset"
else no "autopass policy" "got $a1$a2$a3$a4$a5$a6 want 011111"; fi

# 41) the backlog deduplicates: the same deferred finding carried by every run
#     must not pile up as identical lines.
rm -f "$TMP/bl.md"
( BACKLOG_FILE="$TMP/bl.md" MEMORY_ENABLED=true
  . loop/lib/common.sh; . loop/lib/memory.sh
  backlog_add "same deferred item"; backlog_add "same deferred item"; backlog_add "another item" )
n="$(grep -c '^- ' "$TMP/bl.md" 2>/dev/null)"
[ "$n" = "2" ] && ok "backlog deduplicates carried items" || no "backlog dedupe" "lines=$n want 2"

# 42) memory hygiene: digests are pruned to max_entries and redacted on write.
rm -f "$TMP/mm.md"
( MEMORY_FILE="$TMP/mm.md" MEMORY_ENABLED=true MEMORY_MAX_ENTRIES=3
  . loop/lib/common.sh; . loop/lib/memory.sh
  for i in 1 2 3 4; do printf 'digest body %s\n' "$i" | memory_append "r$i"; done
  printf 'leaked %s\n' "$ghp2" | memory_append "r5" )
n="$(grep -c '^## ' "$TMP/mm.md" 2>/dev/null)"
if [ "$n" = "3" ] && grep -q 'r5' "$TMP/mm.md" && ! grep -q '— r1$' "$TMP/mm.md" \
   && ! grep -q "$ghp2" "$TMP/mm.md" && grep -q 'REDACTED' "$TMP/mm.md"; then
  ok "memory pruned to max_entries and redacted on write"
else no "memory hygiene" "sections=$n r1=$(grep -c '— r1$' "$TMP/mm.md" 2>/dev/null) leak=$(grep -c "$ghp2" "$TMP/mm.md" 2>/dev/null)"; fi

echo
if [ "$fail" -eq 0 ]; then printf 'evals: \033[32m%d passed, 0 failed\033[0m\n' "$pass"
else printf 'evals: %d passed, \033[31m%d failed\033[0m\n' "$pass" "$fail"; fi
[ "$fail" -eq 0 ]
