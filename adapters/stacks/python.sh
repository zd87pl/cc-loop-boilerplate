#!/usr/bin/env bash
# Python adapter. Prefers ruff, then classic tools, then skips.
# Detected by: pyproject.toml | setup.py | setup.cfg | requirements.txt
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

verb_fmt() {
  if   have ruff;  then run ruff format .
  elif have black; then run black .
  else skip "no formatter (install ruff or black)"; fi
}

verb_lint() {
  if   have ruff;   then run ruff check .
  elif have flake8; then run flake8
  else skip "no linter (install ruff or flake8)"; fi
}

verb_typecheck() {
  if   have mypy;    then run mypy .
  elif have pyright; then run pyright
  else skip "no type checker (install mypy or pyright)"; fi
}

verb_test() {
  if   have pytest; then run pytest -q
  elif have python3; then run python3 -m unittest discover -q
  elif have python;  then run python -m unittest discover -q
  else skip "no test runner (install pytest, or use unittest)"; fi
}

verb_build() {
  if [ -f pyproject.toml ] || [ -f setup.py ]; then
    if python3 -c "import build" 2>/dev/null; then run python3 -m build
    else skip "python 'build' module not installed (pip install build)"; fi
  else
    skip "no pyproject.toml/setup.py to build"
  fi
}

verb_securityscan() {
  if   have bandit;   then run bandit -q -r . -x ./tests,./test
  elif have pip-audit; then run pip-audit
  else skip "no security scanner (install bandit or pip-audit)"; fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
