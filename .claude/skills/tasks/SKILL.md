---
name: tasks
description: Stage 3 (Tasks) of the spec-driven loop. Decompose the technical plan into small, ordered, independently testable tasks, each with its own acceptance check and the REQ-NNN it satisfies. Invoke explicitly as /tasks.
disable-model-invocation: true
argument-hint: "[spec dir]"
---

# /tasks — decompose into testable units (Stage ③)

**Owner:** `architect` subagent.   **Gate:** auto.

Read `specs/constitution.md`, the approved spec, and `plan.md` first.

## Procedure
1. Delegate to the **architect** subagent.
2. Break the plan into the smallest units that are each **independently
   implementable** and **testable in isolation**.
3. Order tasks by dependency. Give each a stable id (`T1`, `T2`, …), an
   acceptance check, and the `REQ-NNN`(s) it satisfies.
4. Keep tasks small enough that one task = one focused change = one gate pass
   (CON-020). Avoid big-bang tasks.

## Output
- `tasks.md`: an ordered checklist of tasks with ids, acceptance checks, and
  requirement references.

## Failure handling
If the plan is too vague to decompose into testable units, halt with
`NEEDS CLARIFICATION` rather than inventing scope.
