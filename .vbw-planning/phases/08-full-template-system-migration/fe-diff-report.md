# Frontend Overlay Parity Diff Report

Diff of all 9 hand-authored FE agents vs `generate-agent.sh --dry-run --dept frontend` output.

## Legend

- **TEMPLATE_RICHER**: Template has content that hand-authored file lacks (hand-authored file is missing sections from template)
- **HAND_RICHER**: Hand-authored file has FE-specific content not in overlay/template (needs back-port to frontend.json)
- **COSMETIC**: Formatting/wording difference with no semantic impact (e.g., `--` vs `---`, section reordering)
- **DIVERGED**: Both sides have different content for the same concept (needs reconciliation)

---

## 1. yolo-fe-dev.md

### Status: TEMPLATE_RICHER + COSMETIC

The hand-authored file is MISSING significant template sections. The overlay already contains all FE-specific content for dev role.

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| COSMETIC | Title uses "Frontend" vs template "FE" | HAND_RICHER | `# YOLO Frontend Dev` vs `# YOLO FE Dev` (template uses DEPT_LABEL) |
| COSMETIC | "No creative decisions" in description | HAND_RICHER | Hand has "component specs" vs template "task specs" |
| COSMETIC | Section order | DIVERGED | Hand: Persona → Hierarchy → Execution. Template: Hierarchy → Persona → Execution |
| COSMETIC | Archetype dash style | DIVERGED | Hand: `--`, Template: `---` |
| TEMPLATE_RICHER | Compaction marker check | MISSING | `.yolo-planning/.compaction-marker` check in Stage 1 |
| TEMPLATE_RICHER | Remediation detail | MISSING | 5-step gap fix protocol (read gap, fix, update st, commit, continue) |
| TEMPLATE_RICHER | TDD RED detail | MISSING | Phase dir + test-plan.jsonl tf field reference; "(spec or tests may be wrong)" |
| TEMPLATE_RICHER | GREEN check detail | MISSING | `bash scripts/test-summary.sh` reference; "never invoke bats directly" |
| TEMPLATE_RICHER | Done criteria | MISSING | Step 7 validate done criteria from `done` field |
| TEMPLATE_RICHER | Checkpoint | MISSING | `tp = "checkpoint:*"` stop behavior |
| TEMPLATE_RICHER | Summary JSONL example | MISSING | Full example line with all fields |
| TEMPLATE_RICHER | Research Request Output | MISSING | Entire section (research_request schema, blocking/informational) |
| TEMPLATE_RICHER | Escalation Resolution | MISSING | Pause Behavior, Receive Resolution, Resume Protocol sections |
| TEMPLATE_RICHER | Change Management | MISSING | 5-step protocol for code_review_changes handling |
| TEMPLATE_RICHER | Communication section | MISSING | `As teammate:` summary line |
| TEMPLATE_RICHER | Shutdown Response | MISSING | Full 5-step shutdown protocol (hand has only cross-reference) |
| TEMPLATE_RICHER | Constraints detail | MISSING | One commit per task format, progress tracking, compaction check |
| TEMPLATE_RICHER | Minor deviation rule | MISSING | `<5 lines: Fix inline, note in summary dv field` |
| COSMETIC | Escalation table wording | DIVERGED | "domain question" vs "critical deviation"; "Architectural issue" row missing |

### Overlay Coverage: COMPLETE (all DEV_* keys populated in frontend.json)

---

## 2. yolo-fe-senior.md

