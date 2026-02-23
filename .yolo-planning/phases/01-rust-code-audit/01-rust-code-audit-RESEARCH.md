# Research: Phase 1 — Rust Code Audit

## Findings

### Critical (1)
- **Cargo.toml:23-29** — Both `yolo` and `yolo-mcp-server` bin targets reference same `src/main.rs`. Compiler warning, potential binary confusion.

### High (4)
- **src/hooks/map_staleness.rs:14** — `input` parameter unused in `handle()`
- **src/commands/session_start.rs:796** — `cwd` parameter unused in `build_context()`
- **src/commands/state_updater.rs:255** — `phase_dir` parameter unused in `update_model_profile()`
- **src/hooks/agent_health.rs:150** — `planning_dir` parameter unused in `orphan_recovery()`

### Medium (8)
- **src/cli/router.rs:5** — Unused import `Ordering`
- **src/commands/hard_gate.rs:3** — Unused import `PathBuf`
- **src/commands/list_todos.rs:4** — Unused import `Datelike`
- **src/commands/token_baseline.rs:3** — Unused import `DateTime`
- **src/commands/resolve_model.rs:64** — Dead method `as_str()`
- **src/commands/commit_lint.rs:88** — Dead function `validate_subject()`
- **src/commands/bootstrap_claude.rs:161** — Assigned `rows_inserted` never read
- **src/commands/list_todos.rs:150** — Unnecessary `mut` on `text`

### Code Quality (~245 clippy warnings)
- **245x nested if** — collapsible `if let + if` patterns across most command files
- **16x manual prefix strip** — Should use `strip_prefix()` instead of `trim_start_matches()`
- **6x unnecessary `.to_vec()`** — router.rs and state_updater.rs pass slices as vecs
- **5x `push_str("\n")`** — Should be `push('\n')` for single char
- **3x excessive fn args (8-9 params)** — telemetry/db.rs record functions
- **2x missing Default trait** — mcp/retry.rs, mcp/tools.rs have `new()` but no `Default`
- **2x useless vec construction** — session_start.rs lines 219, 247
- **80+ other** — regex in loops, consecutive replace, style issues

## Relevant Patterns
- Error handling is consistent: `Result<T, String>` throughout
- No `unwrap()`, `panic!()`, or `expect()` in production code (strong)
- 30 `unsafe` blocks all properly justified (signal handling, PID checks, uid)
- 79 command modules, 24 hook modules, 5 MCP modules

## Risks
- The 245 nested-if refactors touch nearly every file — high merge conflict risk if done as one task
- Unused parameters may be intentional API surface for future use (verify before removing)
- Cargo.toml dual-target is the only truly critical issue

## Recommendations
- Split audit into: (1) critical/high fixes, (2) dead code removal, (3) clippy bulk fixes, (4) telemetry refactor
- Run `cargo clippy` as verification after each plan
- Keep plans to disjoint file sets for parallel dev execution
