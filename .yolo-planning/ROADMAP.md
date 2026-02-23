# Roadmap: Workflow Integrity Enforcement

**Milestone:** Workflow Integrity Enforcement
**Phases:** 4
**Scope:** Execute protocol (SKILL.md), tier context system (tier_context.rs), agent definitions, enforcement hooks

## Phase 1: Review Gate — Agent-Based Adversarial Review ✓
**Goal:** Replace the review-plan CLI-only path in Step 2b with a two-stage review: Rust CLI pre-check (structural validation) THEN yolo-reviewer agent spawn (adversarial design review). The agent's VERDICT becomes the gate verdict, not the CLI exit code.
**Success criteria:** Execute protocol spawns yolo-reviewer agent for every plan when review_gate="always". Reviewer agent can reject a plan and trigger the architect revision feedback loop. Rust CLI pre-check still runs as a fast fail-early gate.
**REQ:** REQ-01, REQ-04, REQ-08
**Status:** Complete (2026-02-24) — 2 plans, 2 commits

## Phase 2: QA Gate — Agent-Based Verification
**Goal:** Replace the QA CLI-only path in Step 3d with a two-stage verification: Rust CLI commands provide structured data, THEN yolo-qa agent analyzes results and applies adversarial verification. QA agent's report becomes the gate verdict.
**Success criteria:** Execute protocol spawns yolo-qa agent after Dev completion when qa_gate="always". QA agent can trigger HARD STOP or dev-fixable remediation loop. CLI commands still run as data sources for the QA agent.
**REQ:** REQ-02, REQ-04, REQ-08

## Phase 3: Context Integrity — Architecture Persistence & Step Ordering
**Goal:** Fix context injection so developers receive ARCHITECTURE.md. Add step-ordering verification to execution-state.json. Strengthen delegation mandate to survive compression.
**Success criteria:** Execution family tier2 includes ARCHITECTURE.md. Execution-state.json tracks which steps completed (prevents skip). Lead delegation mandate is reinforced with anti-takeover patterns.
**REQ:** REQ-03, REQ-05, REQ-06

## Phase 4: Integration Tests & Validation
**Goal:** Add bats tests verifying that review and QA agents are spawned during execution, feedback loops trigger correctly, and context includes ARCHITECTURE.md for all roles.
**Success criteria:** New test files covering agent spawn verification, gate enforcement, context compilation with architecture, and step ordering. All existing tests still pass.
**REQ:** REQ-07
