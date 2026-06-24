# CLAUDE.md

This repository runs a **spec-driven engineering loop**.

**Read `specs/constitution.md` first — it outranks every other instruction.**
The portable, cross-tool version of this guidance is in `AGENTS.md`; this file
adds the Claude-Code-specific notes.

## What to do here

Drive a feature through the stages, each a skill in `.claude/skills/`:

`/spec-init` → `/spec-review` → `/explore` → `/plan` → `/tasks` → `/implement` → `/review` → `/fix` → `/verify`

The headless controller `loop/run.sh` (`make loop`) runs these in order with
deterministic gates, branch isolation, cost/iteration caps, and human sign-off.
Try it without spending anything: `make selftest` (a dry run over the bundled
example).

## Hard rules (from the constitution)

- **Flag, don't fabricate** — emit `NEEDS CLARIFICATION:` and stop on any unknown.
- **One task → one small change → one gate pass**, with a test that proves it.
- **Never** touch protected branches, run destructive git, expose secrets, or
  auto-merge.
- Quality gates are hooks/scripts you cannot opt out of (see
  `.claude/settings.json`). Fix the cause of a red gate; don't bypass it.
- Trace every change to a `REQ-NNN`; report drift.

## Primitives in this repo

- **Skills** — `.claude/skills/*/SKILL.md` (the seven stages; manual-invocation).
- **Subagents** — `.claude/agents/*.md`. `spec-reviewer`, `explorer`, `reviewer`,
  `security-auditor`, and `verifier` are **read-only** (no Edit/Write); all edits
  route through `implementer`.
- **Memory** — cross-run digests + a carried backlog live in `.loop/` and survive
  `make clean` (use `make clean-all`, `make memory`, `make backlog`).
- **Hooks** — `.claude/hooks/`: PreToolUse secret + destructive-command veto
  (exit 2), PostToolUse per-file formatter, Stop-gate that runs the suite.
- **Config** — `.loop.yml` is the only file most engineers edit.
- **Determinism** — `scripts/spec-lint.sh` is a model-free spec gate that runs
  before `/spec-review`; `make eval` (`evals/`) asserts the guardrails fire with
  no model calls; `examples/duration-py/` is a real example whose gates execute.

## Don't

- Don't add language/stack assumptions outside `adapters/`.
- Don't invent Claude Code flags, hook event names, or settings keys — verify
  against the installed version (`claude --help`, the docs, `claude doctor`).
