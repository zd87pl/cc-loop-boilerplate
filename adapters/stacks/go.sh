#!/usr/bin/env bash
# Go adapter. Detected by: go.mod
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

require_go() { have go || { skip "go toolchain not installed"; return 1; }; }

# $LOOP_FMT_CHECK=1 -> verify formatting without rewriting (CON-038).
verb_fmt() {
  require_go || return 0
  if [ "${LOOP_FMT_CHECK:-0}" = "1" ]; then
    local unformatted; unformatted="$(gofmt -l . 2>/dev/null)"
    if [ -n "$unformatted" ]; then
      printf '    files need gofmt:\n%s\n' "$unformatted" >&2
      return 1
    fi
    note "gofmt: clean"
  else
    run gofmt -w .
  fi
}

verb_lint() {
  if have golangci-lint; then run golangci-lint run
  else skip "golangci-lint not installed (go vet runs under typecheck)"; fi
}

verb_typecheck() {
  require_go || return 0
  run go vet ./...
}

verb_test() {
  require_go || return 0
  run go test ./...
}

verb_build() {
  require_go || return 0
  run go build ./...
}

verb_securityscan() {
  if   have govulncheck; then run govulncheck ./...
  elif have gosec;       then run gosec ./...
  else skip "no security scanner (install govulncheck or gosec)"; fi
}

# Extended gates (agentic-code-quality alignment). Thresholds arrive via env:
#   LOOP_COVERAGE_MIN   minimum %-coverage (0 = measure only)
#   LOOP_COMPLEXITY_MAX maximum cyclomatic complexity per function
verb_coverage() {
  require_go || return 0
  local min="${LOOP_COVERAGE_MIN:-0}" pct
  run go test -coverprofile=coverage.out ./... || return $?
  pct="$(go tool cover -func=coverage.out 2>/dev/null | awk '/^total:/ {gsub(/%/,"",$NF); print $NF}')"
  [ -n "$pct" ] || { skip "could not compute coverage total"; return 0; }
  note "coverage: ${pct}% (minimum: ${min}%)"
  if [ "${min:-0}" -gt 0 ] 2>/dev/null; then
    coverage_compare "$pct" "$min" || { printf '    coverage %s%% is below the %s%% minimum\n' "$pct" "$min" >&2; return 1; }
  fi
}

verb_complexity() {
  local max="${LOOP_COMPLEXITY_MAX:-0}"
  [ "${max:-0}" -gt 0 ] 2>/dev/null || { skip "complexity gate off (set complexity_max in .loop.yml)"; return 0; }
  if have gocyclo; then run gocyclo -over "$max" .
  else skip "gocyclo not installed"; fi
}

verb_archlint() {
  if [ -f .go-arch-lint.yml ]; then
    if have go-arch-lint; then run go-arch-lint check
    else skip "go-arch-lint config present but tool not installed"; fi
  else
    skip "no architecture rules (.go-arch-lint.yml)"
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
