---
name: plan
description: Stage 2 (Plan) of the spec-driven loop. Produce a technical plan from the approved spec + ADRs + .loop.yml constraints — patterns, integration contracts, NFRs, and the files expected to change. Invoke explicitly as /plan.
disable-model-invocation: true
argument-hint: "[spec dir]"
---

# /plan — technical plan (Stage ②)

**Owner:** `architect` subagent.   **Gate:** auto (+ optional human).

Read `specs/constitution.md` and the approved spec first.

## Inputs
- The approved `spec.md`, all `adr-*.md`, the `prd.md`, and `.loop.yml`.

## Procedure
1. Delegate to the **architect** subagent.
2. Produce a plan covering: chosen patterns; integration contracts (API shapes,
   error envelopes); NFRs (performance, security, data-handling); and the exact
   list of files expected to change.
3. Reference each relevant **ADR by id**. If a plan decision would conflict with
   an accepted ADR, **stop** and emit `NEEDS CLARIFICATION` (CON-004).
4. Map every plan element back to one or more `REQ-NNN` (no orphan work, no
   drift).

## Output
- `plan.md` at the location the controller specifies.

## Failure handling
ADR conflict or missing decision input → halt with `NEEDS CLARIFICATION`.
