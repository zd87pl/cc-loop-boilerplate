#!/usr/bin/env bash
# loop/lib/config.sh — load .loop.yml into a JSON blob and expose typed getters.
# Flavor-agnostic across mikefarah/yq (Go) and kislyuk/yq (Python). Requires jq.
# Source common.sh first.

# Convert a YAML file to JSON on stdout, supporting both yq flavors.
yaml_to_json() {
  local f="$1"
  [ -f "$f" ] || { printf '{}'; return 0; }
  if   yq -o=json '.' "$f" 2>/dev/null; then return 0   # mikefarah/yq (Go)
  elif yq -c '.'      "$f" 2>/dev/null; then return 0   # kislyuk/yq (Python)
  elif yq '.'         "$f" 2>/dev/null; then return 0
  else printf '{}'; fi
}

config_load() {
  LOOP_CONFIG_FILE="${1:-$PWD/.loop.yml}"
  if [ -f "$LOOP_CONFIG_FILE" ]; then
    LOOP_CFG_JSON="$(yaml_to_json "$LOOP_CONFIG_FILE")"
  else
    warn ".loop.yml not found at $LOOP_CONFIG_FILE — using built-in defaults"
    LOOP_CFG_JSON="{}"
  fi
  printf '%s' "$LOOP_CFG_JSON" | jq -e . >/dev/null 2>&1 \
    || die "could not parse $LOOP_CONFIG_FILE as YAML/JSON"
  export LOOP_CFG_JSON LOOP_CONFIG_FILE
}

# cfg <jq-filter> [default] -> scalar (default if absent/null/empty)
cfg() {
  local filter="$1" def="${2:-}" v
  v="$(printf '%s' "$LOOP_CFG_JSON" | jq -r "($filter) // empty" 2>/dev/null)"
  if [ -n "$v" ] && [ "$v" != "null" ]; then printf '%s' "$v"; else printf '%s' "$def"; fi
}

# cfg_list <jq-filter> -> newline-separated items (empty if absent)
cfg_list() {
  printf '%s' "$LOOP_CFG_JSON" | jq -r "(${1}) // [] | .[]" 2>/dev/null
}

# cfg_bool <jq-filter> <default> -> "true" | "false"
cfg_bool() {
  case "$(cfg "$1" "$2")" in true|1|yes|on) echo true ;; *) echo false ;; esac
}

# config_hash -> short, stable hash of the normalized config (reproducibility).
config_hash() {
  printf '%s' "$LOOP_CFG_JSON" \
    | { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null || cksum; } \
    | awk '{print $1}' | cut -c1-16
}
