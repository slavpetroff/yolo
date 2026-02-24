# Roadmap: Workflow Validation & Rust Quality Audit

## Phase 1 — QA & Reviewer Gate Enforcement
**Goal:** Fix all gaps where QA/Reviewer gates are defined but not properly enforced during execution.

**Success Criteria:**
- review_gate and qa_gate defaults changed to "always" in defaults.json
- qa_skip_agents enforced in execute protocol (docs plans skip QA)
- check-regression fixable_by consistent: "manual" everywhere
- Verdict parsing fails closed on malformed output (STOP, not continue)
- All existing tests pass; new tests cover gate enforcement

**REQ coverage:** REQ-01, REQ-02, REQ-03, REQ-04

## Phase 2 — HITL Hardening
**Goal:** Make human-in-the-loop gates genuinely blocking instead of advisory/stub.

**Success Criteria:**
- request_human_approval writes execution state to disk and returns structured pause signal
- Architect Vision Gate enforced: execution state tracks "awaiting_approval" status
- Execute protocol checks approval state before proceeding past vision gate
- UAT checkpoint mechanism documented for all autonomy levels
- Tests validate HITL blocking behavior

**REQ coverage:** REQ-05, REQ-06

## Phase 3 — Rust Idiomatic Hardening
**Goal:** Fix the highest-priority Rust anti-patterns: unsafe unwrap in async, regex hot-path compilation, duplicated code, inconsistent config parsing.

**Success Criteria:**
- Mutex::lock().unwrap() replaced with proper error handling in telemetry/db.rs and mcp/tools.rs
- Regex::new() calls in hot paths use OnceLock statics (security_filter, phase_detect, generate_contract)
- extract_frontmatter() deduplicated into commands/utils.rs
- At least 3 more command files migrated from manual JSON parsing to YoloConfig struct
- unsafe { libc::getuid() } replaced with safe alternative
- cargo clippy passes clean; all Rust unit tests pass

**REQ coverage:** REQ-07, REQ-08, REQ-09, REQ-10

## Phase 4 — Validation & Release
**Goal:** End-to-end validation of all changes, regression testing, version bump.

**Success Criteria:**
- Full bats test suite passes (700+ tests, 0 failures)
- cargo test passes (all Rust unit tests)
- Manual smoke test of execute protocol with review_gate=always and qa_gate=always
- CHANGELOG updated, version bumped
- CLAUDE.md updated with new defaults and any convention changes

**REQ coverage:** All REQs validated
