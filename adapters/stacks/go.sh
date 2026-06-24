#!/usr/bin/env bash
# Go adapter. Detected by: go.mod
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

require_go() { have go || { skip "go toolchain not installed"; return 1; }; }

verb_fmt() {
  require_go || return 0
  run gofmt -w .
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

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
