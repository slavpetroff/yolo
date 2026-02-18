# Phase 7: Architecture Audit & Optimization — Research

## Findings

### Critical Issues

**CI-1: Dual Classification Redundancy**
`complexity-classify.sh` and the Analyze agent (`yolo-analyze.md`) both perform complexity classification. The shell script runs pattern matching, then the Analyze agent runs an LLM call for the same purpose. This means every task is classified twice — once cheaply (shell) and once expensively (LLM). Need to consolidate into single classification path.

**CI-2: Department Guard Gaps**
`scripts/department-guard.sh` blocks cross-department file writes at the hook level, but the guard only checks file paths — it does not verify artifact content. An agent could write a correctly-pathed file containing content from another department's domain. The guard needs content-awareness or the artifact format needs department attribution.

**CI-3: Context Manifest Incomplete Coverage**
`config/context-manifest.json` defines per-role context packages, but not all 36 agents have manifest entries. Agents without manifest entries get full context (wasteful) or no context (broken). Every agent role needs a manifest entry.

**CI-4: Escalation Chain Dead Ends**
`escalation.jsonl` logs escalations but the escalation chain (Dev → Senior → Lead → Owner) has no timeout handling for intermediate steps. If a Senior fails to respond to an escalation, it sits indefinitely. Need timeout-based auto-promotion to next level.

**CI-5: Analyze Agent Hardcoded to Opus**
`yolo-analyze.md` is hardcoded to always use Opus regardless of model profile. In budget mode, this is the single most expensive call. The classification task could use Sonnet with minimal accuracy loss for trivial/medium cases, reserving Opus for ambiguous edge cases.

### Redundancy

**R-1: Department Agent File Duplication (~85%)**
`yolo-dev.md`, `yolo-fe-dev.md`, and `yolo-ux-dev.md` share ~85% identical content — only the department scope section and file path patterns differ. Same for Senior, Tester, QA, QA-Code, Security, Documenter triplicates. This is 9 role types × 3 departments = 27 files where a template + dept overlay pattern would eliminate ~18 files worth of duplicated tokens.

**R-2: TOON File Duplication**
`references/departments/backend.toon`, `frontend.toon`, `uiux.toon` have significant overlap in workflow steps, communication protocols, and artifact format descriptions. A shared base TOON with dept-specific overlays would reduce total TOON token count by ~40%.

**R-3: Reference Packages Duplicate Agent Prompts**
`references/packages/*.toon` files duplicate content already in the agent `.md` files. Each package adds ~500 tokens of redundant role definition. If compile-context.sh already reads the agent file, the package file is pure overhead.

**R-4: Handoff Schemas Repeated Across Docs**
`references/handoff-schemas.md` defines schemas that are also described inline in agent files and `artifact-formats.md`. Triple definition means triple maintenance burden and divergence risk.

**R-5: Execute Protocol Duplicates go.md Logic**
`references/execute-protocol.md` and `commands/go.md` both describe the execution flow. Some steps are defined in both files with slightly different wording, creating ambiguity about which is authoritative.

### Token Optimization Opportunities

**T-1: Compile-Context Could Be Smarter**
`scripts/compile-context.sh` includes all JSONL artifacts for a phase. For later plans in a phase, earlier plans' full artifacts are included even though only their summaries matter. A rolling summary approach would cap context growth.

**T-2: Agent Prompts Include Unused Sections**
Agent `.md` files include sections for every mode/capability even when only one mode is needed for a given task. A mode-filtered prompt would eliminate 30-50% of agent prompt tokens per invocation.

**T-3: JSONL Abbreviated Keys Save Tokens But Cost Readability**
The abbreviated key format (`sg`, `cf`, `ra`, `rt`, `mh`, etc.) saves tokens but creates a learning curve. Some keys are ambiguous (`t` = title? type? task?). A lookup table in the agent prompt costs tokens to include. Consider whether the savings outweigh the disambiguation cost.

