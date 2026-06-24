---
name: explore
description: Cheap codebase reconnaissance before planning. Surveys the existing code and writes a context map (modules, conventions, integration points, prior art, risks) that the plan/tasks/implement stages read. Read-only. Invoke explicitly as /explore.
disable-model-invocation: true
argument-hint: "[spec dir]"
---

# /explore — ground the loop in the codebase (Stage ①·8)

**Owner:** `explorer` subagent (**read-only**).   **Gate:** auto.   **Model:**
the cheap `explore` tier (haiku by default) — this is recon, not reasoning.

Read `specs/constitution.md` and the active spec first.

## Procedure

1. Delegate to the **explorer** subagent.
2. Survey the existing code for what this change touches: relevant modules and
   entry points (`path:symbol`), conventions (build/test commands, naming, error
   handling, test layout), integration points and contracts to preserve, prior
   art to reuse, and the top risks.
3. Also load cross-run memory (the path the controller provides) so prior
   decisions and the carried-forward backlog inform the map.

## Output

- `context-map.md` in the run dir — concise enough that `plan`, `tasks`, and
  `implement` read all of it. Cite real paths/symbols; reuse beats reinvention.

## Why

This pays down "intent debt": the agent maps the territory once, where every
later stage reads it, instead of re-deriving project context from zero.
