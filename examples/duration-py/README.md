# Example: duration parser (Python) — SPEC-000 implemented for real

This is the worked example with **real code and real tests**, so the loop's
gates actually execute (not skip) and the verifier has something concrete to
trace. It implements [`specs/000-example/spec.md`](../../specs/000-example/spec.md).

```sh
# From this directory — the python adapter runs the suite as a real gate:
bash ../../adapters/stacks/python.sh test       # python3 -m unittest discover
python3 duration.py 1h30m                        # -> 5400
```

`adapters/detect.sh` recognizes this dir as a Python stack (via `pyproject.toml`),
so `make gates` / the loop run `test` here for real.

## Traceability matrix (REQ ⇄ code ⇄ test)

| Requirement | Implemented by (`duration.py`)            | Proven by (`test_duration.py`)        |
| ----------- | ----------------------------------------- | ------------------------------------- |
| REQ-001     | `parse_duration` (segment scan + sum)     | `test_ac1_hours_minutes`, `test_ac2_seconds` |
| REQ-002     | `_UNITS` table                            | `test_ac3_days`, `test_ac4_weeks`     |
| REQ-003     | accumulation across segments              | `test_ac1_hours_minutes`, `test_ac7_all_units` |
| REQ-004     | empty / no-segment → `DurationError`      | `test_ac5_empty_is_error`             |
| REQ-005     | unknown-unit detection (`unknown unit …`) | `test_ac6_unknown_unit_names_it`      |
| REQ-006     | `MAX_SAFE_SECONDS` overflow check         | `test_ac8_overflow`                   |
| REQ-007     | gap detection (sign/space rejected)       | `test_ac9_sign_or_space_rejected`     |
| REQ-008     | `_main` CLI wrapper                        | `test_ac10_cli`                       |

Every requirement is COVERED: real code + a passing test. This is what the
`/verify` stage produces automatically on a live run; here it is committed so the
matrix is inspectable without spending tokens.
