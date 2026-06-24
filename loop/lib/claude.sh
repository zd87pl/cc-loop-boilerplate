#!/usr/bin/env bash
# loop/lib/claude.sh — wrap `claude -p` for one stage: invoke a stage skill, parse
# cost/usage from --output-format json, accrue it, and enforce the cost ceiling
# (CON-051). Requires common.sh, state.sh. The dry-run path never calls this.
#
# Verified flags (claude 2.1.x): -p, --output-format json, --model,
# --permission-mode, --allowedTools, --max-budget-usd. (No --max-turns exists in
# this CLI; iteration bounds are enforced by the orchestrator.)

CLAUDE_BIN="${CLAUDE_BIN:-claude}"

# claude_remaining_budget -> remaining USD (>= 0) under the cost ceiling.
claude_remaining_budget() {
  awk -v ceil="${COST_CEILING_USD:-5.00}" -v spent="$(cost_spent)" \
      'BEGIN{r=ceil-spent; if(r<0)r=0; printf "%.4f", r}'
}

# claude_stage <stage> <model> <perm-mode> <allowed-tools> <prompt>
# Echoes the model's text result on stdout; returns the CLI exit code.
claude_stage() {
  local stage="$1" model="$2" perm="$3" allowed="$4" prompt="$5"
  local remaining; remaining="$(claude_remaining_budget)"
  if ! awk -v r="$remaining" 'BEGIN{exit !(r>0)}'; then
    warn "cost ceiling reached before stage '$stage' — not calling the model"
    return 3
  fi

  local args=( -p --output-format json --model "$model"
               --permission-mode "$perm" --max-budget-usd "$remaining" )
  [ -n "$allowed" ] && args+=( --allowedTools "$allowed" )

  local errf out rc
  errf="$(mktemp "${TMPDIR:-/tmp}/loop.claude.XXXXXX")"
  # Pass the prompt on STDIN, never as a trailing positional: --allowedTools is a
  # variadic flag and would otherwise swallow the prompt as tool-rule arguments
  # (then the CLI errors "Input must be provided ... as a prompt arg").
  out="$(printf '%s' "$prompt" | "$CLAUDE_BIN" "${args[@]}" 2>"$errf")"; rc=$?

  if [ $rc -ne 0 ]; then
    warn "claude exited $rc for stage '$stage': $(head -c 400 "$errf")"
    rm -f "$errf"; printf '%s' "$out"; return $rc
  fi
  rm -f "$errf"

  # Defensive parse: tolerate missing fields across CLI versions.
  local cost itok otok text
  cost="$(printf '%s' "$out" | jq -r '.total_cost_usd // 0'        2>/dev/null || echo 0)"
  itok="$(printf '%s' "$out" | jq -r '.usage.input_tokens // 0'    2>/dev/null || echo 0)"
  otok="$(printf '%s' "$out" | jq -r '.usage.output_tokens // 0'   2>/dev/null || echo 0)"
  text="$(printf '%s' "$out" | jq -r 'if has("result") then .result elif has("text") then .text else "" end' 2>/dev/null)"
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || text="$out"   # fall back to raw only on non-JSON

  cost_add "$cost" "$itok" "$otok"
  printf '%s' "$text"
  return 0
}
