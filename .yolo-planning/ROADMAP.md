# YOLO Roadmap

**Goal:** YOLO

**Scope:** 3 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 3/3 | 12 | 12 |
| 2 | Complete | 1/1 | 4 | 2 |
| 5 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: General Improvements](#phase-1-general-improvements)
- [x] [Phase 2: Fix Statusline](#phase-2-fix-statusline)
- [ ] [Phase 5: MCP Server Audit & Fixes](#phase-5-mcp-server-audit--fixes)

---

## Phase 1: General Improvements

**Goal:** Address open improvements, bug fixes, and enhancements across the YOLO plugin

**Requirements:** REQ-01, REQ-02, REQ-03, REQ-04, REQ-05

**Success Criteria:**
- All targeted improvements implemented and tested
- CI pipeline passes
- No regressions in existing functionality

**Dependencies:** None

---

## Phase 2: Fix Statusline

**Goal:** Rewrite the YOLO statusline to read stdin JSON from Claude Code, parse state files correctly, display context window/cost/model info, and add OAuth usage + git awareness — matching VBW statusline functionality

**Requirements:** REQ-06

**Success Criteria:**
- Statusline reads stdin JSON for context_window, cost, model data
- Phase/plans/progress parsed correctly from STATE.md or execution-state.json
- No Anthropic API calls for rate limits (uses OAuth usage endpoint instead)
- Model name comes from stdin JSON, not hardcoded
- Git branch and file change indicators displayed
- Multi-tier caching for OAuth and update checks
- All tests pass after rewrite

**Dependencies:** None

---

## Phase 5: MCP Server Audit & Fixes

**Goal:** Audit and fix 8 verified findings in the yolo-mcp-server Rust implementation: concurrent request handling, async thread blocking, compile_context token bloat (role/phase-aware filtering), telemetry data capture, dynamic test runner detection, delta_files fallback strategy, and minor optimizations (phase parsing cache, HashSet normalization)

**Requirements:** REQ-07

**Success Criteria:**
- MCP server handles requests concurrently via tokio::spawn + mpsc channel
- All external process calls use tokio::process::Command (no sync blocking)
- compile_context filters output by role and phase parameters (not blind concatenation)
- run_test_suite auto-detects test runner (npm/cargo/bats/pytest) from project context
- Telemetry records actual input/output byte lengths (not hardcoded 0,0)
- delta_files limits fallback scope (cap file count, skip tag-based fallback)
- token_baseline caches phase parsing outside inner loops
- bootstrap_claude uses HashSet for O(N+M) deduplication instead of O(N*M)
- All existing tests pass + new tests for concurrent handling and role-filtered context
- cargo build succeeds with no warnings

**Dependencies:** None
