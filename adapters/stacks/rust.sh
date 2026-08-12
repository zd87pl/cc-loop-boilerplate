#!/usr/bin/env bash
# Rust adapter. Detected by: Cargo.toml
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

require_cargo() { have cargo || { skip "cargo not installed"; return 1; }; }

verb_fmt() {
  require_cargo || return 0
  run cargo fmt --all
}

verb_lint() {
  require_cargo || return 0
  if cargo clippy --version >/dev/null 2>&1; then
    run cargo clippy --all-targets --all-features -- -D warnings
  else
    skip "clippy not installed (rustup component add clippy)"
  fi
}

verb_typecheck() {
  require_cargo || return 0
  run cargo check --all-targets
}

verb_test() {
  require_cargo || return 0
  run cargo test
}

verb_build() {
  require_cargo || return 0
  run cargo build
}

verb_securityscan() {
  if cargo audit --version >/dev/null 2>&1; then run cargo audit
  else skip "cargo-audit not installed (cargo install cargo-audit)"; fi
}

# Extended gates (agentic-code-quality alignment). Threshold via env:
#   LOOP_COVERAGE_MIN   minimum %-coverage (0 = measure only)
verb_coverage() {
  require_cargo || return 0
  local min="${LOOP_COVERAGE_MIN:-0}"
  if cargo tarpaulin --version >/dev/null 2>&1; then
    if [ "${min:-0}" -gt 0 ] 2>/dev/null; then run cargo tarpaulin --fail-under "$min"
    else run cargo tarpaulin; fi
  elif cargo llvm-cov --version >/dev/null 2>&1; then
    if [ "${min:-0}" -gt 0 ] 2>/dev/null; then run cargo llvm-cov --fail-under-lines "$min"
    else run cargo llvm-cov; fi
  else skip "no coverage tool (cargo install cargo-tarpaulin or cargo-llvm-cov)"; fi
}

verb_mutation() {
  if cargo mutants --version >/dev/null 2>&1; then run cargo mutants
  else skip "cargo-mutants not installed (cargo install cargo-mutants)"; fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
