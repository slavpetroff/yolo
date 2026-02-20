---
phase: 5
plan: 05
title: "End-to-end workflow verification and test suite"
wave: 2
depends_on: ["05-01", "05-02", "05-03"]
must_haves:
  - "`cargo build --release` succeeds with zero warnings"
  - "`cargo test` passes with zero failures"
  - "`yolo --help` lists all commands correctly"
  - "Full init → vibe → plan → execute → archive workflow path verified"
  - "No runtime dependency on any .sh script"
---

## Task 1: Build verification and binary health check

**Files:** `yolo-mcp-server/` (build), `~/.cargo/bin/yolo` (verify)

**Acceptance:** `cargo build --release` in yolo-mcp-server/ succeeds with 0 errors. `cargo clippy -- -D warnings` passes (no new warnings). `~/.cargo/bin/yolo --version` prints version. `~/.cargo/bin/yolo --help` lists all subcommands. Binary size noted for reference. No dynamic linking to any .sh script or bash dependency in the critical path.

## Task 2: Run full cargo test suite

**Files:** `yolo-mcp-server/` (test)

**Acceptance:** `cargo test` passes with 0 failures. All unit tests in commands/, hooks/, mcp/, telemetry/ pass. Test count reported. Any test that was checking for .sh file existence (e.g., pre_push_hook.rs guard) has been updated in Plan 03 and now passes. No test output contains "FAILED" or "panicked".

## Task 3: Verify hook dispatch workflow

**Files:** `hooks/hooks.json` (read), `~/.cargo/bin/yolo` (execute)

**Acceptance:** For each critical hook event, verify the Rust dispatcher handles it:
- `echo '{"tool_name":"Write","tool_input":{"file_path":"test.txt"}}' | yolo hook PreToolUse` returns valid JSON (exit 0)
- `echo '{}' | yolo hook SessionStart` returns valid JSON (exit 0)
- `echo '{}' | yolo hook Stop` returns valid JSON (exit 0)
- No hook invocation shells out to .sh scripts (verify via strace/dtruss or by confirming no bash subprocess in code)

## Task 4: Verify key CLI commands work end-to-end

**Files:** `~/.cargo/bin/yolo` (execute)

**Acceptance:** The following commands execute without error:
- `yolo help-output` — produces help text
- `yolo resolve-agent-model dev` — returns a model name
- `yolo resolve-agent-max-turns dev` — returns a number
- `yolo detect-stack .` — returns JSON with tech stack info
- `yolo bump-version --verify` — either succeeds or returns clear error (not "script not found")
- `yolo doctor-cleanup scan` — runs without bash dependency error
No command produces "scripts/" or ".sh" in its error output (indicating a missing bash script).

## Task 5: Final migration verification report and commit

**Files:** (none created — verification only)

**Acceptance:** Generate a verification summary confirming:
1. scripts/ directory: 0 .sh files remain (or directory removed)
2. commands/*.md: 0 references to scripts/ paths
3. Rust source: 0 runtime .sh dependencies
4. cargo build: PASS
5. cargo test: PASS (N tests, 0 failures)
6. Hook dispatch: PASS (all events handled by Rust)
7. CLI commands: PASS (all key commands functional)
If all pass, single atomic commit: `chore(cleanup): verify complete scripts-to-Rust migration`. If any fail, document failures as blockers for follow-up.
