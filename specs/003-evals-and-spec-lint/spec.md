# SPEC: Make the loop trustworthy to change — evals, spec-lint, real example

| Field        | Value                          |
| ------------ | ------------------------------ |
| Spec ID      | SPEC-003                       |
| Status       | approved                       |
| Owner        | platform-dx                    |
| Related PRD  | prd.md                         |
| Related ADRs | adr-001.md                     |
| Last updated | 2026-06-24                     |

## 1. Context

The loop ships guardrails (halt-on-ambiguity, ADR-conflict halt, secret veto,
protected-branch refusal, gates) but **nothing proves they fire**, and the only
worked example is spec-only (gates skip). We add three things so a team can
*evolve* the loop with confidence: a deterministic **spec-lint** (cheap gate
before the model review), an **eval harness** that asserts the guardrails on
fixtures in CI, and a **real worked example** the gates actually execute.

## 2. Scope

**In scope**

- `scripts/spec-lint.sh`: deterministic spec structure checks; wired as a gate
  before `/spec-review`, plus `make spec-lint`.
- `evals/`: fixtures + `evals/run.sh` + `make eval`, asserting deterministic
  guardrails (no model cost); wired into CI.
- `examples/duration-py/`: a real Python implementation of SPEC-000 with tests
  the python adapter runs and a real REQ⇄code⇄test matrix.

**Out of scope**

- Model-dependent evals (ADR-conflict/drift detection) run live, not in the
  deterministic CI suite (scaffolded as live-only fixtures).

## 3. Requirements (EARS)

| ID      | Type         | Requirement                                                                                                                  | Acceptance check |
| ------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| REQ-001 | Ubiquitous   | The system shall provide a deterministic spec linter that checks spec structure without calling a model.                      | AC-1, AC-2       |
| REQ-002 | Unwanted     | If a spec has no requirements, a duplicate REQ id, a requirement without an acceptance check, an unresolved TODO/TBD, or (when approved) an open NEEDS CLARIFICATION, then spec-lint shall exit non-zero. | AC-2 |
| REQ-003 | Event-driven | When the loop runs the spec stage, it shall run spec-lint as a gate and halt before `/spec-review` if it finds errors.        | AC-3             |
| REQ-004 | Ubiquitous   | The system shall provide an eval harness (`make eval`) that asserts deterministic guardrails on fixtures and exits non-zero if any case fails. | AC-4 |
| REQ-005 | Event-driven | When a spec contains an unresolved `NEEDS CLARIFICATION:`, the loop (even in dry-run) shall halt with status `needs_clarification`. | AC-5    |
| REQ-006 | Ubiquitous   | The system shall include a real example whose tests the stack adapter executes and passes, with a REQ⇄code⇄test matrix.        | AC-6             |
| REQ-007 | Ubiquitous   | The eval harness shall run with no model calls (deterministic) so it is safe in CI.                                           | AC-4             |

## 4. Acceptance criteria

| #    | Input / precondition                          | Expected result                                              | Covers          |
| ---- | --------------------------------------------- | ----------------------------------------------------------- | --------------- |
| AC-1 | `spec-lint.sh specs/000-example/spec.md`      | exit 0 (clean)                                              | REQ-001         |
| AC-2 | `spec-lint.sh` on a spec missing an AC / dup id | exit non-zero with the specific finding                   | REQ-001, REQ-002 |
| AC-3 | dry-run loop on a lint-failing spec           | halts at the spec gate before `/spec-review`                | REQ-003         |
| AC-4 | `make eval`                                    | every deterministic case PASSES; exit 0; no model called    | REQ-004, REQ-007 |
| AC-5 | dry-run loop on a spec with `NEEDS CLARIFICATION:` | status `needs_clarification`                            | REQ-005         |
| AC-6 | `adapters/stacks/python.sh test` in the example | exit 0 (real tests pass)                                  | REQ-006         |

## 5. Non-functional requirements

- **Deterministic & free:** spec-lint and the eval harness call no model.
- **Portable:** the example uses only the Python standard library.

## 6. Open questions

_None._

## 7. Traceability hints

`scripts/spec-lint.sh`; spec-lint wiring + dry-run clarification halt in
`loop/run.sh`; `evals/run.sh` + `evals/cases/`; `examples/duration-py/`;
`make spec-lint` / `make eval`; CI step in `.github/workflows/loop-gates.yml`.
