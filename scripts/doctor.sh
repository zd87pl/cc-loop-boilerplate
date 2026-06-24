#!/usr/bin/env bash
# scripts/doctor.sh — report prerequisite and configuration status clearly.
# Exit 0 if all REQUIRED tools are present; non-zero otherwise.
set -uo pipefail
cd "$(dirname "$0")/.."

if [ -t 1 ]; then
  red=$'\033[31m'; grn=$'\033[32m'; yel=$'\033[33m'; dim=$'\033[2m'; rst=$'\033[0m'
else red=; grn=; yel=; dim=; rst=; fi
ok(){ printf '  %s✓%s %s\n' "$grn" "$rst" "$*"; }
no(){ printf '  %s✗%s %s\n' "$red" "$rst" "$*"; }
wn(){ printf '  %s!%s %s\n' "$yel" "$rst" "$*"; }
hdr(){ printf '\n%s%s%s\n' "$dim" "$*" "$rst"; }

REQ_MISSING=0
ver(){ printf '%s' "$dim$("$1" --version 2>/dev/null | head -1)$rst"; }
req(){ if command -v "$1" >/dev/null 2>&1; then ok "$1  $(ver "$1")"; else no "$1 (required) — $2"; REQ_MISSING=1; fi; }
opt(){ if command -v "$1" >/dev/null 2>&1; then ok "$1  $(ver "$1")"; else wn "$1 (optional) — $2"; fi; }

printf '%sSpec-loop doctor%s\n' "$dim" "$rst"

hdr "Required"
req claude "https://docs.claude.com/claude-code"
req git   "install git"
req jq    "install jq (https://jqlang.github.io/jq)"
req yq    "install yq (mikefarah/yq or kislyuk/yq)"
req bash  "bash 3.2+"

hdr "Recommended"
opt gh "GitHub CLI — required to open PRs automatically (loop degrades gracefully without it)"
opt rg "ripgrep — faster search"
if command -v gitleaks >/dev/null 2>&1 || command -v trufflehog >/dev/null 2>&1; then
  ok "secret scanner present (gitleaks/trufflehog)"
else
  wn "no gitleaks/trufflehog — the PreToolUse guard falls back to a builtin regex scan"
fi
opt semgrep "richer securityscan (wire via .loop.yml gates.securityscan)"

hdr "Configuration"
if [ -f .loop.yml ]; then
  if yq -c '.' .loop.yml >/dev/null 2>&1 || yq -o=json '.' .loop.yml >/dev/null 2>&1; then ok ".loop.yml parses"; else no ".loop.yml present but does not parse as YAML"; REQ_MISSING=1; fi
else wn "no .loop.yml — built-in defaults apply"; fi

if [ -f .claude/settings.json ]; then
  jq -e . .claude/settings.json >/dev/null 2>&1 && ok ".claude/settings.json is valid JSON" || no ".claude/settings.json is invalid JSON (it will be silently ignored!)"
else wn "no .claude/settings.json (project hooks not wired here)"; fi

for h in pretool-guard posttool-format stop-gate; do
  f=".claude/hooks/$h.sh"
  if [ -x "$f" ]; then ok "hook $h.sh present + executable"
  elif [ -f "$f" ]; then wn "hook $h.sh present but not executable (run: chmod +x $f)"
  else wn "hook $h.sh missing"; fi
done

sk=$(ls -1 .claude/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
ag=$(ls -1 .claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
ok "skills: $sk   agents: $ag"

if jq -e . .claude-plugin/plugin.json >/dev/null 2>&1; then ok ".claude-plugin/plugin.json is valid"; else wn "no/invalid .claude-plugin/plugin.json (plugin install unavailable)"; fi

hdr "Detected stacks (in $(pwd))"
stacks="$(bash adapters/detect.sh . 2>/dev/null)"
if [ -n "$stacks" ]; then
  for s in $stacks; do
    [ -f "adapters/stacks/$s.sh" ] && ok "$s → adapters/stacks/$s.sh" || wn "$s detected but no adapter"
  done
else
  wn "no language stack detected — gates will skip; set .loop.yml gates.* to override per-verb"
fi

hdr "Summary"
if [ "$REQ_MISSING" -eq 0 ]; then ok "all required tools present — you can run the loop"; exit 0
else no "missing required tooling/config — resolve the ✗ items above"; exit 1; fi
