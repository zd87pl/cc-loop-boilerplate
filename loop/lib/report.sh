#!/usr/bin/env bash
# loop/lib/report.sh — render the human-readable run report and the traceability
# matrix (CON-080/081). Requires common.sh, state.sh, jq. Expects RUN_DIR and
# STATE_FILE set by the caller.

report_tool_versions() {
  local c g j y
  c="$(${CLAUDE_BIN:-claude} --version 2>/dev/null | head -1)"
  g="$(git --version 2>/dev/null)"
  j="$(jq --version 2>/dev/null)"
  y="$(yq --version 2>/dev/null | head -1)"
  printf 'claude=%s; %s; jq=%s; yq=%s' "${c:-?}" "${g:-git?}" "${j:-?}" "${y:-?}"
}

# report_traceability <spec-file> <dry_run> -> markdown table to stdout.
# Rows are derived from the spec's REQ-NNN requirements so the matrix is always
# populated against the contract; the Code/Test columns are filled by the
# verifier in a real run (or marked as dry-run stubs).
report_traceability() {
  local spec="$1" dry="$2"
  printf '| Requirement | Acceptance evidence (spec) | Code | Test | Status |\n'
  printf '| --- | --- | --- | --- | --- |\n'
  if [ ! -f "$spec" ]; then
    printf '| _(spec file not found)_ |  |  |  | UNKNOWN |\n'
    return 0
  fi
  awk -F'|' '
    /^\| *REQ-[0-9]/ {
      id=$2; acc=$(NF-1);
      gsub(/^[ \t]+|[ \t]+$/,"",id); gsub(/^[ \t]+|[ \t]+$/,"",acc);
      print id "\t" acc
    }' "$spec" | while IFS="$(printf '\t')" read -r id acc; do
      if [ "$dry" = "true" ]; then
        printf '| %s | %s | _(dry run — not generated)_ | _(dry run — not generated)_ | TRACED (spec only) |\n' "$id" "$acc"
      else
        printf '| %s | %s | _pending verifier_ | _pending verifier_ | PENDING |\n' "$id" "$acc"
      fi
    done
}

# report_write_traceability <spec-file> <dry_run> — persist the matrix.
report_write_traceability() {
  report_traceability "$1" "$2" > "$RUN_DIR/traceability.md"
  ok "traceability matrix written: $RUN_DIR/traceability.md"
}

report_render() {
  local f="$RUN_DIR/report.md"
  {
    echo "# Spec-Driven Loop — Run Report"
    echo
    echo "- **Run id:** \`$(state_get '.run_id')\`"
    echo "- **Status:** **$(state_get '.status')**"
    echo "- **Dry run:** $(state_get '.dry_run')"
    echo "- **Created:** $(state_get '.created_at')"
    echo "- **Updated:** $(state_get '.updated_at')"
    [ "$(state_get '.halt_reason // ""')" != "" ] && echo "- **Halt reason:** $(state_get '.halt_reason')"
    echo
    echo "## Reproducibility header"
    echo
    echo "| Field | Value |"
    echo "| --- | --- |"
    echo "| Spec | \`$(state_get '.spec.path')\` |"
    echo "| Base branch | \`$(state_get '.git.base_branch')\` |"
    echo "| Feature branch | \`$(state_get '.git.branch')\` |"
    echo "| Worktree | \`$(state_get '.git.worktree // "-"')\` |"
    echo "| Base SHA | \`$(state_get '.git.base_sha // "-"')\` |"
    echo "| Head SHA | \`$(state_get '.git.head_sha // "-"')\` |"
    echo "| Config hash | \`$(state_get '.config.hash')\` |"
    echo "| Max iterations | $(state_get '.config.max_iterations') |"
    echo "| Cost ceiling (USD) | $(state_get '.config.cost_ceiling_usd') |"
    echo "| Tool versions | $(report_tool_versions) |"
    echo
    echo "## Models per stage"
    echo
    echo "| Stage | Model |"
    echo "| --- | --- |"
    state_get_raw '.models // {}' | jq -r 'to_entries[] | "| \(.key) | \(.value) |"'
    echo
    echo "## Stages"
    echo
    echo "| # | Stage | Owner | Gate | Status | Attempts |"
    echo "| --- | --- | --- | --- | --- | --- |"
    state_get_raw '.stages' | jq -r 'to_entries[] | "| \(.key+1) | \(.value.name) | \(.value.owner // "-") | \(.value.gate // "-") | \(.value.status) | \(.value.attempts // 0) |"'
    echo
    echo "## Quality gates (last result)"
    echo
    echo "| Verb | Status | Exit | Command |"
    echo "| --- | --- | --- | --- |"
    state_get_raw '.gates // {}' | jq -r 'to_entries[] | "| \(.key) | \(.value.status) | \(.value.code) | `\(.value.command)` |"'
    echo
    echo "## Cost & iterations"
    echo
    echo "- Iterations consumed: $(state_get '.iteration') / $(state_get '.config.max_iterations')"
    echo "- Spend: \$$(state_get '.cost.spent_usd // 0') / \$$(state_get '.config.cost_ceiling_usd') ceiling"
    echo "- Tokens: in=$(state_get '.cost.input_tokens // 0') out=$(state_get '.cost.output_tokens // 0')"
    echo
    echo "## Traceability matrix (SPEC/PRD/ADR ⇄ code ⇄ test)"
    echo
    if [ -f "$RUN_DIR/traceability.md" ]; then cat "$RUN_DIR/traceability.md"; else echo "_not generated_"; fi
    echo
    echo "## Open clarifications"
    echo
    local n; n="$(state_get '.clarifications | length')"
    if [ "${n:-0}" -eq 0 ]; then echo "_none_"; else
      state_get_raw '.clarifications' | jq -r '.[] | "- " + .'
    fi
    echo
    echo "## Data handling"
    echo
    echo "All spec/code processing is local. The only data sent off-machine is the"
    echo "content transmitted to the model API during stage calls. PII/secrets are"
    echo "kept out of this report and the event stream via the configured redaction"
    echo "patterns, and \`runs_dir\` is gitignored by default (CON-090..092)."
  } > "$f"
  ok "report written: $f"
}
