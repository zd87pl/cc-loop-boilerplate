# SPEC: Duration-string parser

| Field        | Value       |
| ------------ | ----------- |
| Spec ID      | SPEC-000    |
| Status       | approved    |
| Owner        | platform-dx |
| Related PRD  | prd.md      |
| Related ADRs | adr-001.md  |
| Last updated | 2026-06-24  |

## 1. Context

Many internal tools accept human-friendly durations (timeouts, retention
windows, cache TTLs) such as `1h30m`. We need one small, dependency-free,
pure-function parser that turns such strings into a whole number of seconds, so
every tool parses durations identically. This spec is also the worked example
that exercises the spec-driven loop end to end.

## 2. Scope

**In scope**

- A pure library function `parse_duration(input) -> integer seconds`.
- A thin optional CLI wrapper around that function.

**Out of scope**

- Fractional/decimal values (e.g. `1.5h`), locale-aware words ("two hours").
- Calendar arithmetic (months, years — ambiguous lengths).

## 3. Requirements (EARS)

| ID      | Type         | Requirement                                                                                                                            | Acceptance check |
| ------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| REQ-001 | Ubiquitous   | The system shall parse a duration string composed of one or more `<integer><unit>` segments into a total of whole seconds.             | AC-1, AC-7       |
| REQ-002 | Ubiquitous   | The system shall support units `w`,`d`,`h`,`m`,`s` meaning 604800, 86400, 3600, 60, 1 seconds respectively.                            | AC-3, AC-4       |
| REQ-003 | Event-driven | When the input contains multiple segments, the system shall return the sum of their second-values.                                     | AC-1, AC-7       |
| REQ-004 | Unwanted     | If the input is empty or contains no valid segment, then the system shall return an "invalid input" error.                             | AC-5             |
| REQ-005 | Unwanted     | If the input contains a unit other than `w`,`d`,`h`,`m`,`s`, then the system shall return an error naming the bad unit.                | AC-6             |
| REQ-006 | Unwanted     | If a computed total exceeds the platform's safe integer range, then the system shall return an "overflow" error.                       | AC-8             |
| REQ-007 | State-driven | While parsing, the system shall reject any sign or whitespace inside a segment (no negative or spaced values).                         | AC-9             |
| REQ-008 | Optional     | Where the CLI wrapper is built, the system shall print the total to stdout and exit 0, or print the error to stderr and exit non-zero. | AC-10            |

## 4. Acceptance criteria (concrete oracles)

| #     | Input            | Expected result         | Covers           |
| ----- | ---------------- | ----------------------- | ---------------- |
| AC-1  | `1h30m`          | `5400`                  | REQ-001, REQ-003 |
| AC-2  | `90s`            | `90`                    | REQ-001          |
| AC-3  | `2d`             | `172800`                | REQ-002          |
| AC-4  | `1w`             | `604800`                | REQ-002          |
| AC-7  | `1w2d3h4m5s`     | `788645`                | REQ-001, REQ-003 |
| AC-5  | `` (empty)       | error: invalid input    | REQ-004          |
| AC-6  | `5x`             | error: unknown unit `x` | REQ-005          |
| AC-8  | `9999999999999w` | error: overflow         | REQ-006          |
| AC-9  | `-1h` / `1 h`    | error: invalid input    | REQ-007          |
| AC-10 | CLI `1h30m`      | prints `5400`, exit 0   | REQ-008          |

## 5. Non-functional requirements

- **Performance:** single pass, O(n) over input length; no I/O in the core
  function.
- **Purity:** the core function has no side effects and no global state.
- **Dependencies:** none beyond the language's standard library.
- **Security / data handling:** input length is bounded; no input is logged.

## 6. Open questions

_None — this example spec is fully specified so the self-test can reach
all-gates-green. (A real spec lists every unknown as a `NEEDS CLARIFICATION`
line and is not `approved` while any remain.)_

## 7. Traceability hints

Expect the parser in a single module named like `duration` (e.g.
`duration.<ext>`) with a sibling test file asserting every AC row above.
