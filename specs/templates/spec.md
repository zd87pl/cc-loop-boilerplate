<!--
SPEC template — EARS-structured.

Copy this file to specs/<NNN-feature-slug>/spec.md and fill it in. One spec
describes one feature. The loop operates on a single spec at a time.

EARS quick reference (each requirement must be ONE individually testable claim):
  Ubiquitous       The system shall <response>.
  Event-driven     When <trigger>, the system shall <response>.
  State-driven     While <state>, the system shall <response>.
  Unwanted         If <condition>, then the system shall <response>.
  Optional         Where <feature included>, the system shall <response>.
If a requirement cannot be expressed as one verifiable claim, split it.

Any unknown becomes a line beginning `NEEDS CLARIFICATION:` under §6 and halts
the spec stage for a human (CON-010). Do not guess.
-->

# SPEC: <Feature title>

| Field        | Value                                   |
| ------------ | --------------------------------------- |
| Spec ID      | SPEC-<NNN>                              |
| Status       | draft \| in-review \| approved          |
| Owner        | <name / team>                           |
| Related PRD  | <prd.md or link>                        |
| Related ADRs | <adr-001.md, ...>                       |
| Last updated | <YYYY-MM-DD>                            |

## 1. Context

Why this exists, in 2–4 sentences. Link the PRD for the product framing. State
the user-visible behavior this spec governs.

## 2. Scope

**In scope**
- <bullet>

**Out of scope**
- <bullet>

## 3. Requirements (EARS)

Each requirement has a stable `REQ-NNN` id, an EARS type, and an acceptance
check. Ids are referenced by tasks, tests, and the verifier's traceability
matrix — do not renumber once merged.

| ID       | Type        | Requirement                                                        | Acceptance check |
| -------- | ----------- | ------------------------------------------------------------------ | ---------------- |
| REQ-001  | Ubiquitous  | The system shall <response>.                                       | <how proven>     |
| REQ-002  | Event-driven| When <trigger>, the system shall <response>.                       | <how proven>     |
| REQ-003  | State-driven| While <state>, the system shall <response>.                        | <how proven>     |
| REQ-004  | Unwanted    | If <condition>, then the system shall <response>.                  | <how proven>     |
| REQ-005  | Optional    | Where <feature included>, the system shall <response>.             | <how proven>     |

## 4. Acceptance criteria (concrete oracles)

Worked examples a test can assert directly. Prefer input → expected-output pairs
and explicit error cases.

| # | Input / precondition | Expected result      | Covers   |
| - | -------------------- | -------------------- | -------- |
| 1 | <input>              | <output>             | REQ-001  |
| 2 | <invalid input>      | <error behavior>     | REQ-004  |

## 5. Non-functional requirements

- **Performance:** <e.g. O(n) over input length; no I/O in the core path>
- **Security / data handling:** <e.g. no PII logged; input bounds enforced>
- **Compatibility:** <platforms, versions>
- **Dependencies:** <none / list>

## 6. Open questions

List every unknown as a `NEEDS CLARIFICATION` line. The spec is not `approved`
while any remain.

- NEEDS CLARIFICATION: <question for a human>

## 7. Traceability hints

Where the verifier should expect to find evidence (modules, test files,
patterns). Optional but speeds up §⑦ Verify.
