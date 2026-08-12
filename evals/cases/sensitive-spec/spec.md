# SPEC: Password rotation interval (eval fixture)

This fixture exists to prove risk calibration: the word "password" classifies
it `sensitive` in the dry-run stub, which must make the security pass and the
coverage bar MANDATORY (skip counts as red) and raise the coverage threshold.

| Field       | Value    |
| ----------- | -------- |
| Spec ID     | SPEC-901 |
| Status      | approved |
| Owner       | evals    |

## Requirements (EARS)

| ID      | Type       | Requirement                                                            | Acceptance check |
| ------- | ---------- | ---------------------------------------------------------------------- | ---------------- |
| REQ-001 | Ubiquitous | The system shall store the password rotation interval in whole days.   | AC-1             |
| REQ-002 | Unwanted   | If the interval is zero or negative, then the system shall reject it.  | AC-2             |

## Acceptance criteria (concrete oracles)

| #    | Input | Expected result       | Covers  |
| ---- | ----- | --------------------- | ------- |
| AC-1 | `30`  | stored; returns `30`  | REQ-001 |
| AC-2 | `0`   | error: invalid value  | REQ-002 |
