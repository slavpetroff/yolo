---
phase: 02
plan: 02
title: "resolve-agent facade command"
wave: 1
depends_on: []
must_haves:
  - "Merges resolve-model and resolve-turns into single call"
  - "Returns JSON with model and turns fields"
  - "Supports --all flag for all 9 agents"
  - "Always includes defaults, caller never needs fallback"
  - "Cargo clippy clean"
---

# Plan 02: resolve-agent facade command

**Files modified:** `yolo-mcp-server/src/commands/resolve_agent.rs`

Implements `yolo resolve-agent <agent> <config> <profiles> [effort] [--all]` that merges resolve-model + resolve-turns into a single JSON response.

## Task 1: Create resolve_agent.rs with argument parsing

**Files:** `yolo-mcp-server/src/commands/resolve_agent.rs`

**What to do:**
1. Create `yolo-mcp-server/src/commands/resolve_agent.rs`
2. Add imports: `use std::path::Path; use std::time::Instant; use serde_json::json;`
3. Import: `use crate::commands::{resolve_model, resolve_turns};`
4. Implement `pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String>`
5. Parse positional args and flags:
   - Detect `--all` flag
   - Normal mode: `args[2]` = agent, `args[3]` = config_path, `args[4]` = profiles_path, optional `args[5]` = effort
   - `--all` mode: filter out flags, positionals are config_path and profiles_path
   - Detect optional effort arg (not starting with `--`)
6. Validate required arg count: normal needs 5 positionals, --all needs 4

## Task 2: Implement single-agent resolution

**Files:** `yolo-mcp-server/src/commands/resolve_agent.rs`

**What to do:**
1. For single agent mode, build args and call both:
   - `resolve_model::execute(&["yolo", "resolve-model", agent, config, profiles], cwd)` - parse plaintext output as model name
   - `resolve_turns::execute(&["yolo", "resolve-turns", agent, config, effort?], cwd)` - parse plaintext output as turns integer
2. Handle resolve_model returning JSON when --with-cost is used vs plaintext - strip whitespace and parse
3. Handle resolve_turns returning plaintext integer - strip whitespace and parse to u32
4. Build response:
```json
{
  "ok": true,
  "cmd": "resolve-agent",
  "delta": {
    "agent": agent_name,
    "model": model_string,
    "turns": turns_number
  },
  "elapsed_ms": elapsed
}
```

## Task 3: Implement --all mode

**Files:** `yolo-mcp-server/src/commands/resolve_agent.rs`

**What to do:**
1. Define the list of 9 agents: lead, dev, qa, scout, debugger, architect, docs, researcher, reviewer
2. For each agent, call resolve_model and resolve_turns as in Task 2
3. Build response:
```json
{
  "ok": true,
  "cmd": "resolve-agent",
  "delta": {
    "agents": {
      "lead": {"model": "opus", "turns": 50},
      "dev": {"model": "opus", "turns": 75},
      ...
    },
    "count": 9
  },
  "elapsed_ms": elapsed
}
```
4. If any individual agent resolution fails, set ok=false and include error in that agent's entry

## Task 4: Add unit tests

**Files:** `yolo-mcp-server/src/commands/resolve_agent.rs`

**What to do:**
1. Add `#[cfg(test)] mod tests` at bottom
2. Helper functions: `write_config(dir, content)` and `write_profiles(dir)` following resolve_model.rs test pattern
3. Test: single agent returns `{ok: true, delta: {agent, model, turns}}`
4. Test: --all returns all 9 agents with model+turns
5. Test: missing args returns Err with usage
6. Test: invalid agent name returns Err
7. Test: response always has `cmd: "resolve-agent"` and `elapsed_ms`
8. Test: effort parameter affects turns value (thorough vs balanced)

**Commit:** `feat(yolo): add resolve-agent facade command`
