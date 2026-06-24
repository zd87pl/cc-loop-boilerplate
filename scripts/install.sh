#!/usr/bin/env bash
# scripts/install.sh — non-interactive setup for CI / automation.
#
# For the guided, interactive experience, run `make setup`. This thin wrapper
# delegates to `setup.sh --yes`, which checks the Claude Code CLI + dependencies,
# wires the repo, and runs a no-cost smoke test WITHOUT mutating global state
# (system-package installs are printed, never auto-run, in --yes mode).
exec "$(dirname "$0")/setup.sh" --yes "$@"
