#!/usr/bin/env bash
# Python adapter. Prefers ruff, then classic tools, then skips.
# Detected by: pyproject.toml | setup.py | setup.cfg | requirements.txt
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

# $LOOP_FMT_CHECK=1 -> verify formatting without rewriting (the judged gate
# suite must not mutate the tree — CON-038); otherwise format in place.
verb_fmt() {
  if [ "${LOOP_FMT_CHECK:-0}" = "1" ]; then
    if   have ruff;  then run ruff format --check .
    elif have black; then run black --check .
    else skip "no formatter (install ruff or black)"; fi
  else
    if   have ruff;  then run ruff format .
    elif have black; then run black .
    else skip "no formatter (install ruff or black)"; fi
  fi
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

# Extended gates (agentic-code-quality alignment). Thresholds arrive via env:
#   LOOP_COVERAGE_MIN   minimum %-coverage (0 = measure only)
#   LOOP_COMPLEXITY_MAX maximum cyclomatic complexity per function
verb_coverage() {
  local min="${LOOP_COVERAGE_MIN:-0}"
  if have pytest && python3 -c "import pytest_cov" 2>/dev/null; then
    if [ "${min:-0}" -gt 0 ] 2>/dev/null; then run pytest -q --cov=. --cov-fail-under="$min"
    else run pytest -q --cov=.; fi
  elif have coverage; then
    run coverage run -m pytest -q || return $?
    if [ "${min:-0}" -gt 0 ] 2>/dev/null; then run coverage report --fail-under="$min"
    else run coverage report; fi
  else skip "no coverage tool (install pytest-cov or coverage)"; fi
}

verb_complexity() {
  local max="${LOOP_COMPLEXITY_MAX:-0}"
  [ "${max:-0}" -gt 0 ] 2>/dev/null || { skip "complexity gate off (set complexity_max in .loop.yml)"; return 0; }
  if   have xenon;  then run xenon --max-absolute "$(complexity_grade "$max")" .
  elif have lizard; then run lizard -C "$max" -i 0 .
  else skip "no complexity tool (install xenon or lizard)"; fi
}

verb_archlint() {
  # Architecture/import-boundary rules — only meaningful when the repo declares
  # them (import-linter config); otherwise skip quietly.
  if [ -f .importlinter ] || { [ -f pyproject.toml ] && grep -q '\[tool\.importlinter\]' pyproject.toml 2>/dev/null; }; then
    if have lint-imports; then run lint-imports
    else skip "import-linter config present but lint-imports not installed"; fi
  else
    skip "no architecture rules (.importlinter / [tool.importlinter])"
  fi
}

verb_mutation() {
  if have mutmut; then run mutmut run
  else skip "no mutation tool (pip install mutmut)"; fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
