---
name: fix
description: Stage 6 (Fix) of the spec-driven loop. Apply the smallest patches that resolve the review/security findings, re-running the gates, and reference each finding id. Invoke explicitly as /fix.
disable-model-invocation: true
argument-hint: "[findings file]"
---

# /fix — resolve findings (Stage ⑥)

**Owner:** `implementer` subagent.   **Gate:** auto.

Read `specs/constitution.md`, the spec, and the findings from `/review` first.

## Procedure
1. Delegate to the **implementer** subagent.
2. For each finding, make the **minimum** change that resolves it. Do not add
   behavior the spec did not request (that would be new drift).
3. Re-run the gates after each fix. Reference the finding id in the commit, e.g.
   `fix(x): validate empty input (F1, REQ-004)`.
4. Update the findings count so the controller can decide whether to loop again.

## Output
- Patches resolving the findings, committed on the feature branch; an updated
  findings count.

## Failure handling
If a finding cannot be fixed without changing the contract, **stop** and emit
`NEEDS CLARIFICATION`. The loop ⑤→⑥ repeats until clean or `max_iterations`.
