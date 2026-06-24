#!/usr/bin/env bash
# loop/lib/state.sh — the resumable run-state file + cost meter (CON-080/081).
# Requires jq and common.sh. STATE_FILE must be set by the caller.

state_write() {
  # Refuse to write empty/invalid output: a failed jq upstream must NOT destroy
  # the resumable state file (the atomic mv guards torn writes, not empty ones).
  local tmp="$STATE_FILE.tmp.$$" data
  data="$(cat)"
  if [ -z "$data" ] || ! printf '%s' "$data" | jq -e . >/dev/null 2>&1; then
    err "state_write: refusing to write empty/invalid state (mutation dropped)"
    return 1
  fi
  printf '%s\n' "$data" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

state_get()     { jq -r "$1" "$STATE_FILE"; }
state_get_raw() { jq -c "$1" "$STATE_FILE"; }

# state_set <jq-lhs-path> <value-as-json>
state_set() {
  jq --argjson v "$2" --arg now "$(now_utc)" "$1 = \$v | .updated_at = \$now" \
     "$STATE_FILE" | state_write
}
# state_set_str <jq-lhs-path> <string>
state_set_str() {
  jq --arg v "$2" --arg now "$(now_utc)" "$1 = \$v | .updated_at = \$now" \
     "$STATE_FILE" | state_write
}

# cost_add <usd> <input_tokens> <output_tokens>  (CON-080)
cost_add() {
  jq --argjson c "${1:-0}" --argjson i "${2:-0}" --argjson o "${3:-0}" --arg now "$(now_utc)" '
      .cost.spent_usd     = ((.cost.spent_usd // 0) + $c)
    | .cost.input_tokens  = ((.cost.input_tokens // 0) + $i)
    | .cost.output_tokens = ((.cost.output_tokens // 0) + $o)
    | .updated_at = $now' "$STATE_FILE" | state_write
}
cost_spent() { state_get '.cost.spent_usd // 0'; }

# stage_update <name> <field> <value-as-json>
stage_update() {
  jq --arg n "$1" --argjson v "$3" --arg now "$(now_utc)" \
     '(.stages[] | select(.name==$n) | .'"$2"') = $v | .updated_at = $now' \
     "$STATE_FILE" | state_write
}
# stage_update_str <name> <field> <string>
stage_update_str() {
  jq --arg n "$1" --arg v "$3" --arg now "$(now_utc)" \
     '(.stages[] | select(.name==$n) | .'"$2"') = $v | .updated_at = $now' \
     "$STATE_FILE" | state_write
}
stage_status() { state_get '(.stages[] | select(.name=="'"$1"'") | .status) // "pending"'; }

# gate_update <verb> <status> <code> <command>
gate_update() {
  jq --arg verb "$1" --arg s "$2" --argjson code "${3:-0}" --arg cmd "${4:-}" --arg now "$(now_utc)" '
      .gates[$verb] = {status:$s, code:$code, command:$cmd, updated_at:$now}
    | .updated_at = $now' "$STATE_FILE" | state_write
}

# clarification_add <text>
clarification_add() {
  jq --arg t "$1" --arg now "$(now_utc)" \
     '.clarifications += [$t] | .updated_at = $now' "$STATE_FILE" | state_write
}

state_validate() { # optional schema check when a validator is available
  local schema="${1:-}"
  [ -n "$schema" ] && [ -f "$schema" ] || return 0
  if have check-jsonschema; then
    check-jsonschema --schemafile "$schema" "$STATE_FILE" >/dev/null 2>&1 \
      && ok "state validates against schema" || warn "state did not validate (non-fatal)"
  fi
  return 0
}
