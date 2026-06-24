# Project Constitution

This document is the **supreme contract** for the spec-driven engineering loop.
Every stage, subagent, hook, and adapter in this repository is subordinate to
the rules below. When any instruction (a prompt, a SKILL, an ADR, a reviewer
comment) conflicts with this constitution, the constitution wins.

The rules are written in **EARS** (Easy Approach to Requirements Syntax) so each
is a single, individually testable claim. See `specs/templates/spec.md` for the
EARS forms. Rules are identified `CON-NNN` and may be cited from skills, agents,
and the verifier's traceability matrix.

> Precedence, highest to lowest: **Constitution → SPEC → PRD → ADR → Plan →
> Tasks → Code**. Code remains the source of truth for _behavior_; the
> SPEC/PRD/ADR set remains the contract that behavior is generated against and
> checked back against.

---

## Principles (the _why_)

- **The spec is the contract.** Implementation is generated _against_ the
  SPEC/PRD/ADR and verified _back against_ them. The spec drives generation and
  review; it does not replace the codebase.
- **Flag, don't fabricate.** Ambiguity is surfaced, never guessed away.
- **Small, reviewable increments.** One task → one focused change → one gate
  pass. Big-bang generation is a known anti-pattern and is forbidden.
- **Determinism over vibes.** Quality is enforced by scripts and hooks the model
  cannot opt out of, not by polite requests in a prompt.
- **Humans own sign-off and merge.** The machine proposes; a person disposes.
- **Portable and polyglot.** No stack assumptions leak outside `adapters/`.
- **Observable and auditable.** Every run can be reproduced and reviewed.

---

## Rules (EARS)

### Spec as contract

- **CON-001** The system shall treat the SPEC, PRD, and ADR set as the contract
  for any change.
- **CON-002** While generating any artifact, the agent shall trace every unit of
  work to at least one SPEC/PRD/ADR requirement.
- **CON-003** If code implements behavior that no requirement asks for, then the
  verifier shall report it as _drift_ and the change shall not pass verification
  until the drift is removed or a requirement is added by a human.
- **CON-004** If a plan or implementation decision conflicts with an ADR, then
  the agent shall halt and emit `NEEDS CLARIFICATION` rather than override the
  ADR.

### Clarification over fabrication

- **CON-010** When a requirement is ambiguous, under-specified, or missing an
  acceptance criterion, the agent shall emit a line beginning
  `NEEDS CLARIFICATION:` and halt the current stage for a human.
- **CON-011** The agent shall never invent requirements, public APIs, acceptance
  criteria, or test oracles to make a stage pass.

### Spec readiness (first-pass review)

- **CON-012** Before the spec human gate, the system shall run a first-pass
  readiness review that scores the spec across the readiness dimensions (problem
  clarity; scope & decision-readiness; testability & acceptance; NFR & guardrails;
  dependencies & second-order effects) and emits one verdict: `READY`, `CAVEATS`,
  or `NOT_READY`.
- **CON-013** If a critical gap is present (a requirement without a testable
  acceptance criterion, an unresolved `NEEDS CLARIFICATION`, a data- or
  security-touching change without a guardrail, or scope that is not
  decision-ready), then the verdict shall be `NOT_READY` and the controller shall
  halt before PLAN.
- **CON-014** The readiness review shall output prioritized, write-ready action
  items: a single "start here" fix and separated `Critical` and `Optimization`
  lists. It shall not flag every item as critical.
- **CON-015** Where the spec is classified `sensitive`, the verifier's effective
  coverage threshold shall be raised to the configured sensitive minimum.
- **CON-016** When the verify stage runs, the system shall produce a
  change-walkthrough (what changed, why, risk areas) so a human reviews with
  understanding rather than rubber-stamping.

### Grounding and cross-run memory

- **CON-017** Before planning, the system shall run a read-only codebase
  reconnaissance that writes a context map the plan stage reads, so plans are
  grounded in the code that exists rather than re-derived from zero each run.
