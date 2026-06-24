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
# echo the final run status.
loop_status() {
  LOOP_RUNS_DIR="$TMP/runs" LOOP_MEMORY_FILE="$TMP/mem.md" LOOP_BACKLOG_FILE="$TMP/bk.md" \
    bash loop/run.sh --dry-run --spec "$1" --yes >/dev/null 2>&1 || true
  local sf; sf="$(ls -1dt "$TMP"/runs/run-* 2>/dev/null | head -1)/state.json"
  jq -r '.status // "MISSING"' "$sf" 2>/dev/null || echo "MISSING"
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

# 8) protected-branch guard: main refused, a feature branch allowed
if ( . loop/lib/common.sh; . loop/lib/git.sh; PROTECTED_BRANCHES="main master"; git_is_protected main && ! git_is_protected loop/x ); then
  ok "protected-branch guard (main refused, feature allowed)"
else no "protected branch" "guard incorrect"; fi

# 9) a real stack gate executes and passes (not skipped)
if ( cd examples/duration-py && bash ../../adapters/stacks/python.sh test ) >/dev/null 2>&1; then
  ok "real python gate passes"
else no "real gate" "example tests failed"; fi

echo
if [ "$fail" -eq 0 ]; then printf 'evals: \033[32m%d passed, 0 failed\033[0m\n' "$pass"
else printf 'evals: %d passed, \033[31m%d failed\033[0m\n' "$pass" "$fail"; fi
[ "$fail" -eq 0 ]
