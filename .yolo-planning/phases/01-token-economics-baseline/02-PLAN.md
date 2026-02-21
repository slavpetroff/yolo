---
phase: 1
plan: 2
title: "Build yolo report token-economics dashboard"
wave: 1
depends_on: []
must_haves:
  - "yolo report shows per-agent token spend (input/output/cache_read/cache_write) per phase"
  - "Cache hit rate percentage calculated from telemetry data"
  - "Waste metric: tokens loaded but never referenced in output (heuristic)"
  - "ROI metric: tokens spent per commit/task delivered"
  - "Dashboard renders in terminal with YOLO brand formatting"
---

# Plan 2: Build Token Economics Dashboard (`yolo report token-economics`)

## Goal
Create a new `yolo report token-economics` subcommand that reads from both the SQLite telemetry DB and JSONL event/metrics files to render a branded terminal dashboard showing per-agent cost breakdown, cache hit rates, waste identification, and ROI metrics.

## Tasks

### Task 1: Create `token_economics_report.rs` command module
**Files to modify:**
- `yolo-mcp-server/src/commands/token_economics_report.rs` (NEW)
- `yolo-mcp-server/src/commands/mod.rs` (add `pub mod token_economics_report;`)

**What to implement:**
Create a new command module with `pub fn execute(args: &[String], cwd: &Path, db_path: &Path) -> Result<(String, i32), String>` that:

1. **Per-agent token spend table**: Query JSONL `.metrics/run-metrics.jsonl` for `agent_token_usage` events. Group by (agent_role, phase). Show columns: Role | Phase | Input | Output | Cache Read | Cache Write | Total.

2. **Cache hit rate**: Calculate `cache_read_tokens / (cache_read_tokens + cache_write_tokens + input_tokens) * 100` across all agents. Also show per-agent cache hit rates.

3. **Waste metric (heuristic)**: For each agent, waste = `input_tokens - output_tokens` when input >> output (ratio > 10:1). Flag agents with waste ratio > 10x as "high waste". Also count compile_context calls from SQLite where `output_length > 0` to compute context-loaded-but-unused ratio.

4. **ROI metric**: Count commits from `git log --oneline | wc -l` within the phase timeframe. Count tasks from event-log `task_completed_confirmed` events. ROI = total_tokens / completed_tasks. Also show tokens_per_commit.

5. **YOLO brand formatting**: Use ANSI colors matching `statusline.rs` constants (C_CYAN, C_GREEN, C_YELLOW, C_RED, C_BOLD, C_DIM, C_RESET). Render with box-drawing characters and the `[YOLO]` brand header. Progress bars for cache hit rate using the same `progress_bar` pattern.

**Test expectations:**
- Rust unit test: with mocked JSONL data, verify output contains all 4 sections (Per-Agent, Cache Hit, Waste, ROI)
- Rust unit test: verify cache hit rate calculation with known values (e.g., 3000 read / 4000 total = 75%)
- Rust unit test: verify waste detection flags agents with >10:1 input/output ratio

### Task 2: Wire `token-economics` into CLI router
**Files to modify:**
- `yolo-mcp-server/src/cli/router.rs`

**What to implement:**
- Add a new match arm in `run_cli`: `"report-tokens"` (or extend the existing `"report"` match arm to accept a subcommand). Recommended: add `"report-tokens"` as a new top-level command that calls `token_economics_report::execute(&args, &cwd, &db_path)`.
- Import `token_economics_report` in the router's use statement

**Test expectations:**
- Rust unit test in router.rs: verify `run_cli(vec!["yolo", "report-tokens"], db_path)` returns Ok with dashboard output when given test data
- Rust unit test: verify the command exits 0 with a helpful message when no data exists

### Task 3: Add `--phase` and `--json` output flags
**Files to modify:**
- `yolo-mcp-server/src/commands/token_economics_report.rs`

**What to implement:**
- Parse `--phase=N` to filter all metrics to a specific phase
- Parse `--json` flag to output raw JSON instead of formatted terminal output (for programmatic consumption)
- JSON output schema: `{ "per_agent": [...], "cache_hit_rate": { "overall": N, "per_agent": {...} }, "waste": { "agents": [...] }, "roi": { "tokens_per_task": N, "tokens_per_commit": N } }`

**Test expectations:**
- Rust unit test: with `--json` flag, verify output parses as valid JSON with expected keys
- Rust unit test: with `--phase=1`, verify only phase 1 data appears in output