- **CON-018** The system shall load cross-run memory at the start of a run and
  append a per-run digest (not transcripts) at its end, keeping PII/secrets out.
- **CON-019** Deferred items (Optimization findings, CAVEATS, drift) shall be
  carried into a persistent backlog rather than silently dropped.

### Determinism before judgment, and proving it

- **CON-020** Before the model reviews a spec, the system shall run a
  deterministic, model-free `spec-lint` and halt on structural errors — mechanics
  are checked for free; the model is reserved for judgment.
- **CON-021** The system shall ship a deterministic eval suite that asserts its
  guardrails (halt-on-ambiguity, lint, secret/destructive veto, protected-branch
  refusal, a real gate) and shall run it with no model calls so it is safe in CI.

### Increments

- **CON-020** While implementing, the agent shall prefer the smallest change that
  satisfies exactly one task.
- **CON-021** When a task is implemented, the agent shall write or update at
  least one test that proves the task's acceptance check before the task is
  considered done.
- **CON-022** The system shall record one commit per task, referencing the task
  identifier in the commit message.

### Determinism and gates

- **CON-030** The system shall enforce quality gates (format, lint, type-check,
  test, build, secret-scan, security-scan) as scripts and hooks, never as model
  instructions.
- **CON-031** While any required gate is failing, the controller shall not
  advance to a human pre-merge gate.
- **CON-032** Where a coverage threshold is configured, if a change lowers line
  coverage below that threshold, then verification shall fail.

### Safety, branches, and secrets

- **CON-040** The system shall operate only on a dedicated worktree or feature
  branch whose name carries the configured prefix.
- **CON-041** The system shall never commit to, push to, force-push to, or merge
  a protected branch.
- **CON-042** The system shall never run history-rewriting or destructive git
  operations (`push --force`, `reset --hard` on shared refs, `clean -fdx` of the
  worktree root, branch deletion of protected branches).
- **CON-043** If a secret or credential is detected in a file write or a command,
  then the operation shall be denied (PreToolUse exit code 2).
- **CON-044** The system shall never auto-merge; a human shall open or promote
  the PR to ready.

### Bounds

- **CON-050** When the iteration count reaches `max_iterations`, the controller
  shall stop and produce a partial-completion report rather than continue.
- **CON-051** When cumulative model spend reaches `cost_ceiling_usd`, the
  controller shall stop and report.
- **CON-052** While the loop is running, if an iteration produces no measurable
  progress (no stage advanced and no gate flipped to green), then the controller
  shall halt to avoid spinning.

### Human gates

- **CON-060** When the spec has been normalized, the system shall require human
  sign-off before any code is written (configurable; on by default).
- **CON-061** Before opening a PR, the system shall require human sign-off on the
  verifier's traceability matrix (configurable; on by default).

### Roles and least privilege

- **CON-070** Subagents that only inspect (`reviewer`, `security-auditor`,
  `verifier`) shall be configured read-only and shall not be granted edit tools.
- **CON-071** All file edits shall route through the `implementer` subagent or
  the parent session so permission prompts and hooks are honored.

### Observability and audit

- **CON-080** After each stage, the controller shall append a structured event
  (stage, result, duration, token usage, cost, git SHA) to the run log.
- **CON-081** Every run shall produce an audit trail sufficient to reproduce it:
  model strings, tool versions, config hash, and base + head git SHAs.

### Data handling (GDPR-aware)

- **CON-090** The system shall keep PII and secrets out of run logs and reports
  via the configured redaction patterns.
- **CON-091** The system shall document exactly what data leaves the machine (the
  content sent to the model API) and shall keep all other processing local.
- **CON-092** The system shall keep `runs_dir` out of version control by default.

---

_Extend this file per-org. Keep every addition in EARS form and give it a
`CON-NNN` identifier so it remains individually testable and citable._
