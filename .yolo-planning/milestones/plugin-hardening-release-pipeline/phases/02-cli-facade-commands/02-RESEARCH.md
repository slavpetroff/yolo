# Phase 2: CLI Facade Commands — Research

## Findings

### QA Commands (5 total)
All share `pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String>` signature.
- `verify-plan-completion`: args = summary_path, plan_path. 5 checks (frontmatter, task_count, completion, commit_hashes, body_sections).
- `commit-lint`: args = commit_range. Regex validates conventional commit format.
- `check-regression`: args = phase_dir. Counts Rust tests + bats files. Always ok=true.
- `diff-against-plan`: args = summary_path. Compares declared vs actual files from git show.
- `validate-requirements`: args = plan_path, phase_dir. Keyword search in summaries + git log.

All return JSON with `ok`, `cmd`, `fixable_by` fields. Exit code 0=pass, 1=fail.

### resolve-model
- Single mode: `resolve-model <agent> <config> <profiles>` → plaintext model name
- All mode: `resolve-model --all <config> <profiles>` → JSON {agent: model}
- `--with-cost` flag adds cost_weight field
- Resolution: config.model_profile → profiles[profile][agent] → override
- Cache: `/tmp/yolo-model-{agent}-{mtime}-{hash}`

### resolve-turns
- `resolve-turns <agent> <config> [effort]` → plaintext integer
- Default base turns: scout=15, qa=25, architect=30, debugger=80, lead=50, dev=75, docs=30
- Multipliers: thorough=1.5x, balanced=1.0x, fast=0.8x, turbo=0.6x
- Config override: `agent_max_turns[agent]` (scalar or per-effort object)

### Bootstrap commands (4 subcommands)
All under `yolo bootstrap <subcommand>`:
- `project`: output_path, name, description, [core_value] → PROJECT.md
- `requirements`: output_path, discovery_json, [research_file] → REQUIREMENTS.md
- `roadmap`: output_path, project_name, phases_json → ROADMAP.md + phase dirs
- `state`: output_path, project_name, milestone_name, phase_count → STATE.md

Sequential dependency: project → requirements → roadmap → state (each uses prior output).

### Router pattern (router.rs, 946 lines)
1. Add enum variant in `Command` (lines 8-84)
2. Add `from_arg()` case (lines 87-165)
3. Add `name()` case (lines 168-245)
4. Add dispatch arm in `run_cli()` (lines 349-824)
5. Import module in use statement (line 5)
6. Declare module in mod.rs

### Execute-protocol call sites
- resolve-model + resolve-turns: 6 pairs across Reviewer (line 86), Architect (207), Dev (570), QA (758), Lead, Researcher
- QA suite: 5 sequential calls at lines 800-846
- Bootstrap: 4 calls in bootstrap.md lines 17-58
- Release: bump + changelog + commit + tag + push in archive.md lines 55-95

## Relevant Patterns

- All commands return `Result<(String, i32), String>` — String is JSON, i32 is exit code
- JSON response always includes `ok`, `cmd`, `elapsed_ms`
- Delta fields carry the variable payload
- Bootstrap uses subcommand routing: `yolo bootstrap project|requirements|roadmap|state`
- resolve-model already has `--all` flag for batch resolution

## Risks

1. **resolve-agent merging resolve-model + resolve-turns**: Different output formats (plaintext vs JSON). Need consistent JSON for merged command.
2. **qa-suite parallel execution**: Commands are independent but share cwd. Safe to call concurrently in Rust (each reads different files).
3. **release-suite git operations**: Must be sequential (commit before tag before push). Cannot parallelize.
4. **bootstrap-all sequential deps**: requirements depends on project existing, roadmap depends on requirements. Must execute in order.
5. **Instruction updates**: execute-protocol SKILL.md is 74KB. Careful replacement of bash patterns needed.

## Recommendations

- 4 facade commands (not 5): resolve-agent merges resolve-model + resolve-turns with --all support
- qa-suite: call all 5 internally, aggregate into unified JSON with per-check results
- release-suite: sequential steps, --dry-run computes all but writes nothing, report+stop on failure
- bootstrap-all: sequential with dependency chain, returns aggregated results
- resolve-agent: single agent returns JSON `{model, turns}`, --all returns `{agent: {model, turns}}` for all 9 agents
- All facades follow existing JSON schema: `{ok, cmd, delta, elapsed_ms}`
- Add Cargo.toml + Cargo.lock to release-suite git add
