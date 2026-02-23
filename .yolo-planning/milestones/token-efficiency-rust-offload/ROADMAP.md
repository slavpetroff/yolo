# Roadmap: Token Efficiency — Rust Offload & Instruction Compression

## Phase 1: Fix Tests & Audit Rust CLI Coverage
**Goal:** Green test suite + complete inventory of Rust CLI vs MD-side deterministic work
**Success criteria:**
- All 728+ tests pass (fix 3 failing: validate-commit.bats x2, vibe-mode-split.bats x1)
- Audit document: every deterministic operation mapped to Rust command or flagged as "needs new command"
- REQ-01, REQ-02

## Phase 2: New Rust Commands for Deterministic Offload
**Goal:** Create Rust CLI commands that replace LLM-side deterministic work
**Success criteria:**
- `parse-frontmatter` — extract YAML frontmatter from any MD file as JSON
- `compile-progress` — compute phase/plan/summary counts and percentages
- `git-state` — unified git status, last release, commits since, dirty check
- `resolve-plugin-root` — resolve marketplace plugin path without shell glob
- All new commands have bats tests
- REQ-03

## Phase 3: Enhance Existing Rust Commands
**Goal:** Add flags to existing commands that eliminate LLM reasoning
**Success criteria:**
- `phase-detect --suggest-route` returns routing decision as JSON
- `resolve-model --with-cost` returns cost estimation alongside model resolution
- `session-start` consolidates pre-computed state that commands currently re-derive
- Updated bats tests for new flags
- REQ-04

## Phase 3b: Rust Idiom Cleanup
**Goal:** Refactor Phase 2+3 Rust code to use idiomatic patterns — enums, match arms, shared utilities
**Success criteria:**
- String-based state machines replaced with enums (StepStatus, PhaseState, Route, AgentRole, Model)
- if-else chains replaced with match arms throughout
- Regex moved outside loops / replaced with str methods
- Code duplication eliminated (config parsing, dir listing, response builders, skill collection)
- Error handling convention unified (Err vs Ok with exit code)
- Raw string indexing replaced with safe str methods (split_once, strip_prefix)
- All existing tests still pass

## Phase 4: Compress Agent & Command Instructions
**Goal:** Revise MD files to call Rust CLI, remove redundant inline logic, compress agent instructions
**Success criteria:**
- Command MDs call Rust utilities instead of inline shell/jq (23+ plugin-root instances eliminated)
- Agent instruction files compressed by 30%+ (remove verbose boilerplate, reference Rust output)
- All tests still pass after compression
- REQ-05, REQ-06, REQ-07
