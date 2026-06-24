#!/usr/bin/env bash
# scripts/install.sh — verify prerequisites and make the loop usable. This script
# does NOT mutate global state; the only footprint is making bundled scripts
# executable (reversible). Plugin install happens inside Claude Code.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "== spec-loop install =="

# 1) prerequisites
if ! bash scripts/doctor.sh; then
  echo
  echo "Resolve the required tools reported above, then re-run scripts/install.sh."
  exit 1
fi

# 2) make bundled scripts executable (local, reversible footprint)
chmod +x adapters/detect.sh adapters/stacks/*.sh loop/run.sh \
         .claude/hooks/*.sh scripts/*.sh 2>/dev/null || true
echo
echo "Made bundled scripts executable."

# 3) plugin install instructions (run inside Claude Code)
cat <<'MSG'

To install the stages, subagents, and guardrail hooks org-wide, run INSIDE
Claude Code:

    /plugin marketplace add zd87pl/cc-loop-boilerplate
    /plugin install spec-loop@cc-loop

Already working inside this repo? The .claude/ config here is active as-is
(vendored mode) — just run `make dry-run` or `make loop`.
MSG

if claude plugin --help >/dev/null 2>&1; then
  echo
  echo "Tip: a 'claude plugin' CLI is available; see 'claude plugin --help' for"
  echo "non-interactive marketplace management."
fi

echo
echo "Install check complete. No global state was modified by this script."
