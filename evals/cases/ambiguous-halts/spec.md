# SPEC: Ambiguous fixture (must halt)

| Field   | Value       |
| ------- | ----------- |
| Spec ID | SPEC-EVAL-1 |
| Status  | draft       |

## 3. Requirements

| ID      | Type       | Requirement                                    | Acceptance check |
| ------- | ---------- | ---------------------------------------------- | ---------------- |
| REQ-001 | Ubiquitous | The system shall do something underspecified.  | AC-1             |

## 4. Acceptance criteria

| #    | Input | Expected | Covers  |
| ---- | ----- | -------- | ------- |
| AC-1 | a     | b        | REQ-001 |

## 6. Open questions

- NEEDS CLARIFICATION: what should happen when the input is negative? (This
  marker must make the loop halt with status `needs_clarification`.)
