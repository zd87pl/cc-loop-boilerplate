---
name: review
description: Stage 5 (Review) of the spec-driven loop. Run an adversarial code review and a CWE-aware security pass over the change, producing a findings list with severities. Read-only. Invoke explicitly as /review.
disable-model-invocation: true
argument-hint: "[branch | diff range]"
---

# /review — adversarial + security review (Stage ⑤)

**Owners:** `reviewer` and `security-auditor` subagents (both **read-only**).
**Gate:** auto.

Read `specs/constitution.md` and the active spec first.

## Procedure
1. Delegate **in parallel** to:
   - the **reviewer** subagent — an *adversarial* pass that looks for the ways the
     change is wrong (correctness vs. spec, edge cases, error handling,
     concurrency, drift), and
   - the **security-auditor** subagent — common weakness classes annotated with
     **CWE** ids.
2. Neither subagent edits files. They only report findings.
3. Merge and de-duplicate the findings.

## Output
- A findings list as JSON matching `loop/findings.schema.json`:
  `{"start_here": "<the one fix to do first>",
  "findings":[{id, severity, title, cwe?, file?, line?, requirement?, detail?, source?}]}`
  plus a findings **count** (a bare integer), written where the controller
  specifies. Severity ∈ `critical|high|medium|low`; `source` ∈
  `reviewer|security-auditor` records which agent raised it. Lead with the
  single **"start here"** fix and keep `critical` for things that must block
  merge — prioritization is part of the job.
- The controller validates this file against the schema and **derives** its
  loop decision from it (CON-026/033): findings at or above the configured
  blocking severity repeat the fix cycle; the rest are carried to the backlog
  (CON-035). A malformed findings file halts the run — it never passes silently.

## Next
Findings flow to `/fix`. The review↔fix cycle repeats until the review is clean
or `max_iterations` is reached. Prefer a few real findings over a pile of nits.
