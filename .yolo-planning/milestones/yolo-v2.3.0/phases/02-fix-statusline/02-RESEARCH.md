# Phase 2 Research: Fix Statusline

## Problem
The YOLO statusline (`yolo statusline` CLI) produces broken output:
- "Phase: None", "Plans: 0/0", "Progress: 0%" — despite Phase 1 being complete
- "auth expired (run /login)" — makes unnecessary Anthropic API calls
- "Model: claude-3-5-sonnet-20241022" — hardcoded outdated model name
- Cache Hits counter uses SQLite DB that doesn't exist

## Root Cause Analysis

### 1. STATE.md Parsing Mismatch (statusline.rs:37-57)
`get_state_info()` looks for lines starting with `Phase: `, `Plans: `, `Progress: ` — but STATE.md uses Markdown bold format: `**Current Phase:** Phase 1`, `**Status:** Complete`, `**Progress:** 100%`. The patterns NEVER match.

### 2. Unnecessary API Calls (statusline.rs:95-157)
`execute_fetch_limits()` sends real HTTP requests to `https://api.anthropic.com/v1/messages` to read rate limit headers. This is completely wrong — Claude Code provides context_window/cost/model data on stdin as JSON. The VBW statusline reads `$(cat)` from stdin and parses with jq.

### 3. Hardcoded Model (statusline.rs:107,113,147,153,188,213)
Model is hardcoded to `claude-3-5-sonnet-20241022` in 6 places. Should come from stdin JSON `.model.display_name`.

### 4. Missing Stdin JSON Parsing
Claude Code pipes a JSON payload to statusline commands containing:
- `.context_window.used_percentage`, `.context_window.remaining_percentage`
- `.context_window.current_usage.input_tokens`, `.output_tokens`, `.cache_creation_input_tokens`, `.cache_read_input_tokens`
- `.context_window.context_window_size`
- `.cost.total_cost_usd`, `.cost.total_duration_ms`, `.cost.total_api_duration_ms`
- `.cost.total_lines_added`, `.cost.total_lines_removed`
- `.model.display_name`
- `.version` (Claude Code version)

The current Rust code ignores stdin entirely.

## VBW Reference (scripts/vbw-statusline.sh)
The VBW statusline is a 481-line bash script with:
- **Stdin JSON parsing**: `input=$(cat)` then jq extraction of all context_window/cost/model fields
- **4-line output**: L1=project/phase, L2=context window, L3=usage limits, L4=model/cost
- **Multi-tier caching**: Fast cache (5s TTL) for VBW state, slow cache (60s TTL) for OAuth usage
- **OAuth integration**: Reads credentials from macOS Keychain, Linux secret-tool, or files
- **Git awareness**: Branch, staged/modified counts, ahead count, GitHub clickable links
- **Execution state**: Reads `.execution-state.json` for build progress bars
- **Update checking**: Compares local VERSION against GitHub remote
- **Cost ledger**: Tracks per-agent cost attribution

## Recommended Approach
Rewrite `statusline.rs` to:
1. **Read stdin JSON** for context_window, cost, model data (match VBW approach)
2. **Parse `.yolo-planning/STATE.md`** with correct Markdown bold patterns OR use `.execution-state.json`
3. **Read `.yolo-planning/config.json`** for effort/model_profile
4. **Add git info** via `git` commands (branch, staged, modified)
5. **Remove all API call logic** (execute_fetch_limits, trigger_background_fetch, get_cache_path, reqwest dependency if unused elsewhere)
6. **Add OAuth usage** via same approach as VBW (credential store -> /api/oauth/usage)
7. **Add update checking** against GitHub remote VERSION file
8. **Use multi-tier file caching** for slow operations (OAuth, update check)
9. **Match VBW 4-line format**: project+phase, context window, usage limits, model+cost

## Files to Modify
- `yolo-mcp-server/src/commands/statusline.rs` — Full rewrite
- `yolo-mcp-server/src/cli/router.rs` — Pipe stdin to statusline, add fetch-limits removal
- `yolo-mcp-server/Cargo.toml` — May remove `reqwest` if only used by statusline

## Risks
- `reqwest` may be used by other modules — check before removing
- OAuth credential access differs macOS vs Linux
- Tests need full rewrite to match new behavior
