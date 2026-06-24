#!/usr/bin/env bash
# Node.js / TypeScript adapter. Prefers package.json scripts, then local/global
# tools, then skips. Detected by: package.json
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

# True if package.json defines the named npm script.
npm_script() {
  [ -f package.json ] || return 1
  node -e "process.exit((((require('./package.json').scripts)||{})['$1'])?0:1)" 2>/dev/null
}

# Pick the package manager by lockfile, falling back to npm.
pm() {
  if   [ -f pnpm-lock.yaml ] && have pnpm; then echo pnpm
  elif [ -f yarn.lock ]      && have yarn; then echo yarn
  else echo npm; fi
}

# Prefer a project-local binary in node_modules/.bin over a global one.
node_have() { [ -x "node_modules/.bin/$1" ] || have "$1"; }
node_run() {
  local b="$1"; shift
  if [ -x "node_modules/.bin/$b" ]; then run "node_modules/.bin/$b" "$@"
  else run "$b" "$@"; fi
}

verb_fmt() {
  if   npm_script format; then run "$(pm)" run format
  elif node_have prettier; then node_run prettier --write .
  else skip "no formatter (add a package.json 'format' script or prettier)"; fi
}

verb_lint() {
  if   npm_script lint; then run "$(pm)" run lint
  elif node_have eslint; then node_run eslint .
  else skip "no linter (add a 'lint' script or eslint)"; fi
}

verb_typecheck() {
  if   npm_script typecheck; then run "$(pm)" run typecheck
  elif [ -f tsconfig.json ] && node_have tsc; then node_run tsc --noEmit
  else skip "no typecheck (no tsconfig/tsc or 'typecheck' script)"; fi
}

verb_test() {
  if npm_script test; then run "$(pm)" test
  else skip "no 'test' script in package.json"; fi
}

verb_build() {
  if npm_script build; then run "$(pm)" run build
  else skip "no 'build' script in package.json"; fi
}

verb_securityscan() {
  # npm audit is built in. Requires a lockfile and (usually) network access.
  [ -f package-lock.json ] || [ -f pnpm-lock.yaml ] || [ -f yarn.lock ] || {
    skip "no lockfile; skipping dependency audit"; return 0; }
  case "$(pm)" in
    pnpm) run pnpm audit --audit-level=high ;;
    yarn) run yarn npm audit --severity high ;;
    npm)  run npm audit --audit-level=high ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
