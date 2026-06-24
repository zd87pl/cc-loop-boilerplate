#!/usr/bin/env bash
# Ruby adapter. Detected by: Gemfile | *.gemspec
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

# Run a tool through bundler when a Gemfile is present and bundler is installed.
bx() {
  if [ -f Gemfile ] && have bundle; then run bundle exec "$@"
  else run "$@"; fi
}
tool_available() { # name reachable directly or via bundler
  have "$1" || { [ -f Gemfile ] && have bundle && bundle exec "$1" --version >/dev/null 2>&1; }
}

verb_fmt() {
  if tool_available rubocop; then bx rubocop -A
  else skip "rubocop not available"; fi
}

verb_lint() {
  if tool_available rubocop; then bx rubocop
  else skip "rubocop not available"; fi
}

verb_typecheck() {
  if tool_available srb; then bx srb tc
  else skip "no type checker (sorbet not configured)"; fi
}

verb_test() {
  if   tool_available rspec; then bx rspec
  elif [ -f Rakefile ];      then bx rake test
  else skip "no test runner (rspec or rake test)"; fi
}

verb_build() {
  local gs; gs="$(ls ./*.gemspec 2>/dev/null | head -n1 || true)"
  if [ -n "$gs" ] && have gem; then run gem build "$gs"
  else skip "no gemspec to build"; fi
}

verb_securityscan() {
  if   tool_available brakeman; then bx brakeman -q
  elif tool_available bundle-audit; then bx bundle-audit check --update
  else skip "no security scanner (brakeman or bundler-audit)"; fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
