# SPEC: Ground the loop in reality — codebase explorer + cross-run memory

| Field        | Value                          |
| ------------ | ------------------------------ |
| Spec ID      | SPEC-002                       |
| Status       | approved                       |
| Owner        | platform-dx                    |
| Related PRD  | prd.md                         |
| Related ADRs | adr-001.md                     |
| Last updated | 2026-06-24                     |

## 1. Context

Two failure modes from "Loop Engineering": agents **re-derive project context
from zero every run** (intent/comprehension debt), and **the model forgets
everything between runs** (no memory). We ground the loop in reality across two
axes: a cheap **codebase explorer** that maps the existing code before planning,
and a **cross-run memory + backlog** on disk so each run starts from what the
last one learned and deferred.

## 2. Scope

**In scope**

- An `explore` stage (skill `/explore`, read-only `explorer` agent) before
  `plan`, producing a context map the later stages read.
- A cross-run memory file and a carried-forward backlog, both on disk, read at
  the start of a run and updated at its end.

**Out of scope**

- A scheduled "heartbeat" that discovers work unprompted (that is Tier 2).
- External memory stores (Linear/DB); memory is local markdown here.

## 3. Requirements (EARS)

| ID      | Type         | Requirement                                                                                                                          | Acceptance check |
| ------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------ | ---------------- |
| REQ-001 | Ubiquitous   | The system shall run an `explore` stage before `plan` that surveys the existing codebase and writes a context map to the run dir.     | AC-1             |
| REQ-002 | Ubiquitous   | The context map shall capture relevant modules, conventions, integration points, prior art, and risks, and the plan stage shall read it. | AC-1          |
| REQ-003 | Ubiquitous   | The `explorer` subagent shall be read-only (no Edit/Write/NotebookEdit).                                                              | AC-2             |
| REQ-004 | Event-driven | When a run starts, the system shall load cross-run memory (if present) and make its path available to the stages as context.          | AC-3             |
| REQ-005 | Event-driven | When a run reaches a terminal state, the system shall append a digest (run id, spec id, status, verdict, iterations, cost) to memory. | AC-3             |
| REQ-006 | Ubiquitous   | Deferred items (Optimization findings, CAVEATS, drift) declared by a stage shall be carried into a persistent backlog and shown in the report. | AC-4    |
| REQ-007 | Unwanted     | If `make clean` is run, then per-run artifacts shall be removed but the cross-run memory and backlog shall be preserved (use `clean-all` to remove them). | AC-5 |
| REQ-008 | Optional     | Where `memory.enabled` (or `explore.enabled`) is false, the loop shall behave exactly as before.                                      | AC-6             |

## 4. Acceptance criteria

| #    | Input / precondition                       | Expected result                                                          | Covers          |
| ---- | ------------------------------------------ | ------------------------------------------------------------------------ | --------------- |
| AC-1 | Dry-run the loop                           | `explore` runs before `plan`; `context-map.md` exists; report references it | REQ-001, REQ-002 |
| AC-2 | Inspect the explorer agent                 | its `tools` omit Edit/Write/NotebookEdit                                  | REQ-003         |
| AC-3 | Two consecutive runs                       | `.loop/memory.md` gains a digest each run; the 2nd run loads the 1st      | REQ-004, REQ-005 |
| AC-4 | A run with a deferred item                 | the item appears in `.loop/backlog.md` and in the report                  | REQ-006         |
| AC-5 | `make clean` after a run                   | `.loop/runs` gone; `.loop/memory.md` and `.loop/backlog.md` remain        | REQ-007         |
| AC-6 | `explore.enabled: false`, `memory.enabled: false` | loop runs the original 8 stages with no memory side effects        | REQ-008         |

## 5. Non-functional requirements

- **Cheap explore:** the explore stage uses the `explore` model tier (haiku by
  default) — reconnaissance, not reasoning.
- **Local-only:** memory and backlog live under `runs_dir`'s parent (`.loop/`,
  gitignored); secrets/PII stay out per the redaction rules.
- **Backward compatible:** disabling either feature restores prior behavior.

## 6. Open questions

_None._

## 7. Traceability hints

`explore` wiring in `loop/run.sh`; `explorer` agent + `/explore` skill;
`loop/lib/memory.sh`; report section in `loop/lib/report.sh`; `make clean` /
`clean-all` in the `Makefile`; config under `.loop.yml` `explore:` / `memory:`.
