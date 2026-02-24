# Phase 2: CLI Facade Commands & LLM Hop Reduction — Context

Gathered: 2026-02-24
Calibration: architect

## Phase Boundary

5 batch facade commands that reduce LLM round-trips by 50-65% for common workflows. Each facade orchestrates multiple existing CLI commands into a single call returning rich JSON. Instructions updated to use facades exclusively (no fallback to individual calls).

## Decisions

### qa-suite aggregation strategy

- Run ALL 5 checks (verify-plan-completion, commit-lint, check-regression, diff-against-plan, validate-requirements) in parallel, return unified JSON report
- Per-check results with status, evidence, fixable_by classification, plus overall pass/fail
- Individual QA commands COEXIST alongside qa-suite (backward compat, debugging)
- Execute-protocol updated to call qa-suite as primary path

### release-suite scope and safety

- `--dry-run` = full preview with NO side effects (compute version, show changelog edit, list files, show commit message + tag — write nothing)
- Partial failure = report and STOP (no automatic rollback). User decides whether to retry, reset, or fix manually
- Auto-include Cargo.toml and Cargo.lock (if changed) in release commit's git add, alongside VERSION, plugin.json, marketplace.json, CHANGELOG.md
- Gated by `auto_push` config for the push step

### resolve-agent vs resolve-models-all overlap

- MERGE into single `resolve-agent` command with `--all` flag
- `yolo resolve-agent dev ...` returns `{model, turns}` for one agent
- `yolo resolve-agent --all ...` returns `{agent: {model, turns}}` for all agents
- Always return complete data with defaults applied — caller NEVER needs fallback logic
- Removes need for separate `resolve-models-all` command (4 facades instead of 5)

### Instruction update strategy

- Facade-first, REMOVE old sequential patterns from instructions
- Update execute-protocol SKILL.md, plan.md, archive.md, and any agent definitions
- Clean break — instructions are authoritative, not backward-compat libraries
- Individual commands still exist in router but instructions don't reference them for orchestration

### Open (Claude's discretion)

- bootstrap-all: orchestrates 6-7 sequential bootstrap calls (project, requirements, roadmap, state, claude, planning-git) into single entry point
- Error response format: all facades use consistent JSON schema with `ok`, `cmd`, `delta`, `elapsed_ms` fields (matching existing command pattern)
- Facades registered in router.rs as new Command enum variants (QaSuite, ReleasesSuite, ResolveAgent with --all, BootstrapAll)

## Deferred Ideas

None — all facade candidates scoped within Phase 2.
