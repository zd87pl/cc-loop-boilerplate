# evals/ — prove the guardrails actually fire

A boilerplate that *claims* deterministic guardrails should prove them. `make eval`
runs `evals/run.sh`, a **deterministic, model-free** suite (safe + free in CI) that
asserts the loop does the right thing on fixtures:

| Case | Asserts |
| --- | --- |
| clean spec → completed | the happy path reaches all-gates-green |
| ambiguous spec → `needs_clarification` | a `NEEDS CLARIFICATION:` marker halts the loop |
| lint-failing spec → halts | `spec-lint` blocks before the model review |
| spec-lint accepts/rejects | the deterministic linter passes good specs, fails broken ones |
| secret write vetoed (exit 2) | the PreToolUse guard denies a credential |
| force-push vetoed (exit 2) | the PreToolUse guard denies history rewrites |
| protected-branch guard | `main` refused, a feature branch allowed |
| real python gate passes | a stack adapter executes real tests (not skipped) |

```sh
make eval        # or: bash evals/run.sh
```

## Fixtures

`cases/<name>/spec.md` hold the inputs. Each loop case runs `loop/run.sh --dry-run`
isolated from real `.loop/` state (via `LOOP_RUNS_DIR` / `LOOP_MEMORY_FILE`).

## Add a case

Add an assertion to `evals/run.sh` (and a fixture under `cases/` if it needs a
spec). Keep cases **deterministic** — no model calls — so the suite stays free and
reproducible in CI.

## Out of scope (live evals)

Model-dependent guardrails — ADR-conflict halts and drift detection — can't be
asserted deterministically. Run them with a live `make loop` against dedicated
fixtures; they are intentionally not part of this CI suite.
