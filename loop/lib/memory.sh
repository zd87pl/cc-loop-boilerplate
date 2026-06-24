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
memory_append() {
  memory_enabled || return 0
  [ -n "${MEMORY_FILE:-}" ] || return 0
  mkdir -p "$(dirname "$MEMORY_FILE")" 2>/dev/null || return 0
  { printf '\n## %s — %s\n' "$(now_utc)" "${1:-run}"; cat; } >> "$MEMORY_FILE" 2>/dev/null || true
}

# backlog_add <item>  — append one deferred item to the persistent backlog.
backlog_add() {
  memory_enabled || return 0
  [ -n "${BACKLOG_FILE:-}" ] || return 0
  mkdir -p "$(dirname "$BACKLOG_FILE")" 2>/dev/null || return 0
  printf -- '- [%s] %s\n' "$(now_utc)" "$1" >> "$BACKLOG_FILE" 2>/dev/null || true
}

backlog_count() {
  if [ -f "${BACKLOG_FILE:-/nonexistent}" ]; then grep -c '^- ' "$BACKLOG_FILE" 2>/dev/null || echo 0
  else echo 0; fi
}
