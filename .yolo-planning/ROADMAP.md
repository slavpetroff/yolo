# CLI Intelligence & Token Optimization Roadmap

**Goal:** Fix incomplete CLI commands, add structured JSON returns to all state-changing operations, reduce token overhead by 10-15%, and split vibe.md for on-demand mode loading

**Scope:** 4 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 5 | 18 | 14 |
| 2 | Complete | 4 | 20 | 17 |
| 3 | Pending | 0 | 0 | 0 |
| 4 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: Incomplete CLI & MCP Command Fixes](#phase-1-incomplete-cli--mcp-command-fixes)
- [x] [Phase 2: Rust CLI Structured Returns](#phase-2-rust-cli-structured-returns)
- [ ] [Phase 3: Token Reduction Sweep](#phase-3-token-reduction-sweep)
- [ ] [Phase 4: Hot Path & vibe.md Mode Splitting](#phase-4-hot-path--vibemd-mode-splitting)

---

## Phase 1: Incomplete CLI & MCP Command Fixes

**Goal:** Fix broken and incomplete Rust CLI commands so every path produces correct, complete output. This is foundational — structured returns and token optimizations depend on commands actually working.

**Requirements:** REQ-01 (CLI completeness)

**Success Criteria:**
- `yolo infer` correctly detects tech stack (languages, frameworks, tools) from pyproject.toml, Cargo.toml, package.json, go.mod, etc.
- `yolo infer` extracts project purpose from README.md, PROJECT.md, or package description
- `yolo detect-stack` returns complete JSON with all detected signals
- `yolo delta-files` returns distinguishable empty vs no-strategy-worked responses
- `yolo hard-gate` exits 2 on conflict (not 0)
- `yolo lock` exits 2 on conflict (not 0)
- All 56 CLI commands audited for stubs, silent failures, and unrouted modules
- End-to-end test: `yolo infer` on alpine-notetaker correctly detects FastAPI + Redis + Python

**Dependencies:** None

---

## Phase 2: Rust CLI Structured Returns

**Goal:** Make all state-changing CLI commands return structured JSON with operation deltas, eliminating 50-150 wasted LLM tool calls per phase execution.

**Requirements:** REQ-02 (LLM efficiency)

**Success Criteria:**
- 12 fire-and-forget commands return structured JSON: `{"ok": bool, "cmd": "...", "changed": [...], "delta": {...}, "elapsed_ms": N}`
- Exit code standardization: 0=success, 1=error, 2=partial/conflict, 3=skipped
- LLM caller never needs to re-read a file just to understand what a command did
- `update-state` returns delta showing before/after state
- `compile-context` returns tier sizes, cache hit info, output path
- `planning-git commit-boundary` returns commit hash or "skipped" with reason
- `bootstrap *` returns content summary of generated file
- `suggest-next` returns reasoning along with suggestion
- All existing tests pass with JSON output parsing

**Dependencies:** Phase 1

---

## Phase 3: Token Reduction Sweep

**Goal:** Reduce static token overhead by 10-15% per workflow cycle through deduplication, conditional loading, and reference consolidation.

**Requirements:** REQ-03 (token efficiency)

**Success Criteria:**
- V3 experimental features extracted from execute-protocol.md to optional file (loaded only when enabled)
- Shared "Agent Base Patterns" reference created, deduplicating Circuit Breaker/Context Injection/Shutdown across 5 agents
- 4 effort profile MDs consolidated into 1 JSON + summary doc
- 3 dead redirect references removed (execute-protocol.md, discussion-engine.md, verify-protocol.md in references/)
- Handoff-schemas.md reduced via schema-driven approach (JSON examples → config reference)
- Measured token reduction via `yolo report-tokens` shows 10%+ improvement
- No behavioral regression (all tests pass, agents follow conventions)

**Dependencies:** Phase 2

---

## Phase 4: Hot Path & vibe.md Mode Splitting

**Goal:** Optimize highest-frequency code paths. Split vibe.md monolith into mode-specific files for on-demand loading, reducing per-invocation token cost from 7,220 to ~1,500.

**Requirements:** REQ-04 (hot path optimization)

**Success Criteria:**
- vibe.md split into mode-specific files (plan.md content, execute.md content, etc.) loaded on demand
- Each /yolo:vibe invocation loads only the active mode (~1,500 tokens) instead of all 11 (~7,220 tokens)
- Tier 1 mtime caching in compile-context (skip recompilation when architecture unchanged)
- `v2_token_budgets=true` enabled by default with safe defaults
- `session-start` reports step-level success/failure for all 15 init steps
- Measured tokens-per-phase improvement via `yolo report-tokens`
- No behavioral regression across all workflow paths (plan, execute, verify, discuss, archive)

**Dependencies:** Phase 3

