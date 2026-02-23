# Quality Gate Feedback Loops Roadmap

**Goal:** Add configurable feedback loops to the Review and QA gates so that rejected plans are automatically revised by the Architect and QA failures are automatically remediated by Dev — with hard-cap cycle limits to prevent infinite loops. Optimize for token efficiency by leveraging the existing Tier 2 cache sharing (Reviewer/Architect share "planning" cache, QA/Dev share "execution" cache).

**Scope:** 4 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 2 | 10 | 8 |
| 2 | Pending | 0 | 0 | 0 |
| 3 | Pending | 0 | 0 | 0 |
| 4 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: Loop Config & Structured Feedback Infrastructure](#phase-1-loop-config--structured-feedback-infrastructure)
- [ ] [Phase 2: Review Feedback Loop (Architect ↔ Reviewer)](#phase-2-review-feedback-loop-architect--reviewer)
- [ ] [Phase 3: QA Feedback Loop (Dev ↔ QA)](#phase-3-qa-feedback-loop-dev--qa)
- [ ] [Phase 4: Testing & Release](#phase-4-testing--release)

---

## Phase 1: Loop Config & Structured Feedback Infrastructure

**Goal:** Add config keys for loop control, enhance review_plan.rs with actionable feedback fields, add loop state tracking to execution-state.json, and wire event logging for loop iterations.

**Requirements:** REQ-01 (loop infrastructure)

**Success Criteria:**
- `review_max_cycles` config key (default: 3, range: 1-5) in config.json and defaults.json
- `qa_max_cycles` config key (default: 3, range: 1-5) in config.json and defaults.json
- `review_plan.rs` enhanced: each finding includes `suggested_fix` string and `auto_fixable` boolean
- `.execution-state.json` schema extended with `review_loop: {cycle: N, max: N, status: pending|passed|failed}` and `qa_loop: {cycle: N, max: N, status: pending|passed|failed}`
- QA commands (`verify-plan-completion`, `commit-lint`, `diff-against-plan`, `validate-requirements`, `check-regression`) enhanced: each check includes `fixable_by: "dev"|"architect"|"manual"` field
- Event log types added: `review_loop_start`, `review_loop_cycle`, `qa_loop_start`, `qa_loop_cycle`
- Unit tests for enhanced Rust output formats
- All existing tests pass

**Dependencies:** None

---

## Phase 2: Review Feedback Loop (Architect ↔ Reviewer)

**Goal:** Implement the Architect ↔ Reviewer feedback loop in the execute-protocol. When the Reviewer rejects a plan, automatically spawn the Architect with findings to revise, then re-review — looping until approved/conditional or max_cycles exceeded.

**Requirements:** REQ-02 (review loop)

**Success Criteria:**
- Execute-protocol SKILL.md Step 2b updated with loop logic:
  - On `reject`: spawn Architect subagent with findings context + original plan
  - Architect produces revised PLAN.md (overwrites original)
  - Re-run Reviewer on revised plan
  - Loop until `approve`/`conditional` or `review_max_cycles` reached
  - On max cycles exceeded: HARD STOP with all accumulated findings
- Architect agent (`yolo-architect.md`) updated with "Revision Protocol" section:
  - Accept reviewer findings as input context
  - Produce revised plan addressing high/medium severity findings
  - Track which findings were addressed in revision commit message
- Reviewer agent (`yolo-reviewer.md`) updated:
  - On re-review, compare against previous findings (delta-aware)
  - Escalate if same high-severity finding persists across 2+ cycles
- Token efficiency: pass only delta findings between iterations, not full context recompile
  - Architect and Reviewer share "planning" Tier 2 cache — stays warm between iterations
  - Only Tier 3 volatile tail changes (updated plan files)
- Execution state tracks: `review_loop.cycle`, `review_loop.status`, `review_loop.findings_per_cycle[]`
- `conditional` verdict on final cycle: attach warnings to Dev context, proceed

**Dependencies:** Phase 1

---

## Phase 3: QA Feedback Loop (Dev ↔ QA)

**Goal:** Implement the Dev ↔ QA feedback loop in the execute-protocol. When QA checks fail, categorize failures by fixability, auto-spawn Dev for code fixes, then re-run QA — looping until all checks pass or max_cycles exceeded.

**Requirements:** REQ-03 (QA loop)

**Success Criteria:**
- Execute-protocol SKILL.md Step 3d updated with loop logic:
  - On QA failure: categorize each failed check by `fixable_by` field
  - If `fixable_by: "dev"`: spawn Dev subagent with scoped remediation task (fix commit format, update SUMMARY, fix tests)
  - If `fixable_by: "architect"`: HARD STOP — plan-level issues can't be auto-fixed post-execution
  - If `fixable_by: "manual"`: HARD STOP — requires human intervention
  - Dev fixes issue + commits
  - Re-run QA
  - Loop until all pass or `qa_max_cycles` reached
  - On max cycles exceeded: HARD STOP with all accumulated findings
- QA agent (`yolo-qa.md`) updated with "Remediation Classification" section:
  - Classify each failure: commit_lint violations → dev-fixable, regression → manual, requirements → architect
  - Produce structured JSON report with `failed_checks[].fixable_by` field
- Dev agent receives scoped remediation context:
  - Only the specific failure details, not full QA report
  - Clear instructions: "fix commit message X" or "update SUMMARY.md field Y"
- Token efficiency: Dev and QA share "execution" Tier 2 cache — stays warm between iterations
  - Only re-run failed checks on subsequent cycles (skip passed checks)
  - Dev receives minimal remediation context, not full plan/summary re-read
- Execution state tracks: `qa_loop.cycle`, `qa_loop.status`, `qa_loop.failed_checks_per_cycle[]`

**Dependencies:** Phase 2

---

## Phase 4: Testing & Release

**Goal:** Comprehensive testing of both feedback loops, documentation updates, and version bump.

**Requirements:** REQ-04 (release readiness)

**Success Criteria:**
- Bats tests for review loop: mock reject → revise → approve flow
- Bats tests for QA loop: mock fail → fix → pass flow
- Bats tests for hard cap: max_cycles exceeded → HARD STOP
- README.md updated with feedback loop documentation
- ARCHITECTURE.md updated with loop flow diagrams
- CHANGELOG.md updated with v2.7.0 entry
- Version bumped to 2.7.0
- All existing + new tests pass

**Dependencies:** Phase 3
