#!/usr/bin/env bash
# scripts/uninstall.sh — print how to remove the plugin and clean local runtime.
# This script does NOT modify global state.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "== spec-loop uninstall =="
cat <<'MSG'

To remove the plugin, run INSIDE Claude Code:

    /plugin uninstall spec-loop@cc-loop
    /plugin marketplace remove cc-loop

The install script's only local footprint was making bundled scripts
executable; nothing global was changed.
MSG

if [ -d .loop ]; then
  echo
  echo "Local run artifacts exist at .loop/ (gitignored)."
  echo "Remove them with:  rm -rf .loop    (or: make clean)"
fi
