#!/usr/bin/env bash
# loop/lib/events.sh — append-only JSONL event stream (CON-080). Requires jq and
# common.sh. EVENTS_FILE must be set by the caller.

# event <stage> <result> [extra-json-object]
event() {
  local stage="$1" result="$2" extra="${3:-{\}}"
  jq -nc --arg ts "$(now_utc)" --arg stage "$stage" --arg result "$result" \
         --argjson extra "$extra" \
         '{ts:$ts, stage:$stage, result:$result} + $extra' >> "$EVENTS_FILE"
}

# event_cost <stage> — snapshot current cumulative cost into the stream.
event_cost() {
  local spent itok otok
  spent="$(state_get '.cost.spent_usd // 0')"
  itok="$(state_get '.cost.input_tokens // 0')"
  otok="$(state_get '.cost.output_tokens // 0')"
  event "$1" "cost" "$(jq -nc --argjson s "$spent" --argjson i "$itok" --argjson o "$otok" \
                        '{spent_usd:$s, input_tokens:$i, output_tokens:$o}')"
}
