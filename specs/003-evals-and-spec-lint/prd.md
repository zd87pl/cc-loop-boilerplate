# PRD: Make the loop trustworthy to change

| Field        | Value       |
| ------------ | ----------- |
| PRD ID       | PRD-003     |
| Status       | approved    |
| Owner        | platform-dx |
| Related SPEC | SPEC-003    |
| Last updated | 2026-06-24  |

## 1. Problem

The loop ships guardrails but nothing proves they fire, and the only example is
spec-only (gates skip). Teams can't safely change a prompt, gate, or stage
without risking a silent regression in a guarantee they can't see.

## 2. Goals

- Catch loop regressions with assertions, not in production.
- Reject malformed specs cheaply (deterministically) before spending a model.
- Show the loop working on real code with real, executing gates.

## 3. Non-goals

- Model-dependent evals in CI (those run live, separately).

## 4. Users / personas

- **Loop maintainer** — changes a prompt/gate and wants a red test if a guarantee
  breaks.
- **Spec author** — wants instant, deterministic feedback on structure.

## 5. User stories

- As a maintainer, I want `make eval` to fail if the secret veto or the
  ambiguity-halt stops working, so I never ship a broken guardrail.
- As a spec author, I want `make spec-lint` to flag a missing acceptance check
  before I burn a model call on `/spec-review`.

## 6. Success metrics

- `make eval` asserts every deterministic guardrail and runs with zero model
  cost.
- The example's gates execute and pass (not skip).

## 7. Milestones / scope

- M1: spec-lint + eval harness + real example (this spec). M2: live-eval fixtures
  for ADR-conflict/drift.

## 8. Risks, dependencies, open questions

- Risk: evals become flaky → mitigated by keeping them deterministic (no model).
  Dependencies: none new. Open questions: none.
