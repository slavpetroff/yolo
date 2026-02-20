---
phase: 1
plan: 01
title: "Migrate resolve-agent-model.sh and resolve-agent-max-turns.sh to Rust CLI"
wave: 1
depends_on: []
must_haves:
  - "`yolo resolve-model <agent> <config-path> <profiles-path>` produces identical output to resolve-agent-model.sh"
  - "`yolo resolve-turns <agent> <config-path> [effort]` produces identical output to resolve-agent-max-turns.sh"
  - "Both commands registered in CLI router with proper error handling"
  - "Unit tests covering valid agents, overrides, effort normalization, and edge cases"
---

## Task 1: Implement resolve-model command

**Files:** `yolo-mcp-server/src/commands/resolve_model.rs`

**Acceptance:** `yolo resolve-model lead .yolo-planning/config.json config/model-profiles.json` outputs the correct model string (opus/sonnet/haiku) matching the bash script behavior.

Implement `pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String>` following the existing pattern in `detect_stack.rs`. The command must:

1. Parse 3 required args: agent-name, config-path, profiles-path
2. Validate agent name against: lead, dev, qa, scout, debugger, architect, docs
3. Read `model_profile` from config.json (default "quality")
4. Validate profile exists in model-profiles.json
5. Look up `profile.agent` in model-profiles.json
6. Check `model_overrides.{agent}` in config.json for per-agent override
7. Validate final model is opus/sonnet/haiku
8. Output model string + newline on stdout

Include session-level caching using file mtime (matching bash behavior with `/tmp/yolo-model-{agent}-{mtime}`). Include unit tests for: valid agent, invalid agent, missing config, override precedence, invalid profile.

## Task 2: Implement resolve-turns command

**Files:** `yolo-mcp-server/src/commands/resolve_turns.rs`

**Acceptance:** `yolo resolve-turns dev .yolo-planning/config.json balanced` outputs the correct integer turn count matching the bash script behavior.

Implement the full turns resolution logic:

1. Parse args: agent-name (required), config-path (required), effort (optional)
2. Validate agent name (same set as resolve-model)
3. Default base turns per agent: scout=15, qa=25, architect=30, debugger=80, lead=50, dev=75, docs=30
4. Effort normalization: accept thorough/balanced/fast/turbo AND legacy aliases high/medium/low. Fallback chain: explicit arg -> config.effort -> "balanced"
5. Effort multipliers: thorough=1.5x, balanced=1.0x, fast=0.8x, turbo=0.6x (integer math with rounding)
6. Config lookup: check `agent_max_turns.{agent}` then `max_turns.{agent}` in config.json
7. Handle object mode (per-effort values without multiplier) vs scalar mode (apply multiplier)
8. Handle false/FALSE/False/0 as "unlimited" (output 0)
9. Minimum 1 turn (unless explicitly 0/false)

Include unit tests for: default turns, effort scaling, object mode, false=unlimited, invalid agent.

## Task 3: Register both commands in CLI router and module registry

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`

**Acceptance:** `yolo resolve-model` and `yolo resolve-turns` are routable from the CLI binary. Running with no args shows usage error. `cargo test` passes.

1. Add `pub mod resolve_model;` and `pub mod resolve_turns;` to `commands/mod.rs`
2. Add import in router.rs: `use crate::commands::{..., resolve_model, resolve_turns};`
3. Add match arms in `run_cli`:
   - `"resolve-model"` -> `resolve_model::execute(&args, &cwd)`
   - `"resolve-turns"` -> `resolve_turns::execute(&args, &cwd)`
4. Run `cargo test` and `cargo build` to verify everything compiles and tests pass

## Task 4: Add integration tests comparing Rust output to expected values

**Files:** `yolo-mcp-server/src/commands/resolve_model.rs` (append tests), `yolo-mcp-server/src/commands/resolve_turns.rs` (append tests)

**Acceptance:** Tests cover all edge cases from the original bash scripts. `cargo test` passes with 0 failures.

Add comprehensive tests:
- resolve-model: quality/balanced/budget profiles, all 7 agents, override takes precedence, missing config error, invalid agent error, invalid profile error
- resolve-turns: all agents default values, thorough multiplier (1.5x with rounding), turbo multiplier (0.6x), object mode (per-effort), false=0 output, empty effort falls back to config, empty config effort falls back to balanced, minimum 1 clamp
