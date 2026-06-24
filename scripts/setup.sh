#!/usr/bin/env bash
# scripts/setup.sh — interactive first-run setup for the spec-driven loop.
# Checks the Claude Code CLI + dependencies, offers to install what's missing,
# wires the repo, and runs a no-cost smoke test.
#
# Modes:
#   (default)   interactive and friendly
#   --yes, -y   non-interactive; safe defaults; never auto-installs system packages
#   --check     status only (no changes, no smoke test)
#   --live      also make one tiny real model call to verify auth + network (~$0.01)
#   --brief     less hand-holding
set -uo pipefail
cd "$(dirname "$0")/.."

ASSUME_YES=false; CHECK_ONLY=false; BRIEF=false; LIVE=false
for a in "$@"; do
  case "$a" in
    --yes|-y) ASSUME_YES=true ;;
    --check)  CHECK_ONLY=true ;;
    --live)   LIVE=true ;;
    --brief)  BRIEF=true ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (try --help)" >&2; exit 64 ;;
  esac
done
[ -t 0 ] || ASSUME_YES=true   # piped / no TTY -> never block on a prompt

if [ -t 1 ]; then
  B=$'\033[1m'; R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; D=$'\033[2m'; Z=$'\033[0m'
else B= R= G= Y= C= D= Z=; fi
ok(){ printf '  %s✓%s %s\n' "$G" "$Z" "$*"; }
no(){ printf '  %s✗%s %s\n' "$R" "$Z" "$*"; }
wn(){ printf '  %s!%s %s\n' "$Y" "$Z" "$*"; }
hdr(){ printf '\n%s%s%s\n' "$B" "$*" "$Z"; }
say(){ $BRIEF || printf '  %s%s%s\n' "$D" "$*" "$Z"; }
have(){ command -v "$1" >/dev/null 2>&1; }
ver(){ "$1" --version 2>/dev/null | head -1; }

ask(){ # ask "Q" default(Y|N) -> 0 = yes
  local q="$1" def="${2:-N}" ans hint
  [ "$def" = Y ] && hint="[Y/n]" || hint="[y/N]"
  if $ASSUME_YES; then [ "$def" = Y ]; return; fi
  printf '  %s%s%s %s%s%s ' "$C" "$q" "$Z" "$D" "$hint" "$Z"
  IFS= read -r ans </dev/tty 2>/dev/null || ans=""
  case "${ans:-}" in "") [ "$def" = Y ] ;; y|Y|yes|YES) true ;; *) false ;; esac
}

OS="$(case "$(uname -s)" in
  Darwin) echo macos ;;
  Linux)  grep -qi microsoft /proc/version 2>/dev/null && echo wsl || echo linux ;;
  *)      uname -s ;; esac)"
PM=none; for c in brew apt-get dnf pacman zypper apk; do have "$c" && { PM="$c"; break; }; done
if [ "$(id -u)" = 0 ]; then SUDO=""; elif have sudo; then SUDO="sudo "; else SUDO=""; fi

install_hint(){ # install_hint <tool> -> a runnable command or guidance string
  local t="$1"
  if [ "$t" = claude ]; then
    if have npm; then echo "npm install -g @anthropic-ai/claude-code"
    else echo "install Node.js + npm, then 'npm install -g @anthropic-ai/claude-code' (docs: https://docs.claude.com/claude-code)"; fi
    return
  fi
  case "$PM" in
    brew)    echo "brew install $t" ;;
    apt-get)
      case "$t" in
        yq)       echo "${SUDO}snap install yq   # or: pip install yq   (either yq flavor works)" ;;
        gh)       echo "see https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
        gitleaks) echo "download a release binary from https://github.com/gitleaks/gitleaks/releases" ;;
        semgrep)  echo "pip install semgrep" ;;
        *)        echo "${SUDO}apt-get update && ${SUDO}apt-get install -y $t" ;;
      esac ;;
    dnf)     echo "${SUDO}dnf install -y $t" ;;
    pacman)  echo "${SUDO}pacman -S --noconfirm $t" ;;
    zypper)  echo "${SUDO}zypper install -y $t" ;;
    apk)     echo "${SUDO}apk add $t" ;;
    *)       echo "install '$t' with your package manager" ;;
  esac
}
runnable(){ case "$1" in *"see "*|*"http"*|*"install '"*|*"install Node"*|*"download "*) return 1 ;; *) return 0 ;; esac; }

MISSING_REQ=0
offer_install(){ # offer_install <tool> <required|optional>
  local tool="$1" level="$2" cmd; cmd="$(install_hint "$tool")"
  printf '      %sinstall:%s %s%s%s\n' "$D" "$Z" "$C" "$cmd" "$Z"
  runnable "$cmd" || return 0
  $ASSUME_YES && return 0          # never auto-install system packages non-interactively
  local def=N; [ "$level" = required ] && def=Y
  if ask "Run it now?" "$def"; then
    if eval "$cmd"; then ok "installed $tool"; else no "install failed — run the command above manually"; fi
  fi
}

