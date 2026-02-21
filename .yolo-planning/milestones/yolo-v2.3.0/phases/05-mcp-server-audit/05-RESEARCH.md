# Phase 05 Research: MCP Server Audit & Fixes

## Findings

All 8 findings from the audit report have been verified against the actual source code.

### F1: compile_context Tool Bloat — CONFIRMED (HIGH)
**File:** `yolo-mcp-server/src/mcp/tools.rs:22-58`
- Blindly reads 5 files (ARCHITECTURE.md, STACK.md, CONVENTIONS.md, ROADMAP.md, REQUIREMENTS.md) and concatenates them
- Appends raw `git diff HEAD` output literally
- `role` parameter is declared in the tool schema but **completely ignored** in implementation
- `phase` parameter is parsed (line 22) but **never used for filtering**
- Every call dumps the entire project state regardless of what the agent needs

### F2: delta_files Aggressive Fallback — CONFIRMED (MEDIUM)
**File:** `yolo-mcp-server/src/commands/delta_files.rs:60-80`
- If no uncommitted/staged changes, falls back to diff since last git tag (line 61-72)
- Then falls back to `HEAD~5..HEAD` (line 75-80)
- Can return hundreds of irrelevant historical file paths

### F3: Synchronous MCP Server Request Loop — CONFIRMED (HIGH)
**File:** `yolo-mcp-server/src/mcp/server.rs:16-50`
- `handle_request(req, ...).await` is called **inline** in the read loop (line 24)
- No `tokio::spawn`, no mpsc channel for concurrent handling
- If compile_context takes 5s, the server is blocked for 5s

### F4: Async Thread Blocking — CONFIRMED (HIGH)
**File:** `yolo-mcp-server/src/mcp/tools.rs:43,106`
- `std::process::Command::new("git")` on line 43 (compile_context)
- `std::process::Command::new("npm")` on line 106 (run_test_suite)
- Both use synchronous `std::process::Command` inside async context, blocking tokio worker threads

### F5: Redundant Phase Parsing — CONFIRMED (LOW)
**File:** `yolo-mcp-server/src/commands/token_baseline.rs:60,68`
- `phase.parse::<i64>().ok()` evaluated inside inner loops over `&events` (line 60) and `&metrics` (line 68)
- The `phase` string doesn't change in the inner loop — should be cached once per outer iteration
- Also loads entire JSONL files into `Vec<Value>` instead of streaming (line 6-16)

### F6: Hardcoded npm Test Runner — CONFIRMED (MEDIUM)
**File:** `yolo-mcp-server/src/mcp/tools.rs:106-108`
- `Command::new("npm").arg("test").arg(test_path)` — hardcoded npm
- Won't work for cargo, pytest, bats, or any non-npm project
- No output streaming — waits for entire process, dumps all output at once

### F7: Telemetry Data Loss — CONFIRMED (MEDIUM)
**File:** `yolo-mcp-server/src/mcp/server.rs:173-181`
- `0, 0` hardcoded for `input_length` and `output_length`
- The actual sizes are readily computable from params/result JSON serialization
- DB schema supports these fields (`input_length INTEGER`, `output_length INTEGER`)

### F8: Brittle String Normalization — CONFIRMED (LOW)
**File:** `yolo-mcp-server/src/commands/bootstrap_claude.rs:84-98`
- O(N*M) nested loop: for each `drow` in `data_rows`, iterates all `state_content.lines()`
- `normalized_line` recomputed for every (drow, line) pair
- Fix: pre-normalize state lines into a `HashSet` for O(N+M) lookup

## Relevant Patterns

- MCP server uses tokio async runtime with `full` features
- `tokio::process::Command` is available via tokio dependency (already in Cargo.toml)
- Tool schema declares `phase` and `role` params — implementation should honor them
- Test suite has comprehensive unit tests for all tools — changes need test updates
- The `role` parameter value should map to which files are relevant (e.g., "dev" needs CONVENTIONS, "lead" needs ROADMAP+REQUIREMENTS, "architect" needs ARCHITECTURE)

## Risks

1. **Test breakage:** 11 existing tests in tools.rs, 7 in server.rs — all must still pass
2. **MCP protocol compat:** Concurrent request handling must preserve JSON-RPC response ordering
3. **Behavioral change:** Selective context means agents get less data — must ensure the right data reaches the right role
4. **delta_files fallback removal:** Some agents may rely on the "last 5 commits" fallback for recently-landed changes

## Recommendations

1. **Priority order:** F3+F4 (async fixes) → F1 (context filtering) → F7 (telemetry) → F6 (test runner) → F2 (delta fallback) → F5+F8 (optimizations)
2. F3 (concurrent server) and F4 (async process) should be done together — they're tightly coupled
3. F1 (compile_context) is the highest-impact token savings — filter by role+phase
4. F5 and F8 are low-risk optimizations that can be batched
