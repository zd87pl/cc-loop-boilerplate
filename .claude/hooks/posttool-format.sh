#!/usr/bin/env bash
# PostToolUse(Edit|Write) — best-effort format the EDITED FILE in place using
# whatever formatter is on PATH. Never blocks: always exits 0. Only touches code
# files (not markdown/yaml/json) to avoid noisy reformatting.
set -uo pipefail
input="$(cat)"

file=""
command -v jq >/dev/null 2>&1 && file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$file" ] && [ -f "$file" ] || exit 0

h() { command -v "$1" >/dev/null 2>&1; }

case "$file" in
  *.py)
    if h ruff; then ruff format "$file" >/dev/null 2>&1
    elif h black; then black -q "$file" >/dev/null 2>&1; fi ;;
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
    if [ -x node_modules/.bin/prettier ]; then node_modules/.bin/prettier --write "$file" >/dev/null 2>&1
    elif h prettier; then prettier --write "$file" >/dev/null 2>&1; fi ;;
  *.go) h gofmt   && gofmt -w "$file" >/dev/null 2>&1 ;;
  *.rs) h rustfmt && rustfmt "$file" >/dev/null 2>&1 ;;
  *.rb) h rubocop && rubocop -A "$file" >/dev/null 2>&1 ;;
  *.cs) h dotnet  && dotnet format --include "$file" >/dev/null 2>&1 ;;
esac

exit 0
