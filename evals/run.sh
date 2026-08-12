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
    bash loop/run.sh --dry-run --spec "$1" --yes >/dev/null 2>&1 || true
  local sf; sf="$(ls -1dt "$TMP"/runs/run-* 2>/dev/null | head -1)/state.json"
  jq -r '.status // "MISSING"' "$sf" 2>/dev/null || echo "MISSING"
}
# Same, but echo "<status> <exit-code>" so cases can assert the CON-082 mapping.
loop_status_rc() {
  local rc
  LOOP_RUNS_DIR="$TMP/runs" LOOP_MEMORY_FILE="$TMP/mem.md" LOOP_BACKLOG_FILE="$TMP/bk.md" \
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

# 7e) rm with -fr flag order is still vetoed
rc="$(hook_exit pretool-guard.sh '{"tool_name":"Bash","tool_input":{"command":"rm -fr /tmp/x"}}')"
[ "$rc" = "2" ] && ok "rm -fr vetoed (exit 2)" || no "rm -fr veto" "exit=$rc"

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

echo
if [ "$fail" -eq 0 ]; then printf 'evals: \033[32m%d passed, 0 failed\033[0m\n' "$pass"
else printf 'evals: %d passed, \033[31m%d failed\033[0m\n' "$pass" "$fail"; fi
[ "$fail" -eq 0 ]
