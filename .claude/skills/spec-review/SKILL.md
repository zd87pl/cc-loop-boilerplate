---
name: spec-review
description: First-pass readiness review of a normalized spec (between Specify and the human spec gate). Scores the spec across fixed dimensions, classifies risk, and emits a launch-readiness verdict with a "start here" fix, Critical/Optimization items, and write-ready replacement text. Read-only. Invoke explicitly as /spec-review.
disable-model-invocation: true
argument-hint: "[spec dir]"
---

# /spec-review — first-pass readiness review (Stage ①·5)

**Owner:** `spec-reviewer` subagent (**read-only**).   **Gate:** auto, but the
verdict can halt the loop; the human spec gate follows.

Read `specs/constitution.md`, the active spec, PRD, and ADRs first.

## Procedure

1. Delegate to the **spec-reviewer** subagent.
2. Score the five dimensions (problem clarity; scope/decision-readiness;
   testability & acceptance; NFR & guardrails; dependencies/second-order
   effects), classify risk (`low|standard|sensitive`), and apply the hard
   boundaries that force `NOT_READY`.
3. Produce a prioritized punch list: one **"start here"** fix, then **Critical**
   vs **Optimization** items, each with **write-ready replacement text**.

## Output (write all four where the controller specifies — the run dir)

- `spec-review.md` — the human-readable scorecard ("start here", dimensions,
  Critical/Optimization items with write-ready text).
- `spec-review.verdict` — exactly one token: `READY`, `CAVEATS`, or `NOT_READY`.
- `spec-review.riskclass` — exactly one token: `low`, `standard`, or `sensitive`.
- `spec-review.json` — `{verdict, risk_class, start_here, dimensions[], critical[], optimization[]}`.

## Gate behavior

The controller reads `spec-review.verdict`. `NOT_READY` halts the loop for a
human (the punch list is the fix list). `CAVEATS` proceeds but surfaces the items
at the human gate. `READY` proceeds. The verdict is decided by files the
controller reads — never by prose in this skill (CON-030).
