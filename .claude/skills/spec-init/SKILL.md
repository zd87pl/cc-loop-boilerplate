---
name: spec-init
description: Stage 1 (Specify) of the spec-driven loop. Normalize a rough description or existing SPEC/PRD/ADR into an EARS-structured spec with explicit, testable acceptance criteria, flagging every unknown as NEEDS CLARIFICATION. Invoke explicitly as /spec-init.
disable-model-invocation: true
argument-hint: "[spec dir | rough description]"
---

# /spec-init — normalize the spec (Stage ①)

**Owner:** `architect` subagent.   **Gate:** human sign-off.

Read `specs/constitution.md` before doing anything; it is the supreme contract.

## Inputs
- `$ARGUMENTS`: a spec directory (containing `spec.md`/`prd.md`/`adr-*.md`) or a
  rough feature description. Also read `specs/templates/spec.md` for the shape.

## Procedure
1. Delegate to the **architect** subagent.
2. Restate every requirement in **EARS** form with a stable `REQ-NNN` id and a
   concrete acceptance check (input → expected output, including error cases).
3. Extract acceptance criteria explicitly into a table the tests can assert.
4. For **every** unknown, ambiguity, conflicting source, or missing acceptance
   criterion, write a line beginning `NEEDS CLARIFICATION:` and **stop** — do not
   guess or invent (CON-010, CON-011).

## Output
- The normalized spec written back to the spec's `spec.md` (or where the loop
  controller specifies).
- An open-questions list. The spec is not `approved` while any remain.

## Failure handling
If any `NEEDS CLARIFICATION` remains, halt and surface it to the human; the loop
will not advance to PLAN until the spec is signed off.
