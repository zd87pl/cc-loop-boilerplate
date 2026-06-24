---
name: implement
description: Stage 4 (Implement) of the spec-driven loop. Implement the next unfinished task — the smallest change that satisfies it — together with a test that proves its acceptance check, then commit referencing the task id. Invoke explicitly as /implement.
disable-model-invocation: true
argument-hint: "[task id | next]"
---

# /implement — one task, one tested change (Stage ④)

**Owner:** `implementer` subagent.   **Gate:** auto (hooks run on every edit).

Read `specs/constitution.md`, the spec, and `tasks.md` first.

## Procedure
1. Pick the next unfinished task (or the one named in `$ARGUMENTS`).
2. Delegate to the **implementer** subagent.
3. Write the **test** for the task's acceptance check and the **code** that makes
   it pass — the smallest change that satisfies exactly this task (CON-020/021).
4. Let the gates run: the PostToolUse hook formats edits; the Stop hook runs the
   gate suite. Do not work around a failing gate — fix the cause.
5. Commit with a conventional message that references the task id, e.g.
   `feat(x): … (T2, REQ-003)` (CON-022).

## Output
- Code + test for one task, committed on the feature branch.

## Failure handling
If the task turns out ambiguous or the spec is wrong, **stop** and emit
`NEEDS CLARIFICATION` — never guess to make a gate pass (CON-011).
