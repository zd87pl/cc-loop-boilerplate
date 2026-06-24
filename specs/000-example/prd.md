# PRD: Duration-string parser

| Field        | Value       |
| ------------ | ----------- |
| PRD ID       | PRD-000     |
| Status       | approved    |
| Owner        | platform-dx |
| Related SPEC | SPEC-000    |
| Last updated | 2026-06-24  |

## 1. Problem

Internal tools each re-implement "parse `1h30m` into seconds," and they disagree
on edge cases (empty input, unknown units, overflow). Inconsistent parsing
causes surprising timeouts and retention bugs. We want one canonical, tiny,
dependency-free parser teams can copy or vendor.

## 2. Goals

- Identical duration semantics across tools.
- Trivial to adopt: one pure function, no dependencies.
- Explicit, predictable errors instead of silent truncation.

## 3. Non-goals

- Fractional values, natural-language durations, or calendar units.
- Formatting seconds back into a duration string (a separate concern).

## 4. Users / personas

- **Tool author**: needs a drop-in parser with documented edge cases.
- **Operator**: types durations into configs and expects consistent behavior.

## 5. User stories

- As a tool author, I want a pure `parse_duration` function, so that I get the
  same result everywhere without pulling a dependency.
- As an operator, I want a clear error on a typo like `5x`, so that I notice
  before it ships.

## 6. Success metrics

- 100% of the SPEC acceptance criteria covered by passing tests.
- Zero external dependencies in the parser module.

## 7. Milestones / scope

- M1: core `parse_duration` + tests (this example).
- M2 (future): optional CLI wrapper.

## 8. Risks, dependencies, open questions

- Risk: integer overflow on absurd inputs → mitigated by REQ-006.
- Dependency: none.
- Open questions: none.