### Status: TEMPLATE_RICHER + COSMETIC

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| COSMETIC | Title "Frontend" vs "FE" | HAND_RICHER | Same as dev |
| COSMETIC | Section order | DIVERGED | Hand: Intro → Persona → Hierarchy → Mode1. Template: Intro → Hierarchy → Persona → Mode1 |
| TEMPLATE_RICHER | Critique check in Design Review | MISSING | Step 2: critique.jsonl reading |
| TEMPLATE_RICHER | Codebase research wording | DIVERGED | Hand: "component patterns, styling conventions". Template: "patterns, file structures, naming conventions" |
| TEMPLATE_RICHER | TDD compliance detail | MISSING | "verify test files exist, run tests and verify all pass (GREEN confirmed), check test quality" |
| TEMPLATE_RICHER | Review Cycles section | MISSING | Entire section: Minor/Major classification, cycle limits, collaborative approach, Phase 4 hooks |
| TEMPLATE_RICHER | Escalation table row | MISSING | "Cross-phase dependency issue" row |
| TEMPLATE_RICHER | Recognizing Dev Escalations | MISSING | Subsection header + "explaining why Senior cannot resolve it locally" |
| TEMPLATE_RICHER | Resolution Routing | MISSING | Entire section: Translation Protocol, Verification Gate |
| TEMPLATE_RICHER | Decision Logging | MISSING | Entire section with JSONL schema and example |
| TEMPLATE_RICHER | Constraints detail | MISSING | "No source code changes" repeated, "Produces:" list |
| TEMPLATE_RICHER | Parallel review detail | MISSING | "The FE Senior protocol is identical in both steps." |

### Overlay Coverage: COMPLETE (all SENIOR_* keys populated)

---

## 3. yolo-fe-tester.md

### Status: TEMPLATE_RICHER + COSMETIC

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| COSMETIC | Title "Frontend" vs "FE" | HAND_RICHER | Same pattern |
| COSMETIC | "No directs" | MISSING | Template adds "No directs." to hierarchy |
| TEMPLATE_RICHER | Step 1 condensed | DIVERGED | Template compresses Step 1 into 1 paragraph vs hand's 3 numbered steps |
| TEMPLATE_RICHER | Step 2 detail | DIVERGED | Hand: "Run test suite to confirm ALL tests FAIL. If any test passes..." vs Template: "ALL tests for this task must fail (or error due to missing implementation)" + "Record in test-plan.jsonl" |
| TEMPLATE_RICHER | Effort-Based Behavior | MISSING | Entire section (turbo/fast/balanced/thorough) |
| TEMPLATE_RICHER | Test Quality Standards | MISSING | Entire section |
| TEMPLATE_RICHER | Output Schema section | MISSING | Compact schema description section |
| TEMPLATE_RICHER | Communication section | MISSING | `As teammate:` summary line |
| TEMPLATE_RICHER | Missing deps escalation | MISSING | "Missing dependencies for test imports" row in escalation table |
| TEMPLATE_RICHER | Constraints detail | MISSING | "Test files must be syntactically correct", "Commit format", "(never git add .)" |
| COSMETIC | Escalation table order | DIVERGED | Hand has escalation before teammate; template has escalation after constraints |

### Overlay Coverage: COMPLETE (all TESTER_* keys populated)

---

## 4. yolo-fe-lead.md

### Status: TEMPLATE_RICHER + COSMETIC

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| COSMETIC | Title "Frontend" vs "FE" | HAND_RICHER | Same pattern |
| TEMPLATE_RICHER | Escalation Receipt and Routing | MISSING | Entire section: Receive/Assess, State Tracking, Timeout Monitoring, Resolution Forwarding |
| TEMPLATE_RICHER | Output Format detail | MISSING | "Line 1 = plan header, Lines 2+ = tasks (NO `spec` field...)" |
| TEMPLATE_RICHER | Display statusline msgs | MISSING | All `Display:` lines throughout planning protocol |
| TEMPLATE_RICHER | Research numbering format | DIVERGED | Hand: "1. 2. 3..." vs Template: "(1) (2) (3)..." |
| TEMPLATE_RICHER | Stage 3 Self-Review detail | MISSING | Separate section with checklist and Display lines |
| TEMPLATE_RICHER | Stage 4 Commit and Report | MISSING | Separate section with format and Display lines |
| TEMPLATE_RICHER | Decision Logging | MISSING | Entire section with JSONL schema |
| TEMPLATE_RICHER | Constraints detail | MISSING | "compaction resilience", "git log, dir listing, patterns", "Step 3/Step 4" references |
| TEMPLATE_RICHER | Review ownership wording | DIVERGED | Template adds "(Design Review exit)" |
| COSMETIC | Team name | DIVERGED | Hand: "Frontend engineering team" vs Template: "FE engineering team" |

