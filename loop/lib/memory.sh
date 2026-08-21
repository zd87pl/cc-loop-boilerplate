#!/usr/bin/env bash
# loop/lib/memory.sh — cross-run memory + carried-forward backlog ("the model
# forgets everything between runs, so the memory has to be on disk"). Requires
# common.sh. Expects MEMORY_ENABLED, MEMORY_FILE, BACKLOG_FILE in the env.
#
# Memory holds a small DIGEST per run (not transcripts), so growth is bounded and
# secrets/PII stay out (CON-090..092). Both files live under .loop/ (gitignored)
# and survive `make clean` (only `make clean-all` removes them).

memory_enabled() { [ "${MEMORY_ENABLED:-true}" = "true" ]; }

# memory_load — announce the loaded memory (the path is handed to stages as
# context via the prompt; stages read it themselves).
memory_load() {
  memory_enabled || return 0
  [ -f "${MEMORY_FILE:-}" ] || { info "no cross-run memory yet (${MEMORY_FILE:-unset})"; return 0; }
  info "loaded cross-run memory: $MEMORY_FILE ($(wc -l < "$MEMORY_FILE" | tr -d ' ') lines)"
}

# memory_append <label>  — body read from stdin; appended under a dated header.
# Hygiene on the way in: the body is redacted (CON-090 — memory is fed back
# into future prompts) and the file is pruned to the newest max_entries digests
# so growth stays bounded instead of "bounded in spirit".
memory_append() {
  memory_enabled || return 0
  [ -n "${MEMORY_FILE:-}" ] || return 0
  mkdir -p "$(dirname "$MEMORY_FILE")" 2>/dev/null || return 0
  { printf '\n## %s — %s\n' "$(now_utc)" "${1:-run}"; redact_stream; } >> "$MEMORY_FILE" 2>/dev/null || true
  memory_prune
}

# memory_prune — keep only the newest MEMORY_MAX_ENTRIES '## ' sections.
memory_prune() {
  local max="${MEMORY_MAX_ENTRIES:-20}" f="${MEMORY_FILE:-}" n
  [ -n "$f" ] && [ -f "$f" ] || return 0
  case "$max" in ''|*[!0-9]*) return 0 ;; esac
  [ "$max" -gt 0 ] || return 0
  n="$(grep -c '^## ' "$f" 2>/dev/null)" || n=0
  [ "$n" -gt "$max" ] || return 0
  awk -v skip="$((n - max))" '/^## /{c++} c>skip' "$f" > "$f.tmp" 2>/dev/null \
    && mv "$f.tmp" "$f" 2>/dev/null || rm -f "$f.tmp" 2>/dev/null || true
}

# backlog_add <item>  — append one deferred item to the persistent backlog.
# Deduplicated on the item text: the same finding deferred by every run used to
# pile up as N identical lines, which buried the backlog it was meant to keep.
backlog_add() {
  memory_enabled || return 0
  [ -n "${BACKLOG_FILE:-}" ] || return 0
  mkdir -p "$(dirname "$BACKLOG_FILE")" 2>/dev/null || return 0
  [ -f "$BACKLOG_FILE" ] && grep -qF -- "] $1" "$BACKLOG_FILE" 2>/dev/null && return 0
  printf -- '- [%s] %s\n' "$(now_utc)" "$1" >> "$BACKLOG_FILE" 2>/dev/null || true
}

backlog_count() {
  if [ -f "${BACKLOG_FILE:-/nonexistent}" ]; then grep -c '^- ' "$BACKLOG_FILE" 2>/dev/null || echo 0
  else echo 0; fi
}

# ---------------------------------------------------------------------------
# Trust ledger + opt-in autopass (CON-062). Every human-gate outcome is
# recorded durably in TRUST_FILE (.loop/trust.jsonl — survives `make clean`,
# CON-081); the OPT-IN autopass policy may skip a prompt only on the strength
# of consecutive recorded HUMAN approvals.
# ---------------------------------------------------------------------------

# trust_record <gate> <decision> — decisions: approved | declined | autopass |
# auto_approved (dry-run/--yes) | no_tty. Context comes from the run env.
trust_record() {
  [ -n "${TRUST_FILE:-}" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  mkdir -p "$(dirname "$TRUST_FILE")" 2>/dev/null || return 0
  jq -nc --arg ts "$(now_utc)" --arg g "$1" --arg d "$2" \
         --arg run "${RUN_ID:-}" --arg spec "${SPEC_ID:-}" \
         --arg risk "${PROFILE:-${RISK:-standard}}" --arg v "${VERDICT:-}" \
         --argjson dry "${DRY_RUN:-false}" \
         '{ts:$ts, gate:$g, decision:$d, run_id:$run, spec_id:$spec,
           risk:$risk, readiness:$v, dry_run:$dry}' \
    >> "$TRUST_FILE" 2>/dev/null || true
}

# trust_streak <gate> — consecutive trailing HUMAN approvals for this gate.
# Only real human decisions count: approved extends, declined resets;
# autopass/auto_approved/no_tty entries are neutral (skipped) — delegation
# must never feed on itself.
trust_streak() {
  [ -f "${TRUST_FILE:-/nonexistent}" ] || { echo 0; return 0; }
  jq -s --arg g "$1" '
      [ .[] | select(.gate==$g and (.decision=="approved" or .decision=="declined")) ]
      | reverse | map(.decision)
      | (index("declined") // length)' "$TRUST_FILE" 2>/dev/null || echo 0
}

risk_rank() { case "$1" in low) echo 0 ;; sensitive) echo 2 ;; *) echo 1 ;; esac; }

# autopass_ok <gate> <risk> — true only when EVERY condition of the opt-in
# policy holds (CON-062): enabled, gate listed, run risk within max_risk, and
# a sufficient human-approval streak on record.
autopass_ok() {
  type cfg >/dev/null 2>&1 || return 1
  local gate="$1" risk="${2:-standard}"
  [ "$(cfg_bool '.human_gates_autopass.enabled' false)" = "true" ] || return 1
  case " $(cfg_list '.human_gates_autopass.gates' | tr '\n' ' ') " in
    *" $gate "*) : ;; *) return 1 ;;
  esac
  [ "$(risk_rank "$risk")" -le "$(risk_rank "$(cfg '.human_gates_autopass.max_risk' 'low')")" ] || return 1
  local need; need="$(cfg '.human_gates_autopass.min_streak' '3')"
  case "$need" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(trust_streak "$gate")" -ge "$need" ]
}
