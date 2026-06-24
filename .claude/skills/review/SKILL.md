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
- A findings list as JSON: `{"start_here": "<the one fix to do first>",
  "findings":[{id, severity, cwe?, file, line, requirement?, detail}]}` plus a
  findings **count**, written where the controller specifies. Severity ∈
  `critical|high|medium|low`. Lead with the single **"start here"** fix and keep
  `critical` for things that must block merge — prioritization is part of the job.

## Next
Findings flow to `/fix`. The review↔fix cycle repeats until the review is clean
or `max_iterations` is reached. Prefer a few real findings over a pile of nits.
