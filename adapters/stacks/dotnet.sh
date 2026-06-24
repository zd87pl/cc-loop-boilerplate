#!/usr/bin/env bash
# .NET adapter. Detected by: *.sln | *.csproj | *.fsproj | *.vbproj
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

require_dotnet() { have dotnet || { skip "dotnet SDK not installed"; return 1; }; }

verb_fmt() {
  require_dotnet || return 0
  run dotnet format
}

verb_lint() {
  require_dotnet || return 0
  # `dotnet format` in verify mode acts as a style/whitespace lint.
  run dotnet format --verify-no-changes --severity warn
}

verb_typecheck() {
  note "type checking happens during build"
  verb_build
}

verb_test() {
  require_dotnet || return 0
  run dotnet test
}

verb_build() {
  require_dotnet || return 0
  run dotnet build
}

verb_securityscan() {
  require_dotnet || return 0
  # `dotnet list package --vulnerable` always exits 0, so fail the gate manually
  # if it reports vulnerable packages.
  local out
  out="$(run dotnet list package --vulnerable --include-transitive 2>&1)" || true
  printf '%s\n' "$out" >&2
  if printf '%s' "$out" | grep -qi 'has the following vulnerable'; then
    note "vulnerable packages detected"
    return 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