check(){ # check <binname> <required|optional> [install-tool] [label]
  local bin="$1" level="$2" tool="${3:-$1}" label="${4:-$1}"
  if have "$bin"; then ok "$label  ${D}$(ver "$bin")${Z}"; return 0; fi
  if [ "$level" = required ]; then no "$label - required, missing"; MISSING_REQ=$((MISSING_REQ + 1))
  else wn "$label - optional, missing"; fi
  offer_install "$tool" "$level"
}

summary_and_exit(){
  hdr "Next steps"
  if [ "$MISSING_REQ" -gt 0 ]; then
    no "$MISSING_REQ required tool(s) missing - install them (commands above), then re-run: make setup"
    exit 1
  fi
  ok "you are ready to go."
  printf '  %sfirst loop (no cost):%s  make selftest\n' "$D" "$Z"
  printf '  %snew feature:%s          make new-spec SLUG=001-my-feature   (then edit its spec.md)\n' "$D" "$Z"
  printf '  %sdry-run / for real:%s   make dry-run SPEC=specs/001-my-feature  |  make loop SPEC=...\n' "$D" "$Z"
  printf '  %s5-minute guide:%s       ONBOARDING.md\n' "$D" "$Z"
  exit 0
}

# ---------------------------------------------------------------------------
hdr "Spec-driven loop - setup"
say "Checks the Claude Code CLI and the tools the loop needs, offers to install"
say "what's missing, wires this repo, and runs a no-cost smoke test."
printf '  %senv:%s %s   %spackage manager:%s %s\n' "$D" "$Z" "$OS" "$D" "$Z" "$PM"

hdr "1. Required"
check claude required claude "Claude Code CLI"
check git    required
check jq     required
check yq     required yq
check bash   required

hdr "2. Recommended (optional)"
check gh optional gh "GitHub CLI (open PRs)"
check rg optional ripgrep "ripgrep (fast search)"
if have gitleaks || have trufflehog; then ok "secret scanner present"
else wn "no gitleaks/trufflehog - the guard falls back to a builtin scan"; offer_install gitleaks optional; fi
check semgrep optional semgrep "semgrep (richer securityscan)"

hdr "3. Claude Code"
if have claude; then
  ok "version $(ver claude)"
  say "Logged in? If not, run 'claude' once and '/login'. Per-stage models live in .loop.yml."
else
  no "Claude Code CLI not found (install above), then re-run setup."
fi

# Opt-in live check: one tiny real model call proves auth + network actually work
# (what 'claude --version' cannot). This is the failure that blocks a first run.
if $LIVE && have claude; then
  hdr "3b. Live model check (one tiny call, ~\$0.01)"
  if out="$(claude -p --output-format json --model haiku 'Reply with exactly: OK' 2>/tmp/loop-live.$$)"; then
    res="$(printf '%s' "$out" | jq -r '.result // empty' 2>/dev/null)"
    cost="$(printf '%s' "$out" | jq -r '.total_cost_usd // 0' 2>/dev/null)"
    if [ -n "$res" ]; then ok "model responded - auth + network OK (cost \$$cost)"
    else no "unexpected response - check 'claude' login (run 'claude' then /login)"; fi
  else no "live call failed - check 'claude' login and your network:"; head -c 200 /tmp/loop-live.$$ >&2; fi
  rm -f /tmp/loop-live.$$
elif $LIVE; then
  wn "--live requested but the Claude CLI is missing"
fi

$CHECK_ONLY && summary_and_exit

hdr "4. Wire this repo"
if ask "Make the loop scripts executable?" Y; then
  chmod +x adapters/detect.sh adapters/stacks/*.sh loop/run.sh scripts/*.sh \
           .claude/hooks/*.sh evals/run.sh 2>/dev/null || true
  ok "scripts are executable"
fi
[ -f .loop.yml ] && ok ".loop.yml present - the one file you usually edit" || wn "no .loop.yml (built-in defaults apply)"
if [ -f .claude/settings.json ]; then
  jq -e . .claude/settings.json >/dev/null 2>&1 && ok ".claude/settings.json is valid" \
    || no ".claude/settings.json is INVALID (it would be silently ignored)"
fi

hdr "5. This project's stacks"
stacks="$(bash adapters/detect.sh . 2>/dev/null || true)"
if [ -n "$stacks" ]; then for s in $stacks; do ok "$s -> adapters/stacks/$s.sh"; done
else say "no app stack here - gates skip; in your own repo they auto-detect."; fi

hdr "6. Smoke test (no model calls, no cost)"
if have jq && have yq && ask "Run the example loop in dry-run now?" Y; then
  if make selftest >/tmp/loop-setup-smoke.$$ 2>&1; then ok "self-test passed - the loop works end to end"
  else no "self-test failed:"; tail -15 /tmp/loop-setup-smoke.$$ >&2; fi
  rm -f /tmp/loop-setup-smoke.$$
else
  say "(skipped - needs jq + yq)"
fi

hdr "7. Org-wide install (optional)"
say "To get the slash commands + guardrails in any repo, run inside Claude Code:"
say "  /plugin marketplace add zd87pl/cc-loop-boilerplate"
say "  /plugin install spec-loop@cc-loop"

summary_and_exit
