---
name: verify
description: Stage 7 (Verify) of the spec-driven loop. Build the SPEC/PRD/ADR ⇄ code ⇄ test traceability matrix, report uncovered requirements, drift, and a coverage figure. Read-only; this is the human pre-merge gate. Invoke explicitly as /verify.
disable-model-invocation: true
argument-hint: "[spec dir]"
---

# /verify — close the loop (Stage ⑦)

**Owner:** `verifier` subagent (**read-only**).   **Gate:** human, pre-merge.

Read `specs/constitution.md`, the spec, the PRD, and every ADR first.

## Procedure
1. Delegate to the **verifier** subagent.
2. Build a **traceability matrix** with one row per requirement:
   `Requirement | Implemented by (file:symbol) | Proven by (test) | Status`.
   - `COVERED` only when real code implements it **and** a passing test asserts
     its acceptance criteria (read the test — confirm it is not trivial).
   - `UNCOVERED` when code or a proving test is missing.
   - `DRIFT` for behavior no requirement asked for (CON-003).
3. Compute a coverage figure (covered/total, plus line coverage if a tool is
   available) and list every uncovered requirement and every drift.

## Output
- `traceability.md` (the matrix) and a short verdict: **PASS** only if every
  requirement is COVERED, there is no DRIFT, and no required gate is red;
  otherwise **FAIL** with specific reasons.

## Gate
This is the human pre-merge gate. A person reviews the matrix and signs off
before the loop opens a PR. The loop **never** auto-merges (CON-044).
