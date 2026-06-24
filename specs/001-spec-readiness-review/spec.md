# SPEC: First-pass spec readiness review

| Field        | Value                          |
| ------------ | ------------------------------ |
| Spec ID      | SPEC-001                       |
| Status       | approved                       |
| Owner        | platform-dx                    |
| Related PRD  | prd.md                         |
| Related ADRs | adr-001.md                     |
| Last updated | 2026-06-24                     |

## 1. Context

The loop normalizes a spec to EARS and then asks a human to sign off. Inspired by
Uber's "first-pass PRD reviewer", we add an automated **readiness review** between
`spec-init` and that human gate: it scores the spec across fixed dimensions and
returns a launch-readiness verdict with prioritized, write-ready fixes, so the
human reviews a stronger artifact and the loop refuses to build on a weak one.

## 2. Scope

**In scope**

- A new `spec_review` stage (skill `/spec-review`, agent `spec-reviewer`) run
  after `spec-init`, before the spec human gate.
- A readiness verdict that can halt the loop, a risk classification that
  calibrates downstream depth, and a scorecard surfaced in the run report.
- A short change-walkthrough at verify (comprehension aid).

**Out of scope**

- Generating specs from scratch (spec-init already drafts/normalizes).
- Replacing human sign-off (the verdict strengthens it, never substitutes it).

## 3. Requirements (EARS)

| ID      | Type         | Requirement                                                                                                                                                                                 | Acceptance check |
| ------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| REQ-001 | Ubiquitous   | The system shall run a `spec_review` stage after `spec-init` and before the spec human gate.                                                                                                | AC-1             |
| REQ-002 | Ubiquitous   | The reviewer shall assess the spec across fixed dimensions: problem clarity, scope/decision-readiness, testability & acceptance criteria, NFR & guardrails, and dependencies/second-order effects. | AC-2       |
| REQ-003 | Ubiquitous   | The reviewer shall emit exactly one launch-readiness verdict: `READY`, `CAVEATS`, or `NOT_READY`.                                                                                           | AC-2, AC-3       |
| REQ-004 | Unwanted     | If any critical gap is present (a requirement with no testable acceptance criterion, an unresolved `NEEDS CLARIFICATION`, a data/security-touching change without a guardrail, or scope that is not decision-ready), then the verdict shall be `NOT_READY`. | AC-3 |
| REQ-005 | Event-driven | When the verdict is `NOT_READY`, the controller shall halt for a human rather than proceed to PLAN.                                                                                         | AC-3             |
| REQ-006 | Ubiquitous   | The reviewer shall output a single "start here" highest-priority fix and shall split action items into `Critical` and `Optimization` lists.                                                 | AC-2             |
| REQ-007 | Ubiquitous   | The reviewer shall provide write-ready replacement text for each identified gap.                                                                                                            | AC-2             |
| REQ-008 | Optional     | Where the reviewer classifies the spec risk as `sensitive`, the verifier's effective coverage threshold shall be raised to the configured sensitive minimum.                                | AC-4             |
| REQ-009 | Ubiquitous   | The run report shall include the readiness verdict, risk class, the "start here" fix, and the scorecard.                                                                                    | AC-1, AC-2       |
| REQ-010 | Event-driven | When the verify stage runs, the system shall produce a change-walkthrough (what changed, why, risk areas) and include it in the report.                                                     | AC-5             |

## 4. Acceptance criteria

| #    | Input / precondition                                        | Expected result                                                            | Covers          |
| ---- | ----------------------------------------------------------- | -------------------------------------------------------------------------- | --------------- |
| AC-1 | Dry-run the loop over a complete spec                       | `spec_review` stage runs and passes; report has a "Spec readiness" section | REQ-001, REQ-009 |
| AC-2 | A complete, testable spec                                   | verdict `READY`; scorecard with 5 dimensions, a "start here", and lists    | REQ-002,003,006,007,009 |
| AC-3 | A spec containing an unresolved `NEEDS CLARIFICATION` line  | verdict `NOT_READY`; controller halts before PLAN                          | REQ-003,004,005 |
| AC-4 | Risk class `sensitive` with `sensitive_coverage_threshold`  | effective coverage threshold raised to the configured minimum             | REQ-008         |
| AC-5 | Verify stage completes                                      | a change-walkthrough appears in the report                                 | REQ-010         |

## 5. Non-functional requirements

- **Determinism:** the verdict and risk class are written to machine-readable
  files the controller reads; no model-prompt enforcement of the gate.
- **Backward compatible:** with the feature disabled (`spec_review.enabled:
  false`) the loop behaves exactly as before.
- **No new required dependencies** beyond the existing jq/yq/claude/git baseline.

## 6. Open questions

_None._

## 7. Traceability hints

Stage wiring in `loop/run.sh`; skill in `.claude/skills/spec-review/`; agent in
`.claude/agents/spec-reviewer.md`; report sections in `loop/lib/report.sh`;
config in `.loop.yml`; rules in `specs/constitution.md`.
