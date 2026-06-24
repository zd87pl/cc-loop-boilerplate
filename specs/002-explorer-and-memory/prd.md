# PRD: Ground the loop in reality

| Field        | Value       |
| ------------ | ----------- |
| PRD ID       | PRD-002     |
| Status       | approved    |
| Owner        | platform-dx |
| Related SPEC | SPEC-002    |
| Last updated | 2026-06-24  |

## 1. Problem

Per "Loop Engineering", agents pay **intent debt** (re-deriving project context
every run) and have **no memory between runs**. The result is plans ungrounded in
the actual codebase and the same findings/decisions rediscovered run after run.

## 2. Goals

- Plans grounded in the real code (conventions, integration points, prior art).
- A run starts from what prior runs learned and deferred.
- Deferred work is captured, not lost.

## 3. Non-goals

- Unprompted scheduled discovery (Tier 2), or external memory stores.

## 4. Users / personas

- **The loop** — needs the codebase mapped and prior context loaded.
- **The engineer** — wants a visible backlog of deferred items across runs.

## 5. User stories

- As the loop, I want a context map before planning, so my plan fits the code
  that exists.
- As an engineer, I want deferred Optimization findings to persist, so they are
  not silently dropped each run.

## 6. Success metrics

- Every run reads memory at start and writes a digest at end.
- Deferred items survive across runs in the backlog.

## 7. Milestones / scope

- M1: explore stage + cross-run memory/backlog (this spec). M2 (Tier 2):
  scheduled triage that feeds the same backlog.

## 8. Risks, dependencies, open questions

- Risk: memory grows unbounded → mitigated by append-of-digests (small) and a
  documented prune. Dependencies: none new. Open questions: none.