### Overlay Coverage: COMPLETE (all LEAD_* keys populated)

---

## 5. yolo-fe-architect.md

### Status: TEMPLATE_RICHER + COSMETIC

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| COSMETIC | Title "Frontend" vs "FE" | HAND_RICHER | Same pattern |
| COSMETIC | Section order | DIVERGED | Hand: Intro → Persona → Hierarchy → Protocol. Template: Intro → Hierarchy → Persona → protocol |
| TEMPLATE_RICHER | NEVER contacts User | MISSING | "NEVER contacts User directly -- escalate through Owner" in Hierarchy |
| TEMPLATE_RICHER | Final escalation point line | MISSING | "Final technical escalation point..." moved above Core Protocol |
| TEMPLATE_RICHER | Load context detail | MISSING | "(INDEX.md, ARCHITECTURE.md, PATTERNS.md, CONCERNS.md if exist)" |
| TEMPLATE_RICHER | Address critique detail | MISSING | 3 disposition paths (addressed, deferred, rejected) |
| TEMPLATE_RICHER | Consume research | MISSING | Entire Step 3: 3 research modes (post-critic, pre-critic, standalone) |
| TEMPLATE_RICHER | Phase decomposition | MISSING | Step 6 entirely |
| TEMPLATE_RICHER | Architecture.toon Format | MISSING | Entire section with TOON format description |
| TEMPLATE_RICHER | Decision Logging | MISSING | Entire section with JSONL schema |
| TEMPLATE_RICHER | Escalation table wording | DIVERGED | "with options", "with evidence" vs hand's specific descriptions |
| TEMPLATE_RICHER | Constraints detail | MISSING | "(except decisions.jsonl: append only)" |
| TEMPLATE_RICHER | Review ownership via Lead | MISSING | "via FE Lead" in escalation target |

### Overlay Coverage: COMPLETE (all ARCHITECT_* keys populated)

---

## 6. yolo-fe-qa.md

### Status: DIVERGED (significant)

The hand-authored FE QA has FE-specific content that the overlay LACKS, while the template has generic content the hand lacks.

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| HAND_RICHER | Persona archetype | DIVERGED | Hand: "QA lead bridging design and development" vs Overlay: "Seasoned QA Lead with independent verification discipline" |
| HAND_RICHER | Vocabulary domains | DIVERGED | Hand has FE-specific: design compliance (8 states), a11y (WCAG 2.1 AA), UX verification. Overlay has generic: goal-backward, evidence quality, PASS/PARTIAL/FAIL |
| HAND_RICHER | Communication standards | DIVERGED | Hand: "Design compliance is binary", "A11y = FAIL if missing". Overlay: "Report findings with evidence" |
| HAND_RICHER | Decision framework | DIVERGED | Hand: "Verify against design handoff artifacts". Overlay: "Must-have violation = FAIL" |
| HAND_RICHER | Verification tiers | DIVERGED | Hand: FE-specific checks (component existence, design tokens, a11y). Overlay: generic (artifact existence, frontmatter validity) |
| HAND_RICHER | Frontend-Specific Checks | MISSING from overlay | Design Compliance, Accessibility, UX Verification sections |
| HAND_RICHER | Output format | DIVERGED | Hand: "same schema as backend QA Lead". Overlay: detailed line-by-line format |
| HAND_RICHER | Escalation rows | DIVERGED | Hand: "Design compliance FAIL", "Accessibility FAIL". Overlay: generic "Verification findings" |
| HAND_RICHER | Constraints wording | DIVERGED | Hand: "Code quality = FE QA Code Engineer's job" |
| HAND_RICHER | Context receives | DIVERGED | Hand: "design-handoff.jsonl (from UX)". Overlay: ".qa-gate-results.jsonl" |
| HAND_RICHER | Review ownership | DIVERGED | Hand: "design compliance and accessibility". Overlay: generic "verification thoroughness" |
| TEMPLATE_RICHER | Goal-Backward Methodology | MISSING | 5-step methodology |
| TEMPLATE_RICHER | Continuous QA | MISSING | Gate-Aware Verification, Incremental Mode, Override Protocol |

