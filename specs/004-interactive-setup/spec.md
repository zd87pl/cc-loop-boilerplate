# SPEC: Interactive setup

| Field        | Value                     |
| ------------ | ------------------------- |
| Spec ID      | SPEC-004                  |
| Status       | approved                  |
| Owner        | platform-dx               |
| Related PRD  | prd.md                    |
| Related ADRs | adr-001.md                |
| Last updated | 2026-06-24                |

## 1. Context

The current `install.sh` is non-interactive and just prints status. A new
engineer kicking this off — first-timer or veteran — wants a guided check that
confirms the **Claude Code CLI** and every dependency is present, offers to
install what's missing, wires the repo, and proves it works, without reading the
README first. It must also stay fast and scriptable for experienced devs and CI.

## 2. Scope

**In scope**

- An interactive `scripts/setup.sh` (`make setup`) that checks required +
  recommended tools, offers OS-aware installs, wires the repo, and runs a no-cost
  smoke test.
- Non-interactive (`--yes`) and status-only (`--check`) modes.

**Out of scope**

- Auto-authenticating Claude, or installing language toolchains (only the loop's
  own dependencies).

## 3. Requirements (EARS)

| ID      | Type         | Requirement                                                                                                                              | Acceptance check |
| ------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| REQ-001 | Ubiquitous   | The system shall provide an interactive setup that checks the Claude Code CLI and required deps (git, jq, yq, bash) and recommended deps (gh, ripgrep, a secret scanner, semgrep), reporting each clearly. | AC-1 |
| REQ-002 | Event-driven | When a dependency is missing, the system shall show an OS/package-manager-appropriate install command and, when interactive, offer to run it. | AC-2 |
| REQ-003 | Unwanted     | If a required tool is still missing at the end, then setup shall exit non-zero with guidance to install it and re-run.                    | AC-3             |
| REQ-004 | Ubiquitous   | The system shall support a non-interactive `--yes` mode (safe defaults; never auto-installs system packages) and a `--check` status-only mode. | AC-4, AC-5 |
| REQ-005 | State-driven | While stdin is not a TTY, the system shall behave non-interactively instead of blocking on a prompt.                                      | AC-5             |
| REQ-006 | Ubiquitous   | The system shall wire the repo (make scripts executable, validate `.loop.yml` and `.claude/settings.json`) and offer a no-cost smoke test (`make selftest`). | AC-6 |
| REQ-007 | Ubiquitous   | The system shall give first-timers explanations and tailored next steps while letting experienced devs go fast (`--brief`/`--yes`).        | AC-1, AC-4       |

## 4. Acceptance criteria

| #    | Input / precondition                | Expected result                                                          | Covers          |
| ---- | ----------------------------------- | ------------------------------------------------------------------------ | --------------- |
| AC-1 | `setup.sh --check`                  | prints required + recommended status; exits 0 when all required present  | REQ-001, REQ-007 |
| AC-2 | a missing tool, interactive         | an install command is shown for the detected package manager             | REQ-002         |
| AC-3 | a required tool missing             | non-zero exit with "install … then re-run" guidance                      | REQ-003         |
| AC-4 | `setup.sh --yes`                    | runs non-interactively; makes scripts executable; runs smoke test; does not auto-install system packages | REQ-004, REQ-007 |
| AC-5 | no TTY on stdin (piped)             | does not hang; takes non-interactive defaults                            | REQ-004, REQ-005 |
| AC-6 | `setup.sh --yes` with deps present  | scripts executable; `make selftest` runs and passes                      | REQ-006         |

## 5. Non-functional requirements

- **No surprises:** never mutates global state without consent; `--yes` only does
  safe local actions (chmod, smoke test) and prints (does not run) system installs.
- **Portable:** POSIX-friendly bash; detects macOS/Linux/WSL and brew/apt/dnf/
  pacman/zypper/apk.

## 6. Open questions

_None._

## 7. Traceability hints

`scripts/setup.sh`; `make setup` in the Makefile; `scripts/install.sh` delegates
to it; README/ONBOARDING lead with `make setup`.
