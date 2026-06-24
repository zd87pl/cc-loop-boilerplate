# AGENTS.md — portable agent context

This repository runs a **spec-driven engineering loop**. Any coding agent
(Claude Code, Cursor, Copilot, Codex, …) working here must follow the rules
below. This file is plain markdown on purpose so every tool can consume it; the
Claude-Code-specific notes live in `CLAUDE.md`.

## The contract

- **`specs/constitution.md` is supreme — read it first.** When any instruction
  conflicts with it, the constitution wins.
- The **SPEC / PRD / ADR** set in `specs/` is the contract. Generate code
  *against* it; verify the result *back against* it.
- Code is the source of truth for **behavior**; the spec is the contract that
  behavior is checked against. The spec does not replace the codebase.

## The loop

```
specify → spec-review → explore → plan → tasks → implement → review → fix → verify → sign-off → PR
   ▲           │ NOT_READY halts                                       │
   └───────────┴────────── gaps / drift / failed gates ◄──────────────┘
```

A cross-run memory + backlog on disk (`.loop/`) carries decisions and deferred
items between runs, so each run starts from what the last one learned.

One task → one focused change → one gate pass. **No big-bang generation.**

## Non-negotiables

- **Flag, don't fabricate.** On any unknown, ambiguity, or missing acceptance
  criterion, emit a line starting `NEEDS CLARIFICATION:` and stop. Never invent
  requirements, APIs, acceptance criteria, or test oracles.
- **Smallest change** that satisfies exactly one task, plus a test that proves
  its acceptance check.
- **Trace everything** to a `REQ-NNN`; report any behavior the spec did not ask
  for as drift.
- **Safety:** never commit/push to a protected branch, never run destructive git
  operations, never expose secrets, never auto-merge. A human signs off and
  merges.
- **Gates are deterministic.** Formatting, lint, type-check, test, build, and
  secret/security scans are enforced by scripts/hooks you cannot opt out of.
  Don't work around a failing gate — fix its cause.

## Where things are

| Path | What |
| --- | --- |
| `specs/constitution.md` | the supreme EARS rules (`CON-NNN`) |
| `specs/templates/` | SPEC / PRD / ADR templates |
| `specs/<NNN-feature>/` | one feature's SPEC/PRD/ADR |
| `.loop.yml` | the per-repo config you edit |
| `adapters/` | per-language gate commands (the six-verb contract) |
| `loop/` | the headless controller (`run.sh`) + libraries |
| `.claude/` | Claude-Code skills/agents/hooks (other tools ignore this) |

## Adapter contract (polyglot gates)

`adapters/stacks/<lang>.sh` implements six verbs: `fmt lint typecheck test build
securityscan`. Run one with `bash adapters/stacks/<lang>.sh <verb>`. Override any
verb per-repo via `.loop.yml` → `gates.<verb>`. Add a stack by copying
`adapters/stacks/_template.sh` and adding a rule to `adapters/detect.sh`.

## Roles (when your tool supports subagents)

- **architect** — spec, plan, tasks (authoring only)
- **spec-reviewer** — first-pass readiness review of the spec (read-only)
- **explorer** — codebase reconnaissance before planning (read-only)
- **implementer** — code + tests, one task at a time
- **reviewer** — adversarial review (read-only)
- **security-auditor** — CWE-aware weakness review (read-only)
- **verifier** — traceability + coverage (read-only)

Inspection roles never edit files; all edits route through the implementer.