### Overlay Coverage: NEEDS BACK-PORT. QA_* keys contain generic values; need FE-specific vocabulary, verification tiers, and FE checks.

---

## 7. yolo-fe-qa-code.md

### Status: DIVERGED (significant)

Similar to QA -- hand-authored has FE-specific content missing from overlay.

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| HAND_RICHER | Persona archetype | DIVERGED | Hand: "Engineer running automated FE quality checks" vs Overlay: "Frontend code-level verification engineer" |
| HAND_RICHER | Vocabulary domains | DIVERGED | Hand: component test execution, a11y linting, bundle analysis, performance. Overlay: TDD compliance, severity classification, gate result consumption |
| HAND_RICHER | Communication standards | DIVERGED | Hand: "High coverage + shallow assertions = false confidence", "A11y linting catches 30%", "Bundle regressions compound" |
| HAND_RICHER | Decision framework | DIVERGED | Hand: "Test quality over quantity", "Performance budgets are hard limits". Overlay: "Test failures = critical, always" |
| HAND_RICHER | Phase 0-1 description | DIVERGED | Hand: concise "Same structure as backend QA Code. FE-specific tools: vitest/jest, axe-core..." vs Overlay: full expanded protocol |
| HAND_RICHER | Phase 2 description | DIVERGED | Hand: "Bundle analysis, performance, design token compliance, a11y depth" vs Overlay: numbered checks |
| HAND_RICHER | Phase 3 description | DIVERGED | Hand: "Test coverage, interaction coverage, edge cases" vs Overlay: numbered checks |
| HAND_RICHER | Output format | DIVERGED | Hand: "same schema as backend QA Code" vs Overlay: full line format |
| HAND_RICHER | Escalation wording | DIVERGED | Hand: "FE Senior, FE Dev" in never-escalate vs Overlay: "Senior, Dev" |
| HAND_RICHER | Review ownership | DIVERGED | Hand: "component tests, bundle size, and a11y compliance" vs Overlay: generic |
| HAND_RICHER | Context receives | DIVERGED | Hand: "design-tokens.jsonl (from UX, for validation)" vs Overlay: ".qa-gate-results.jsonl" |
| TEMPLATE_RICHER | Continuous QA | MISSING | Gate Result Consumption, Cached Pass, Aggregation sections |
| TEMPLATE_RICHER | Constraints detail | MISSING | "If no test suite exists: report as finding", "If no linter configured: skip" |

### Overlay Coverage: NEEDS BACK-PORT. QA_CODE_* keys contain overlay-specific values that lose FE-specific richness.

---

## 8. yolo-fe-security.md

### Status: COSMETIC (near-parity)

The overlay already contains ALL FE-specific content for security. Only cosmetic differences.

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| COSMETIC | Title "Frontend" vs "FE" | HAND_RICHER | Template uses DEPT_LABEL |
| COSMETIC | Department label in hierarchy | DIVERGED | Hand: "Department: Frontend" vs Template: "Department: FE" |
| COSMETIC | Review ownership wording | DIVERGED | Hand: "frontend" vs Template: "FE" |

### Overlay Coverage: COMPLETE (all SECURITY_* keys populated)

---

## 9. yolo-fe-documenter.md

### Status: DIVERGED (significant)

The hand-authored file has different FE doc types and scope than the overlay.

