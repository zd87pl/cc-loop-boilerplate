#!/usr/bin/env bash
# loop/lib/artifacts.sh — deterministic validation of stage artifacts (CON-026).
# Requires jq and common.sh. RUN_DIR must be set by the caller.
#
# A stage that "passed" while writing nothing — or writing prose where the
# controller expects a token or JSON — must fail CLOSED, not sail on. Every
# check here is model-free: existence, parseability, token whitelists, and the
# findings schema. The canonical findings shape ships as loop/findings.schema.json
# (documentation + optional external validation); the checks below are jq-native
# so nothing new is required on PATH.

# artifact_require <path> — file exists and contains non-whitespace content.
artifact_require() {
  local f="$1"
  [ -f "$f" ] && grep -q '[^[:space:]]' "$f" 2>/dev/null
}

# artifact_token <path> <allowed...> — the file must contain exactly one of the
# allowed tokens (surrounding whitespace tolerated). Echoes the token on match.
artifact_token() {
  local f="$1" tok t; shift
  [ -f "$f" ] || return 1
  tok="$(tr -d '[:space:]' < "$f" 2>/dev/null)"
  [ -n "$tok" ] || return 1
  for t in "$@"; do
    [ "$tok" = "$t" ] && { printf '%s' "$tok"; return 0; }
  done
  return 1
}

# artifact_json <path> — file parses as JSON.
artifact_json() { [ -f "$1" ] && jq -e . "$1" >/dev/null 2>&1; }

# findings_validate <path> — structural check against the canonical findings
# shape (loop/findings.schema.json): .findings is an array; every finding has a
# string id (unique), a string title, a severity from the closed enum; optional
# cwe must look like CWE-NNN; optional source names the emitting agent.
findings_validate() {
  local f="$1"
  artifact_json "$f" || return 1
  jq -e '
    (.findings | type == "array")
    and ([ .findings[]
           | select( (.id | type == "string")
                     and (.title | type == "string")
                     and ((.severity // "") | IN("critical","high","medium","low"))
                     and ((.cwe // "CWE-0") | test("^CWE-[0-9]+$"))
                     and ((.source // "reviewer") | IN("reviewer","security-auditor")) )
         ] | length) == (.findings | length)
    and ((.findings | map(.id) | unique | length) == (.findings | length))
  ' "$f" >/dev/null 2>&1
}

# findings_count <path> [min_severity] — number of findings at or above the
# given severity (default: low = all). This — never a model-written integer —
# is the review loop's control variable (CON-033). Prints nothing and returns 1
# when the file is missing or malformed, so callers fail closed.
findings_count() {
  local f="$1" min="${2:-low}"
  findings_validate "$f" || return 1
  jq -r --arg min "$min" '
    def rank: {"critical":4,"high":3,"medium":2,"low":1}[.] // 0;
    [ .findings[] | select((.severity | rank) >= ($min | rank)) ] | length
  ' "$f" 2>/dev/null
}

# findings_below <path> <min_severity> — markdown lines for findings BELOW the
# blocking threshold, for carrying into the backlog (CON-019/CON-035).
findings_below() {
  local f="$1" min="${2:-high}"
  findings_validate "$f" || return 1
  jq -r --arg min "$min" '
    def rank: {"critical":4,"high":3,"medium":2,"low":1}[.] // 0;
    .findings[] | select((.severity | rank) < ($min | rank))
    | "deferred [\(.severity)] \(.title)\(if .file then " (\(.file)\(if .line then ":\(.line)" else "" end))" else "" end) [\(.id)]"
  ' "$f" 2>/dev/null
}

# artifacts_validate <stage> — assert the stage's declared artifacts exist and
# parse. Prints one reason per problem to stderr; returns non-zero on any.
artifacts_validate() {
  local stage="$1" bad=0
  _av_fail() { err "artifact check ($stage): $*"; bad=1; }
  case "$stage" in
    spec)
      artifact_require "$RUN_DIR/spec.normalized.md" || _av_fail "spec.normalized.md missing/empty" ;;
    spec_review)
      artifact_token "$RUN_DIR/spec-review.verdict" READY CAVEATS NOT_READY >/dev/null \
        || _av_fail "spec-review.verdict is not exactly READY|CAVEATS|NOT_READY"
      artifact_token "$RUN_DIR/spec-review.riskclass" low standard sensitive >/dev/null \
        || _av_fail "spec-review.riskclass is not exactly low|standard|sensitive"
      artifact_require "$RUN_DIR/spec-review.md"   || _av_fail "spec-review.md missing/empty"
      artifact_json "$RUN_DIR/spec-review.json"    || _av_fail "spec-review.json missing/unparseable" ;;
    explore)
      artifact_require "$RUN_DIR/context-map.md"   || _av_fail "context-map.md missing/empty" ;;
    plan)
      artifact_require "$RUN_DIR/plan.md"          || _av_fail "plan.md missing/empty" ;;
    tasks)
      artifact_require "$RUN_DIR/tasks.md"         || _av_fail "tasks.md missing/empty" ;;
    review|fix)
      findings_validate "$RUN_DIR/findings.json" \
        || _av_fail "findings.json missing or does not match loop/findings.schema.json" ;;
    verify)
      artifact_token "$RUN_DIR/verify.verdict" PASS FAIL >/dev/null \
        || _av_fail "verify.verdict is not exactly PASS|FAIL"
      artifact_require "$RUN_DIR/traceability.md"  || _av_fail "traceability.md missing/empty"
      artifact_require "$RUN_DIR/walkthrough.md"   || _av_fail "walkthrough.md missing/empty" ;;
    *) : ;;  # implement's artifact is commits on the branch; nothing to check here
  esac
  return $bad
}
