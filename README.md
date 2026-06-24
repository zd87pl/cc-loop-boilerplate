# Spec-Driven Engineering Loop (Claude Code boilerplate)

Turn a **SPEC + PRD + ADR** set into reviewed, tested implementation through a
closed verification loop — then stop at a human sign-off and open a PR. Never
auto-merges. Polyglot, portable, and minimal to configure.

```
SPEC + PRD + ADR
      │
      ▼
 ① SPECIFY ─► ② PLAN ─► ③ TASKS ─► ④ IMPLEMENT ─► ⑤ REVIEW ─► ⑥ FIX ─► ⑦ VERIFY
      ▲                                                                      │
      └──────────────────── gaps / drift / failed gates ◄───────────────────┘
                                          │
                                exit when VERIFY passes
                                          ▼
                          human sign-off → PR (never auto-merge)
```

## Why

Specs drift from code, AI changes are plausible-but-wrong more often than we'd
like, and "looks good" reviews miss defects. This boilerplate makes the spec the
contract: implementation is generated *against* SPEC/PRD/ADR and a verifier
checks the result *back against* them, with **deterministic gates** (format,
lint, type-check, test, build, secret/security scan) enforced by hooks the model
cannot opt out of, on an **isolated branch**, under **cost and iteration caps**,
with a **human owning sign-off and merge**.

## Quickstart

```sh
make doctor     # check prerequisites + configuration
make selftest   # dry-run the loop over the bundled example (no model calls, no cost)
make loop SPEC=specs/000-example   # run for real (needs `claude` auth)
```

`make selftest` walks all seven stages and writes a run report with a populated
traceability matrix to `.loop/runs/<id>/report.md` — without calling the model.

## How the loop works

| # | Stage | Owner (subagent) | Output | Gate |
| - | ----- | ---------------- | ------ | ---- |
| ① | Specify | `architect` | normalized EARS `spec.md` + open questions | human |
| ①·5 | Spec review | `spec-reviewer` | readiness scorecard + verdict + risk class | auto (`NOT_READY` halts) |
| ①·8 | Explore | `explorer` | codebase context map (cheap, read-only) | auto |
| ② | Plan | `architect` | technical plan referencing ADRs/NFRs | auto (+opt. human) |
| ③ | Tasks | `architect` | ordered, independently testable tasks | auto |
| ④ | Implement | `implementer` | code + tests per task, on a branch | auto (hooks run) |
| ⑤ | Review | `reviewer` + `security-auditor` | findings (severity, CWE) | auto |
| ⑥ | Fix | `implementer` | patches for findings | auto |
| ⑦ | Verify | `verifier` | SPEC/PRD/ADR ⇄ code ⇄ test matrix + coverage | human pre-merge |

The controller halts and asks a human on `NEEDS CLARIFICATION`, stops at
`max_iterations` or `cost_ceiling_usd`, and halts if an iteration shows no
measurable progress.

## Architecture

```
.claude/            Claude Code integration
  settings.json     hooks wiring + permission baseline (project mode)
  skills/*/SKILL.md the seven stage slash commands
  agents/*.md       architect, spec-reviewer, explorer, implementer, reviewer, security-auditor, verifier
  hooks/            pretool-guard (secret+danger veto), posttool-format, stop-gate
.claude-plugin/     plugin.json + marketplace.json (org-wide install)
plugin/README.md    distribution docs
specs/              constitution.md, templates/, and one dir per feature
adapters/           detect.sh + stacks/<lang>.sh (six-verb gate contract)
loop/               run.sh controller, state.schema.json, lib/
.loop.yml           the per-repo config you edit
Makefile            make doctor | selftest | dry-run | loop | gates | new-spec
.github/            PR template + CI that mirrors the gate suite
scripts/            install.sh / uninstall.sh
AGENTS.md           portable cross-tool agent context
CLAUDE.md           Claude-specific pointer to the above
```

## Configuration (`.loop.yml`)

The single file most engineers touch. Highlights (see the file for all keys and
inline docs):

| Key | Meaning |
| --- | --- |
| `spec_dir` | where SPEC/PRD/ADR live |
| `branch_prefix` / `protected_branches` | feature-branch prefix; branches the loop refuses to write |
| `max_iterations` / `cost_ceiling_usd` | hard stops on review↔fix cycles and spend |
| `require_human_gates` | which stages pause for a person (default: `spec`, `premerge`) |
| `models` | model alias per stage (`opus`/`sonnet`/`haiku`) |
| `gates.<verb>` | override any adapter command for your repo |
| `secret_scan`, `open_pr`, `pr_draft` | guardrails and PR behavior |

## Polyglot by adapters

The loop auto-detects the repo's stack(s) from manifest files and delegates
build/lint/test to per-language adapters. Each `adapters/stacks/<lang>.sh`
exports the same six verbs — `fmt lint typecheck test build securityscan` —
and missing optional tools skip gracefully (reported by `make doctor`, never
silently masked). Ship-in adapters: node, python, go, rust, java, dotnet, ruby.

**Add a stack:** copy `adapters/stacks/_template.sh` to `stacks/<lang>.sh`,
implement the verbs, and add a detection rule to `adapters/detect.sh`.

**Override a gate without an adapter:** set `gates.<verb>` in `.loop.yml`, e.g.
`gates.securityscan: "semgrep --config auto"`.

## Safety & governance

- Runs only on a dedicated worktree/branch; refuses protected branches and
  destructive git operations.
- A **PreToolUse** hook vetoes writes/commands that would expose a secret or
  rewrite shared history (exit code 2 denies).
- Hard `max_iterations` and `cost_ceiling_usd`; human gates after spec
  normalization and before opening a PR.
- Every run leaves an audit trail — `events.jsonl` + `report.md` with a
  reproducibility header (models, tool versions, config hash, base/head SHAs).
- **Data handling:** all processing is local; the only data leaving the machine
  is the content sent to the model API. PII/secrets are kept out of logs/reports,
  and `.loop/runs/` is gitignored.

## Distribution

Install org-wide as a Claude Code plugin (slash commands + subagents + hooks in
any repo), or vendor the repo to get the full headless orchestrator. See
[`plugin/README.md`](plugin/README.md).

## Portability

SPEC/PRD/ADR, `specs/constitution.md`, and `AGENTS.md` are plain markdown, so
engineers on Cursor / Copilot / Codex consume the same artifacts. The `.claude/`
directory is the Claude Code reference implementation; other tools ignore it.

## Tooling accuracy

The Claude-Code surface used here (headless `claude -p`, `--output-format json`,
`--permission-mode`, `--model`, `--max-budget-usd`, hook events, plugin/skill/
agent schemas) was verified against the installed CLI. Notably this CLI has **no
`--max-turns`**, so iteration bounds are enforced by the controller. Verify
against your installed version before relying on any flag — see `ONBOARDING.md`.

## Next

New here? Follow [`ONBOARDING.md`](ONBOARDING.md) — your first loop in ~5 minutes.
