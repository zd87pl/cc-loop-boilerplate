# Onboarding — your first loop in ~5 minutes

This walks you from clone to a completed (dry) run, then to running the loop on
your own feature. No cost until you opt in.

## 0. Prerequisites (1 min)

```sh
make doctor
```

You need `claude`, `git`, `jq`, `yq`, and `bash`. `gh` is optional (the loop
prints manual PR instructions without it). A secret scanner (`gitleaks` /
`trufflehog`) is optional — the guard falls back to a builtin scan. Fix any ✗
items before continuing.

## 1. Run the example loop — dry, no model, no cost (2 min)

```sh
make selftest
```

This runs the full state machine against `specs/000-example/` (a small
"duration-string parser" feature). It walks all seven stages, exercises one
review↔fix cycle, runs the real quality gates (which skip — the boilerplate has
no app stack), and writes artifacts under `.loop/runs/<id>/`.

Open the report:

```sh
cat "$(ls -dt .loop/runs/run-* | head -1)/report.md"
```

You'll see a reproducibility header, the stage table, gate results, cost (\$0 in
dry run), and a **traceability matrix** with every `REQ-NNN` from the spec.

## 2. What just happened (1 min)

- The controller created an isolated feature-branch name (it refuses protected
  branches) and recorded state to `state.json` (schema in
  `loop/state.schema.json`).
- Each stage emitted a structured event to `events.jsonl`.
- The human gates (`spec`, `premerge`) auto-approved because dry-run/`--yes`.
- The verifier produced `traceability.md`, mapping each requirement to its
  acceptance evidence.

Inspect the raw stream if you like:

```sh
cat "$(ls -dt .loop/runs/run-* | head -1)/events.jsonl" | jq -c .
```

## 3. Run on your own feature (1 min to start)

```sh
make new-spec SLUG=001-my-feature      # scaffold from templates
$EDITOR specs/001-my-feature/spec.md   # write EARS requirements + acceptance criteria
make dry-run SPEC=specs/001-my-feature # validate the pipeline without spend
make loop    SPEC=specs/001-my-feature # run for real (uses `claude`; opens a draft PR)
```

Write each requirement in **EARS** form (see `specs/templates/spec.md`) and mark
every unknown as `NEEDS CLARIFICATION:` — the loop will stop and ask rather than
guess.

## 4. Make the gates real for your stack

In a polyglot/app repo, `make doctor` will detect your stack(s) and the gates run
through `adapters/stacks/<lang>.sh`. If your repo is unusual, override any verb
in `.loop.yml`:

```yaml
gates:
  test: "pnpm test --filter changed"
  securityscan: "semgrep --config auto"
```

## 5. Knobs you'll actually touch

All in `.loop.yml`: `max_iterations`, `cost_ceiling_usd`, `require_human_gates`,
`models` (per-stage `opus`/`sonnet`/`haiku`), `branch_prefix`,
`protected_branches`, `open_pr`.

## Troubleshooting

- **`.claude/settings.json is invalid JSON`** in `make doctor` → it would be
  silently ignored (disabling hooks). Fix the JSON.
- **Human gate hangs in CI** → pass `--yes` (or set `require_human_gates: []`):
  `bash loop/run.sh --spec <dir> --yes`.
- **No PR opened** → `gh` is missing or unauthenticated; the loop prints the
  manual `git push` + PR steps. It never auto-merges.
- **Stop hook makes interactive turns slow** → set `LOOP_STOP_GATE=0` to disable
  the on-stop gate suite (the loop still runs gates between stages).
- **macOS / WSL2** → all scripts are POSIX-friendly bash. On WSL2, run inside the
  Linux filesystem (not `/mnt/c`) for sane file watching and speed.

## Resuming

Runs are resumable: every run has an id under `.loop/runs/`. Re-enter with
`bash loop/run.sh --resume <run-id>` to skip already-passed stages.
