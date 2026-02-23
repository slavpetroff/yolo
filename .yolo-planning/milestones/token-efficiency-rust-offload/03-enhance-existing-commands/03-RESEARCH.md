# Research: Phase 3 — Enhance Existing Rust Commands

## Findings

### 1. phase-detect (phase_detect.rs)
- **Current output:** 24 key-value pairs (NOT JSON), one per line. Includes `next_phase_state` with 4 values: `no_phases`, `needs_plan_and_execute`, `needs_execute`, `all_done`
- **No routing logic exists.** Mode routing is done entirely in vibe.md MD-side
- **`--suggest-route` needs:** Map `next_phase_state` + `project_exists` + `execution_state` to a suggested mode string (init/bootstrap/plan/execute/archive/resume)
- **Complexity: S.** Pure match logic on existing fields, no new I/O

### 2. resolve-model (resolve_model.rs)
- **Current output:** Bare model name string (e.g., "opus\n"). NOT JSON
- **Args:** `agent_name config_path profiles_path`
- **9 valid agents:** lead, dev, qa, scout, debugger, architect, docs, researcher, reviewer
- **Cost weights not in profiles file** — hard-coded in MD side only (opus=100, sonnet=20, haiku=2)
- **`--with-cost` needs:** Output JSON `{"model":"opus","cost_weight":100}` instead of bare text
- **`--all` needs:** Iterate all agents, return JSON object `{"lead":"opus","dev":"sonnet",...}`
- **Combined `--all --with-cost`:** `{"lead":{"model":"opus","cost_weight":100},...}`
- **Complexity: S.** Pure lookup iteration, no new I/O patterns
- **Risk:** Output format change is breaking — must be flag-gated. Cache keys must differ for different output modes

### 3. session-start (session_start.rs)
- **Signature: `execute_session_start(&cwd)`** — does NOT receive args (unlike other commands)
- **15 steps** currently, output as JSON with `hookSpecificOutput` + `structuredResult`
- **Already consolidates:** config migration, orphaned state, execution state reconciliation, hook installation, update check, statusline migration, cache cleanup, tmux watchdog, build_context (milestone/phase/next_action)
- **Could add:** progress data (from compile_progress), git state (from git_state), map staleness
- **Complexity: M.** Requires signature change to accept args, importing progress/git modules
- **Risk:** Performance — runs every session launch. Git commands add latency. Compaction debounce (step 2) can cause early return

### Flag Parsing Pattern (consistent across codebase)
```rust
let flag = args.iter().any(|a| a == "--flag-name");
```
No arg crate used. Boolean flags only.

### config-read Already Done
Enhancement #5 from audit (config-read helper) was already implemented in Phase 2.

## Relevant Patterns
- `bump_version.rs:239`: `args.iter().any(|a| a == "--verify")` — canonical flag pattern
- `lock_lite.rs:184`: `.filter(|a| !a.starts_with("--"))` — strip flags from positional args
- Router dispatches all three commands with `execute(&args, &cwd)` except session-start which uses `execute_session_start(&cwd)`

## Risks
1. **session-start signature change:** Currently doesn't receive args. Need to update router dispatch + function signature
2. **resolve-model cache collision:** `--all` and `--with-cost` outputs differ from bare model name. Use separate cache file naming
3. **session-start performance:** Adding git/progress calls increases startup latency. Consider making them conditional on a `--full` flag
4. **detect-stack --brownfield:** Low impact (audit #4). Only used in 1 place. Consider deferring to Phase 4

## Recommendations
- **Plan 03-01:** `phase-detect --suggest-route` + `resolve-model --with-cost --all` (3 flags on 2 commands, both S complexity, disjoint files)
- **Plan 03-02:** `session-start --with-progress --with-git` + `detect-stack --brownfield` + bats tests (M complexity, requires signature change)
- Both plans wave 1 (disjoint files: phase_detect.rs vs resolve_model.rs vs session_start.rs vs detect_stack.rs)
