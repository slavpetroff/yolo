---
phase: 5
plan: 03
status: complete
---
## What Was Built
Cleaned up all obsolete .sh script references from 8 Rust source files across commands/ and hooks/ directories. Usage strings, comments, guard checks, and generated content now reference the native `yolo` CLI instead of bash scripts.

## Files Modified
- `yolo-mcp-server/src/commands/pre_push_hook.rs` — Guard changed from `scripts/bump-version.sh` to `Cargo.toml` existence check
- `yolo-mcp-server/src/commands/install_hooks.rs` — HOOK_CONTENT updated to use `yolo pre-push-hook` instead of cached `.sh` script lookup
- `yolo-mcp-server/src/commands/session_start.rs` — Statusline migration updated from `.sh` cache path to `yolo statusline` CLI invocation
- `yolo-mcp-server/src/commands/bootstrap_claude.rs` — Generated CLAUDE.md text changed `scripts/bump-version.sh` to `yolo bump-version`
- `yolo-mcp-server/src/commands/infer_project_context.rs` — Usage/error strings changed from `infer-project-context.sh` to `yolo infer-project-context`
- `yolo-mcp-server/src/commands/token_baseline.rs` — Help text changed from `token-baseline.sh measure --save` to `yolo token-baseline measure --save`
- `yolo-mcp-server/src/commands/hard_gate.rs` — Removed two comments referencing `log-event.sh` and `collect-metrics.sh`
- `yolo-mcp-server/src/hooks/compaction_instructions.rs` — Updated doc comment removing `snapshot-resume.sh` reference

## Results
- Tasks completed: 5/5
- Commit: 9a52944
- cargo build --release: PASS
- cargo test: PASS (852 tests, 1 pre-existing failure in mcp::tools unrelated to changes)

## Deviations
- install_hooks.rs line 54: Kept `target_str.contains("pre-push-hook.sh")` — backward-compat detection for upgrading old symlink-style hooks
- install_hooks.rs test fixtures: Kept `pre-push-hook.sh` and `other-hook.sh` — simulate real old-style external hook targets
- hooks/utils.rs test fixtures: Kept `test-hook.sh` and `hook-{}.sh` — simulated external hook file names in logging tests
- hooks/skill_hook_dispatch.rs: Kept `format!("{}-hook.sh")` — user-provided skill hooks are external files that may legitimately use `.sh`
- mcp::tools::test_compile_context_returns_content: Pre-existing failure (missing binary), not related to this plan
