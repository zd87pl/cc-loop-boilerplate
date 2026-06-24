#!/usr/bin/env bash
# PostToolUse(Edit|Write) — best-effort format the tree via the stack adapters.
# All language/stack knowledge stays in adapters/ (the `fmt` verb); none lives
# here. Never blocks: always exits 0. Disable with LOOP_POSTTOOL_FORMAT=0.
#
# Note: formatters are idempotent, so on an already-formatted tree this only
# changes the file you just edited. On large or unformatted repos you may prefer
# to disable this and rely on `make fmt` / the CI format check instead.
set -uo pipefail
cat >/dev/null   # consume the hook's stdin payload

[ "${LOOP_POSTTOOL_FORMAT:-1}" = "0" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
ADAPTERS="${CLAUDE_PLUGIN_ROOT:-$ROOT}/adapters"
[ -d "$ADAPTERS" ] || ADAPTERS="$ROOT/adapters"
[ -d "$ADAPTERS" ] || exit 0

for s in $(bash "$ADAPTERS/detect.sh" "$ROOT" 2>/dev/null); do
  [ -f "$ADAPTERS/stacks/$s.sh" ] || continue
  ( cd "$ROOT" && bash "$ADAPTERS/stacks/$s.sh" fmt ) >/dev/null 2>&1 || true
done

exit 0
