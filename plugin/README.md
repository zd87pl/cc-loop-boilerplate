# Distribution — installing the spec-loop as a Claude Code plugin

This directory documents **org-wide distribution**. It intentionally does not
contain the plugin manifest.

> **Manifest location (flagged deviation from the build manifest).** The build
> spec's file manifest put the plugin manifest under `plugin/`. Claude Code
> **requires** the manifest at `.claude-plugin/plugin.json` at the plugin root,
> so the authoritative files live there instead:
>
> - `.claude-plugin/plugin.json` — the plugin manifest (repo root **is** the
>   plugin root)
> - `.claude-plugin/marketplace.json` — a one-plugin marketplace for this repo
>
> The manifest points its component paths at the existing `./.claude/skills`,
> `./.claude/agents`, and `./.claude/hooks/hooks.json`, so there is a **single
> source of truth** — the same files serve both in-repo use and plugin install,
> with no duplicated, drift-prone copies.

## What the plugin provides

Installing the plugin gives every engineer, in any repo:

- the seven stage slash commands (`/spec-init`, `/plan`, `/tasks`,
  `/implement`, `/review`, `/fix`, `/verify`) — namespaced as
  `/spec-loop:<stage>`,
- the five subagents (`architect`, `implementer`, `reviewer`,
  `security-auditor`, `verifier`),
- the deterministic hooks (secret-scan + destructive-command veto, per-file
  formatter, Stop-gate).

## Install (marketplace)

```sh
# Add this repo as a marketplace, then install the plugin from it:
/plugin marketplace add zd87pl/cc-loop-boilerplate
/plugin install spec-loop@cc-loop

# Update / remove later:
/plugin marketplace update
/plugin uninstall spec-loop@cc-loop
```

`scripts/install.sh` checks prerequisites and prints these commands; it does not
mutate global state itself.

## Two ways to use this boilerplate

| Mode | You get | Best for |
| --- | --- | --- |
| **Plugin install** | slash commands + subagents + guardrail hooks in any repo | giving 250 engineers the stages and guardrails everywhere |
| **Vendor the repo** | the above **plus** the headless orchestrator (`loop/`, `adapters/`, `make loop`) and the spec scaffolding | running the full closed loop end-to-end in a project |

The headless controller (`loop/run.sh`) is a repo-level tool: vendor the
boilerplate (or copy `loop/`, `adapters/`, `specs/`) into the target repo to run
`make loop`.

### Driving namespaced commands from the controller

When the stages are installed as a plugin, their commands are namespaced
(`/spec-loop:spec-init`). Point the controller at them by setting `skill_prefix`
in `.loop.yml`:

```yaml
skill_prefix: "spec-loop:"   # default "" expects bare /spec-init (vendored mode)
```
