# PRD: Interactive setup

| Field        | Value       |
| ------------ | ----------- |
| PRD ID       | PRD-004     |
| Status       | approved    |
| Owner        | platform-dx |
| Related SPEC | SPEC-004    |
| Last updated | 2026-06-24  |

## 1. Problem

First-run friction. A new engineer clones this and doesn't know whether they have
the Claude Code CLI, jq, yq, etc., or how to get them. The current `install.sh`
just prints status. We want a guided, one-command setup that works whether you're
new to this or a veteran who wants to go fast.

## 2. Goals

- One command (`make setup`) gets a person from clone to a working first loop.
- Clear, actionable output: what's missing and exactly how to get it.
- Fast/scriptable path for experienced devs and CI.

## 3. Non-goals

- Authenticating Claude for the user; installing language toolchains.

## 4. Users / personas

- **First-timer** — wants explanations, install help, and "what do I run next".
- **Experienced dev / CI** — wants `--check`/`--yes`, no hand-holding, no surprises.

## 5. User stories

- As a newcomer, I want setup to tell me the Claude CLI is missing and the exact
  install command, so I'm unblocked without reading docs.
- As a veteran, I want `make setup` to verify everything and run the smoke test in
  seconds, then get out of my way.

## 6. Success metrics

- From a clean machine, `make setup` either ends "you're ready" or lists exactly
  what to install.
- No global state changed without consent.

## 7. Milestones / scope

- M1: interactive setup + check/yes modes (this spec).

## 8. Risks, dependencies, open questions

- Risk: auto-install surprises → mitigated by showing every command first and
  never auto-installing system packages non-interactively. Open questions: none.