**T-4: Full Test Suite in Context**
When QA runs, it receives the full test file listing. For phases with 1550 tests, this is thousands of tokens of file paths. QA only needs the test files relevant to the current phase's changes.

**T-5: Critique Loop Worst Case**
With 3 rounds × 3 departments, a single critique phase can generate 9 critique.jsonl entries. Each round includes prior rounds' feedback, creating exponential context growth. The confidence gate (85) helps but doesn't cap the per-round growth.

**T-6: PO + Questionary on Medium Path**
Medium-complexity tasks still spawn the PO-Questionary loop when `po.enabled=true`. For medium tasks, the scope is usually clear from the initial request. The PO loop adds ~2000 tokens of overhead for minimal value on medium-path tasks.

### Context Gaps

**CG-1: No Cross-Phase Context**
When planning Phase N, there's no structured summary of what Phases 1 through N-1 built. The Lead must infer from file existence. A phase-completion manifest would provide this.

**CG-2: Agent Self-Knowledge Gap**
Agents don't know which other agents exist or what they do. When a Dev needs to reference Frontend work, it has no structured way to discover `yolo-fe-dev.md` or its outputs. The context manifest helps but doesn't include agent-to-agent discovery.

**CG-3: Config State Not in Agent Context**
Agents receive code context but not config state. A Dev doesn't know if `documenter` is `on_request` or `always`, so it can't adjust its behavior accordingly. Config-relevant keys should be in the agent's context package.

**CG-4: Error Recovery Context**
When a task fails and is retried, the retry agent doesn't receive the error context from the first attempt. This leads to repeated failures. The error should be part of the retry context.

**CG-5: Test Results Not Fed Back**
Tester agents produce `test-results.jsonl` but this isn't fed back to the Dev who wrote the code. If tests fail, the Dev discovers this only through escalation, not through direct feedback.

**CG-6: No Codebase Delta Context**
Between phases, the codebase changes but the codebase map (`codebase/INDEX.md`) doesn't update. Phase 6's Lead plans against a stale codebase understanding. A delta-aware context update would prevent this.

### Communication & Handoff Gaps

**CH-1: Backend-UX Firewall Too Strict**
The rule "Backend NEVER communicates with UI/UX directly" means design decisions in UX (component APIs, data shapes) can't be validated against backend capabilities until Integration Gate. Late discovery of mismatches is expensive. Consider a structured API contract artifact shared between Frontend and Backend that UX can reference.

**CH-2: No Handoff Acknowledgment**
When a Lead hands off to Senior, there's no acknowledgment artifact. If the Senior receives corrupted or incomplete context, it proceeds anyway. A handoff-receipt would catch context loss early.

**CH-3: Scout Results Not Shared Across Departments**
When Scout researches a topic for Backend, the findings aren't available to Frontend or UX even if relevant. Research should be phase-scoped, not department-scoped.

**CH-4: Integration Gate Has No Pre-Check**
The Integration Gate runs after all departments complete. If one department's output is fundamentally incompatible, all three departments' work is wasted. A lightweight pre-integration check at the department Lead level could catch showstoppers earlier.

**CH-5: PO Feedback Loop Is One-Way**
PO Q&A after Integration Gate sends feedback to the user, but user feedback doesn't flow back to specific departments in a structured way. The "Patch" path goes to a dept Senior, but the Senior doesn't receive the PO's specific concerns — just a generic "fix this."

### Workflow Bottlenecks

**WB-1: Serial Critique Across Departments**
Critique runs sequentially per department (Backend → Frontend → UX). Since critique is independent per department, it could run in parallel, saving 2x the critique time.

**WB-2: Architecture Step Always Required for High Path**
Even when the Architect's output would be nearly identical to the Lead's plan (simple high-complexity tasks), the full Architect → Design Review pipeline runs. A "fast-track high" option for well-understood patterns would save tokens.

