# YOLO Roadmap

**Goal:** YOLO

**Scope:** 5 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 3/3 | 12 | 12 |
| 2 | Complete | 1/1 | 4 | 2 |
| 5 | Complete | 3/3 | 13 | 11 |
| 6 | Complete | 2/2 | 8 | 2 |
| 7 | Complete | 3/3 | 13 | 3 |

---

## Phase List
- [x] [Phase 1: General Improvements](#phase-1-general-improvements)
- [x] [Phase 2: Fix Statusline](#phase-2-fix-statusline)
- [x] [Phase 5: MCP Server Audit & Fixes](#phase-5-mcp-server-audit--fixes)
- [x] [Phase 6: Integration Wiring Audit](#phase-6-integration-wiring-audit)
- [x] [Phase 7: Token Cache Architecture](#phase-7-token-cache-architecture)

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

---

## Phase 6: Integration Wiring Audit

**Goal:** Create missing agent definitions (yolo-lead, yolo-debugger), clean up stale hook matchers referencing deprecated agents (yolo-qa, yolo-scout), and verify all MCP tools, CLI commands, agent references, and hook scripts are properly wired end-to-end

**Requirements:** REQ-08

**Success Criteria:**
- `agents/yolo-lead.md` exists with planning orchestration protocol, matching vibe.md Plan mode expectations
- `agents/yolo-debugger.md` exists with scientific debugging protocol, matching debug command expectations
- `hooks/hooks.json` matchers only reference agents that have definitions (remove yolo-qa, yolo-scout)
- Every agent's `allowed-tools` frontmatter includes the MCP tools it actually references in its body
- All existing tests pass
- No orphaned references: every agent name in hooks, commands, and references maps to an existing agent file

**Dependencies:** None

---

## Phase 7: Token Cache Architecture

**Goal:** Realign with the YOLO Expert architecture blueprint: restructure agent prompt assembly so compiled context is injected verbatim at the TOP of every Task prompt (prefix-first pattern for Anthropic API cache hits), split compile_context output into stable prefix + volatile tail, upgrade the ROI telemetry dashboard from hardcoded projections to measured data, and enable token budget enforcement

**Requirements:** REQ-09

**Success Criteria:**
- Execute-protocol injects compiled context content (not file path) as the first block of every Dev agent's Task description
- Vibe Plan mode injects compiled context content at the top of Lead agent's Task description
- compile_context MCP tool returns separate `stable_prefix` and `volatile_tail` fields (plus `prefix_hash` and `prefix_bytes`)
- compile-context CLI emits `<!-- STABLE_PREFIX_END -->` sentinel between stable and volatile sections
- `yolo report` uses actual `AVG(output_length)` from telemetry DB instead of hardcoded 80K assumption
- `v2_token_budgets=true` in config, token truncation enforced and logged
- `v3_metrics=true` and `v3_event_log=true` enabled for observability
- All existing tests pass + new tests for stable/volatile split
- Phase number moved from stable prefix header to volatile tail (enables cross-phase cache reuse)

**Dependencies:** None
