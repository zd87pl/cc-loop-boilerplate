#!/usr/bin/env bash
# JVM (Java/Kotlin) adapter. Detected by: pom.xml | build.gradle[.kts]
#
# JVM repos vary widely in formatting/linting/SAST plugins, so fmt, lint, and
# securityscan default to documented skips — wire them per-repo via .loop.yml
# (gates.fmt / gates.lint / gates.securityscan). test and build delegate to the
# detected build tool.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
. "$SCRIPT_DIR/../lib.sh"

mvn_cmd()    { if [ -x ./mvnw ]; then echo ./mvnw; elif have mvn; then echo mvn; fi; }
gradle_cmd() { if [ -x ./gradlew ]; then echo ./gradlew; elif have gradle; then echo gradle; fi; }
is_gradle()  { [ -f build.gradle ] || [ -f build.gradle.kts ]; }

# build_tool_run <maven-args...> -- <gradle-args...>
build_tool_run() {
  local mvn_args=() gradle_args=() seen=0 a
  for a in "$@"; do
    if [ "$a" = "--" ]; then seen=1; continue; fi
    if [ "$seen" -eq 0 ]; then mvn_args+=("$a"); else gradle_args+=("$a"); fi
  done
  if [ -f pom.xml ]; then
    local m; m="$(mvn_cmd)"
    [ -n "$m" ] && run "$m" "${mvn_args[@]}" || skip "maven not available (install maven or add mvnw)"
  elif is_gradle; then
    local g; g="$(gradle_cmd)"
    [ -n "$g" ] && run "$g" "${gradle_args[@]}" || skip "gradle not available (install gradle or add gradlew)"
  else
    skip "no pom.xml or build.gradle found"
  fi
}

verb_fmt()          { skip "configure gates.fmt (e.g. spotless:apply / spotlessApply)"; }
verb_lint()         { skip "configure gates.lint (e.g. checkstyle / spotbugs / ktlint)"; }
verb_typecheck()    { note "type checking happens during build"; verb_build; }
verb_test()         { build_tool_run -q -B test -- test; }
verb_build()        { build_tool_run -q -B -DskipTests package -- build -x test; }
verb_securityscan() { skip "configure gates.securityscan (e.g. owasp dependency-check)"; }

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  adapter_dispatch "${1:-}"
fi
