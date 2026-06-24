<!--
This PR was (or could be) produced by the spec-driven loop. Keep the
spec-coverage summary below — reviewers use it to confirm the change is on
contract before merging. The loop NEVER auto-merges; a human merges.
-->

## Summary

<!-- What changed and why, in 1-3 sentences. Link the SPEC/PRD/ADR. -->

- Spec: `specs/<NNN-feature>/spec.md`
- Related ADRs: <adr-001, ...>

## Spec-coverage summary

<!-- Paste the verifier's traceability matrix (or its summary) here.
     Source: .loop/runs/<run-id>/traceability.md -->

| Requirement | Implemented by | Proven by (test) | Status |
| ----------- | -------------- | ---------------- | ------ |
| REQ-001     |                |                  |        |

- **Coverage:** <covered>/<total> requirements; line coverage <NN%>
- **Drift:** <none / list behavior not requested by the spec>
- **Run report:** `.loop/runs/<run-id>/report.md`

## Pre-merge checklist

- [ ] All quality gates are green (fmt, lint, typecheck, test, build, securityscan)
- [ ] Every requirement is COVERED by code **and** a passing test
- [ ] No drift (no behavior the spec did not ask for)
- [ ] No `NEEDS CLARIFICATION` left open
- [ ] No secrets added; secret-scan gate passed
- [ ] Human sign-off on the traceability matrix (this is the pre-merge gate)
