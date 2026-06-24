#!/usr/bin/env bash
# scripts/spec-lint.sh — deterministic, model-free spec checks. This is the cheap
# gate that runs BEFORE the model-based /spec-review (SPEC-003): it catches the
# mechanical problems (structure, ids, coverage, placeholders) so the model is
# reserved for judgment. Exit 0 = clean; non-zero = errors found.
#
# Usage: spec-lint.sh <spec.md> [--strict]   (--strict also fails on warnings)
set -uo pipefail

SPEC="${1:-}"; STRICT="${2:-}"
[ -n "$SPEC" ] && [ -f "$SPEC" ] || { echo "usage: spec-lint.sh <spec.md> [--strict]" >&2; exit 64; }

errors=0; warns=0
err()  { printf '  \033[31m✗\033[0m %s\n' "$1" >&2; errors=$((errors+1)); }
warn() { printf '  \033[33m!\033[0m %s\n' "$1" >&2; warns=$((warns+1)); }

# 1) metadata: Spec ID + a valid Status
grep -qiE '^[|][[:space:]]*Spec ID' "$SPEC" || err "missing 'Spec ID' in the metadata table"
status="$(grep -iE '^[|][[:space:]]*Status' "$SPEC" | head -1 \
          | sed -E 's/.*Status[^|]*[|][[:space:]]*//; s/[[:space:]]*[|].*//' \
          | tr '[:upper:]' '[:lower:]')"
case "$status" in
  draft|in-review|approved) : ;;
  "") err "missing 'Status' in the metadata table" ;;
  *)  err "invalid Status '$status' (expected: draft | in-review | approved)" ;;
esac

# 2) requirements present and uniquely identified
req_rows="$(grep -E '^[|][[:space:]]*REQ-[0-9]+' "$SPEC" || true)"
req_ids="$(printf '%s\n' "$req_rows" | grep -oE 'REQ-[0-9]+' || true)"
nreq="$(printf '%s\n' "$req_ids" | grep -c 'REQ-' || true)"
[ "${nreq:-0}" -ge 1 ] || err "no REQ-NNN requirement rows found"
dups="$(printf '%s\n' "$req_ids" | sort | uniq -d | tr '\n' ' ')"
[ -z "${dups// /}" ] || err "duplicate REQ ids: $dups"

# 3) every requirement row carries a non-empty acceptance check (last column)
while IFS= read -r row; do
  [ -n "$row" ] || continue
  id="$(printf '%s' "$row" | grep -oE 'REQ-[0-9]+' | head -1)"
  last="$(printf '%s' "$row" | awk -F'|' '{c=$(NF-1); gsub(/^[ \t]+|[ \t]+$/,"",c); print c}')"
  case "$last" in
    ""|"-"|"TODO"|"TBD"|"<how proven>") err "$id has no acceptance check (last column empty/placeholder)" ;;
  esac
done <<< "$req_rows"

# 4) bidirectional REQ <-> AC coverage (warnings, not hard errors)
ac_covers="$(grep -E '^[|][[:space:]]*AC-' "$SPEC" | grep -oE 'REQ-[0-9]+' | sort -u || true)"
if [ -n "${ac_covers// /}" ]; then
  for id in $(printf '%s\n' "$req_ids" | sort -u); do
    printf '%s\n' "$ac_covers" | grep -qx "$id" || warn "$id is not covered by any acceptance criterion"
  done
  for ref in $ac_covers; do
    printf '%s\n' "$req_ids" | grep -qx "$ref" || warn "an acceptance criterion references $ref, which is not a defined requirement"
  done
else
  warn "no acceptance-criteria (AC-) rows found to cross-check coverage"
fi

# 5) no unresolved placeholder markers (line-leading, so prose that merely
#    mentions "TODO" or a spec about TODOs is not falsely flagged)
grep -qE '^[[:space:]]*([-*>][[:space:]]*)?(TODO|TBD|FIXME|XXX)\b' "$SPEC" \
  && err "unresolved TODO/TBD/FIXME/XXX marker present"

# 6) an approved spec must have no open clarification MARKER (a bullet/line-leading
#    'NEEDS CLARIFICATION:'); inline mentions in prose/tables do not count
if [ "$status" = "approved" ] && grep -qE '^[[:space:]]*[-*]?[[:space:]]*NEEDS CLARIFICATION:' "$SPEC"; then
  err "Status is 'approved' but an unresolved 'NEEDS CLARIFICATION:' marker remains"
fi

# verdict
if [ "$errors" -gt 0 ]; then
  printf '%s: \033[31m%d error(s)\033[0m, %d warning(s)\n' "$SPEC" "$errors" "$warns" >&2
  exit 1
fi
if [ "$STRICT" = "--strict" ] && [ "$warns" -gt 0 ]; then
  printf '%s: 0 errors, \033[33m%d warning(s)\033[0m (strict)\n' "$SPEC" "$warns" >&2
  exit 1
fi
printf '%s: \033[32mclean\033[0m (%d warning(s))\n' "$SPEC" "$warns"
exit 0
