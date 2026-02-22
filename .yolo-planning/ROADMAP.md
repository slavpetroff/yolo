# Agent Quality & Intelligent Compression Roadmap

**Goal:** Add Reviewer, QA, and Researcher agents with Rust-backed quality gates, implement automated token compression, and clean up the MCP/CLI hybrid pattern — all aligned with the 3-tier compiled context architecture for maximum cache reuse and stellar quality output.

**Scope:** 5 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 2 | 8 | 6 |
| 2 | Complete | 2 | 9 | 6 |
| 3 | Complete | 2 | 8 | 4 |
| 4 | Complete | 2 | 8 | 9 |
| 5 | Complete | 2 | 7 | 6 |

---

## Phase List
- [x] [Phase 1: MCP Hygiene & Compression Foundation](#phase-1-mcp-hygiene--compression-foundation)
- [x] [Phase 2: Researcher Agent](#phase-2-researcher-agent)
- [x] [Phase 3: Reviewer Agent (Architectural Critique)](#phase-3-reviewer-agent-architectural-critique)
- [x] [Phase 4: QA Agent (Delivery Verification)](#phase-4-qa-agent-delivery-verification)
- [x] [Phase 5: Integration, Testing & Release](#phase-5-integration-testing--release)

---

## Phase 1: MCP Hygiene & Compression Foundation

**Goal:** Document the MCP/CLI hybrid pattern, fix plugin.json MCP declaration, add markdown minification to compile-context, and create automated compression tooling.

**Requirements:** REQ-01 (infrastructure readiness)

**Success Criteria:**
- MCP hybrid pattern documented in ARCHITECTURE.md (agent tools via MCP, orchestrator tools via CLI)
- plugin.json properly declares MCP server (or decision documented to remove declaration)
- compile_context MCP tool removed (CLI-only — 0 MCP calls in telemetry, avoid dead overlap)
- Markdown minification pass added to tier_context.rs build pipeline (remove excessive whitespace, empty lines between sections)
- `yolo compress-context [--analyze-only]` CLI command: reports per-tier token breakdown and applies minification
- `yolo prune-completed --phase-dir {dir}` CLI command: strips completed plan details from phase directories (keeps SUMMARYs only)
- Automated pruning wired into archive flow (vibe-modes/archive.md calls prune-completed)
- Measured 5-10% additional token reduction on compiled context via `yolo report-tokens`
- All existing tests pass

**Dependencies:** None

---

## Phase 2: Researcher Agent

**Goal:** Create a dedicated research agent with internet access (WebSearch, WebFetch) that produces structured, compressed findings for consumption by Architect and Dev agents.

**Requirements:** REQ-02 (research capability)

**Success Criteria:**
- `agents/yolo-researcher.md` created with: WebSearch, WebFetch, Read, Glob, Grep, Bash (read-only), Write (findings only)
- Researcher is "planning" family in tier_context.rs (shares Tier 2 cache with Architect/Lead)
- `/yolo:research` command updated to spawn Researcher as subagent (not inline)
- Research findings written as structured JSONL: `{source, finding, confidence, category, tokens}` — capped at configurable line limit
- Research findings injected into Tier 3 volatile context when plan references `research_deps`
- Architect agent updated to request Researcher during discussion/planning (optional spawn)
- `config/model-profiles.json` includes researcher role (haiku for budget, sonnet for balanced/quality)
- hooks.json SubagentStart matcher includes `yolo-researcher`
- Bats tests for researcher context injection
- All existing tests pass

**Dependencies:** Phase 1

---

## Phase 3: Reviewer Agent (Architectural Critique)

**Goal:** Create an adversarial Reviewer agent that critiques architectural designs, validates code quality, and serves as a quality gate between plan creation and execution.

**Requirements:** REQ-03 (design quality)

**Success Criteria:**
- `agents/yolo-reviewer.md` created with: Read, Glob, Grep, Bash (read-only, git commands), WebFetch
- Reviewer is "planning" family (shares Tier 2 cache with Architect/Lead/Researcher)
- Review gate added to execute-protocol SKILL.md: after plans created (Step 2), before Dev team creation (Step 3)
- Reviewer produces structured verdict: `{verdict: approve|reject|conditional, findings: [{severity, file, issue, suggestion}], token_cost: N}`
- `yolo review-plan <plan_path>` Rust command: automated checks (complexity heuristics, naming convention violations, pattern anti-match)
- On reject: execution halts, findings returned to Architect for revision
- On conditional: findings attached to Dev context as warnings
- On approve: execution proceeds normally
- Skip gate configurable: `review_gate: always|on_request|never` in config.json
- hooks.json SubagentStart matcher includes `yolo-reviewer`
- `config/model-profiles.json` includes reviewer role (opus for quality, sonnet for balanced/budget)
- Bats tests for review-plan command
- All existing tests pass

**Dependencies:** Phase 2

---

## Phase 4: QA Agent (Delivery Verification)

**Goal:** Create a QA agent that verifies code delivery against plans, backed by 5 new Rust verification commands, serving as a post-execution quality gate.

**Requirements:** REQ-04 (delivery quality)

**Success Criteria:**
- `agents/yolo-qa.md` created with: Read, Glob, Grep, Bash (read-only + git + test runners)
- QA is "execution" family (shares Tier 2 cache with Dev/Debugger)
- 5 new Rust CLI commands:
  - `yolo verify-plan-completion <summary_path> <plan_path>`: cross-references SUMMARY tasks vs PLAN tasks, checks commit evidence
  - `yolo check-regression <phase_dir>`: compares test count before/after phase commits, flags regressions
  - `yolo diff-against-plan <summary_path>`: compares declared files_modified vs actual git diff
  - `yolo validate-requirements <plan_path> <phase_dir>`: checks must_haves appear in code/tests
  - `yolo commit-lint <commit_range>`: validates commit message format against convention
- QA gate added to execute-protocol SKILL.md: after all Dev tasks complete (Step 3c), before state update (Step 5)
- QA produces structured report: `{passed: bool, checks: [{name, status, evidence}], regressions: N}`
- On failure: execution halts with detailed findings
- Skip gate configurable: `qa_gate: always|on_request|never` in config.json
- hooks.json SubagentStart matcher includes `yolo-qa`
- `config/model-profiles.json` includes qa role
- Bats tests for all 5 QA commands
- All existing tests pass

**Dependencies:** Phase 3

---

## Phase 5: Integration, Testing & Release

**Goal:** End-to-end testing of all new agents and commands, update documentation, version bump, and release.

**Requirements:** REQ-05 (release readiness)

**Success Criteria:**
- Integration test: full phase lifecycle with Researcher → Reviewer → Dev → QA pipeline
- README.md updated: 8 agents (architect, debugger, dev, docs, lead, qa, researcher, reviewer)
- ARCHITECTURE.md updated: agent roster, MCP/CLI hybrid, new Rust commands
- CONCERNS.md refreshed with accurate test counts
- model-profiles.json has all 8 agent entries
- hooks.json has all 8 agents in SubagentStart matcher
- Version bumped across all version files
- CHANGELOG updated
- All existing + new tests pass (target: 1,700+ total)

**Dependencies:** Phase 4