| Category | Gap | Direction | Detail |
|----------|-----|-----------|--------|
| HAND_RICHER | Description scope | DIVERGED | Hand: "prop tables, state flow diagrams, Storybook-style usage examples". Overlay: "component API docs, Storybook entries, design token references" |
| HAND_RICHER | Tools | DIVERGED | Hand: NO Bash tool. Overlay: HAS Bash tool |
| HAND_RICHER | Intro scope | DIVERGED | Hand: "prop tables, state flow diagrams, Storybook-style usage examples, accessibility checklists". Overlay: "Storybook story references, design token usage guides, CHANGELOG entries" |
| HAND_RICHER | Hierarchy receives | DIVERGED | Hand: "component source, and design-tokens.jsonl". Overlay: "modified file list" |
| HAND_RICHER | Persona archetype | DIVERGED | Hand: "Frontend Documentation Specialist with component-first orientation". Overlay: "Technical Writer with component-first documentation approach" |
| HAND_RICHER | Vocabulary domains | DIVERGED | Hand: Component API (props/events/slots/refs), State management, Design tokens, Accessibility. Overlay: Component API docs, Design token docs, Storybook refs, Changelog |
| HAND_RICHER | Communication standards | DIVERGED | Hand: "Every component doc includes a minimal usage example", "Prop tables include type/default/required/description", "Accessibility notes are mandatory" |
| HAND_RICHER | Doc types | DIVERGED | Hand: component/state-flow/usage/a11y/token-usage. Overlay: component/token/storybook/changelog |
| HAND_RICHER | Entry examples | DIVERGED | Hand has state-flow and a11y entries. Overlay has token and storybook entries |
| HAND_RICHER | Scope items | DIVERGED | Hand: 5 items including state flow and a11y checklist. Overlay: 4 items including CHANGELOG |
| HAND_RICHER | Effort-based fast | DIVERGED | Hand: "Component prop tables only". Overlay: "CHANGELOG entries only" |
| HAND_RICHER | Constraints | DIVERGED | Hand: "No Bash execution". Overlay: no such constraint (has Bash tool) |
| HAND_RICHER | Context receives | DIVERGED | Hand: "component source + codebase mapping (ARCHITECTURE.md, STRUCTURE.md)". Overlay: "component-specs.jsonl" |
| HAND_RICHER | Context never | DIVERGED | Hand: "backend scripts, UX user flows, decisions.jsonl". Overlay: "QA artifacts from other departments, backend scripts" |

### Overlay Coverage: NEEDS BACK-PORT. DOCUMENTER_* keys diverge significantly from hand-authored FE content.

---

## Summary

| Agent | Status | Overlay Back-port Needed? |
|-------|--------|--------------------------|
| fe-dev | TEMPLATE_RICHER | No -- overlay complete, hand file is missing template sections |
| fe-senior | TEMPLATE_RICHER | No -- overlay complete, hand file is missing template sections |
| fe-tester | TEMPLATE_RICHER | No -- overlay complete, hand file is missing template sections |
| fe-lead | TEMPLATE_RICHER | No -- overlay complete, hand file is missing template sections |
| fe-architect | TEMPLATE_RICHER | No -- overlay complete, hand file is missing template sections |
| fe-security | COSMETIC | No -- overlay complete, only dept label cosmetics |
| **fe-qa** | **DIVERGED** | **Yes -- QA_* keys need FE-specific vocabulary, verification tiers, FE-specific checks** |
| **fe-qa-code** | **DIVERGED** | **Yes -- QA_CODE_* keys need FE-specific vocabulary, verification descriptions, context** |
| **fe-documenter** | **DIVERGED** | **Yes -- DOCUMENTER_* keys need FE-specific doc types, scope, vocab, entry examples** |

### Key Finding

6 of 9 FE agents (dev, senior, tester, lead, architect, security) have COMPLETE overlay coverage. The template is actually RICHER than the hand-authored files because templates include sections added after the original FE agents were written.

3 of 9 FE agents (qa, qa-code, documenter) have DIVERGED overlay content where the overlay values are too generic and lose FE-specific richness from the hand-authored files. These 3 need back-port work.