**WB-3: Code Review Blocks QA**
Senior code review must complete before QA can start. For independent concerns (style vs correctness), these could partially overlap.

**WB-4: Single Integration Gate**
One Integration Gate for all departments means the slowest department blocks the entire pipeline. A per-department readiness signal with partial integration checks would reduce wait time.

### Quality Risks

**QR-1: No Test Isolation Verification**
Tests exist (1550 total) but there's no verification that tests are isolated — a test passing could depend on side effects from prior tests. A randomized test order run would catch this.

**QR-2: Senior Reviews Own Specs**
In the current flow, Senior enriches the plan, then Dev implements, then Senior reviews. The Senior is reviewing against specs they wrote — no independent perspective. A cross-department Senior review or a second Senior would add independence.

**QR-3: Critique Confidence Self-Reported**
The Critic self-reports confidence (cf field). There's no external validation of whether 85 confidence actually correlates with quality. The threshold could be calibrated against QA outcomes.

**QR-4: Trivial Path Skips Code Review**
Trivial tasks go directly to Senior without code review. While trivial by definition, even trivial changes can introduce bugs. A lightweight automated check (lint + type check) would add minimal overhead.

**QR-5: No Regression Gate Between Phases**
Phases run sequentially but there's no automated regression check between phases. Phase 3 could break Phase 1's features without detection until Phase 6's full regression run.

**QR-6: Hallucination Risk in Agent Chains**
Long agent chains (PO → Questionary → Lead → Architect → Senior → Dev) amplify hallucination risk — each agent interprets the prior's output. By step 6, the original intent may be distorted. Structured handoff schemas help but don't eliminate semantic drift.

### Config Simplification

**CS-1: Too Many Feature Flags**
Config has 15+ v2/v3 feature flags, all currently false. These add cognitive load and code complexity (every feature checks its flag). Consider graduating stable features and removing their flags.

**CS-2: Model Profile Indirection**
Model selection goes through 3 layers: profile → override → agent-specific. This indirection makes it hard to know which model an agent actually uses. A resolved-model diagnostic would help.

**CS-3: Agent Max Turns Per-Agent Config**
`agent_max_turns` has per-agent overrides in config. With 36 agents, this could become unwieldy. A per-tier default (simple/medium/complex) with per-agent overrides only for exceptions would scale better.

**CS-4: Duplicate Config Paths**
Some settings exist in both `config/defaults.json` and `commands/go.md` hardcoded defaults. When config is missing, go.md falls back to hardcoded values that may diverge from defaults.json.

**CS-5: QA Skip Agent List**
`qa_skip_agents: ["docs"]` is a blocklist approach. With 36 agents, an allowlist of agents that DO need QA would be shorter and more maintainable.

**CS-6: Department Enable/Disable Granularity**
Departments are enabled/disabled as units. Some projects need Backend + partial Frontend (API-only, no UI components). Per-agent-role enable/disable within a department would add flexibility without full department overhead.

## Estimated Impact

- Token savings: 15,000-20,000 tokens per full-ceremony phase (~25-35% reduction)
- Primary savings from: R-1 (template dedup), T-1 (rolling summaries), T-2 (mode filtering), T-6 (PO skip on medium)
- Quality improvements from: CI-1 (single classification), CG-4 (error recovery context), QR-4 (trivial lint), CH-4 (pre-integration check)
- Velocity improvements from: WB-1 (parallel critique), WB-4 (partial integration)

## Recommendations

1. **Highest ROI first**: R-1 (agent dedup) and T-2 (mode filtering) together save the most tokens with lowest risk
2. **Quick wins**: CS-1 (remove dead flags), T-6 (skip PO on medium), QR-4 (trivial lint)
3. **Architectural**: CI-1 (single classification), CH-4 (pre-integration check) require design but high impact
4. **Defer**: CS-6 (per-role enable/disable) is nice-to-have but adds complexity
