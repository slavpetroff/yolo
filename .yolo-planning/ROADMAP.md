# Workflow Hardening, Org Alignment & Optimization Roadmap

**Goal:** Workflow Hardening, Org Alignment & Optimization

**Scope:** 5 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|---------|
| 1 | Complete | 3 | 11 | 8 |
| 2 | Complete | 4 | 17 | 20 |
| 3 | Pending | 0 | 0 | 0 |
| 4 | Pending | 0 | 0 | 0 |
| 5 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: Bootstrap & Naming Fixes](#phase-1-bootstrap-naming-fixes)
- [x] [Phase 2: R&D Research Flow & Context Optimization](#phase-2-r-d-research-flow-context-optimization)
- [ ] [Phase 3: Company Org Alignment & Review Patterns](#phase-3-company-org-alignment-review-patterns)
- [ ] [Phase 4: Continuous QA System](#phase-4-continuous-qa-system)
- [ ] [Phase 5: Escalation Gates & Owner-User Loop](#phase-5-escalation-gates-owner-user-loop)

---

## Phase 1: Bootstrap & Naming Fixes

**Goal:** Fix CLAUDE.md override bug in bootstrap scripts and standardize all artifact naming conventions to eliminate unnecessary LLM error-recovery calls

**Requirements:** REQ-01, REQ-02

**Success Criteria:**
- bootstrap-claude.sh preserves existing CLAUDE.md sections (test with pre-existing file)
- Naming validation script catches all inconsistencies
- Canonical naming patterns documented in references/
- Zero naming-related LLM error recovery in plan validation

**Dependencies:** None

---

## Phase 2: R&D Research Flow & Context Optimization

**Goal:** Add research phase to the 10-step workflow and create per-agent context filtering scripts that reduce token overhead by delivering only needed fields

**Requirements:** REQ-03, REQ-04

**Success Criteria:**
- Scout research step integrated before Architecture in execute-protocol.md
- Critic findings auto-feed into Scout research brief
- Per-agent context filter scripts exist for all 26 agents
- Agent→field mapping documented and enforced
- Measurable token reduction vs full-context baseline

**Dependencies:** Phase 1

---

## Phase 3: Company Org Alignment & Review Patterns

**Goal:** Align agent hierarchy with real company processes — add missing protocols, review ownership language, and cross-team communication patterns

**Requirements:** REQ-05, REQ-06

**Success Criteria:**
- All reviewing agent prompts (16 of 26) include review ownership language patterns
- R&D→Architect handoff protocol documented and enforced
- Change management loops within teams (Senior↔Dev revision cycle) formalized
- Cross-team status reporting protocol added
- Audit checklist comparing YOLO vs real company passes

**Dependencies:** Phase 2

---

## Phase 4: Continuous QA System

**Goal:** Transform QA from phase-end-only to continuous — add QA gates at post-task, post-plan, and post-phase levels matching real company QA processes

**Requirements:** REQ-07

**Success Criteria:**
- Post-task QA gate runs unit tests after each Senior-approved batch
- Post-plan QA gate runs integration verification after plan completion
- Post-phase QA gate runs full system verification
- QA failures block progression at each level
- QA agent prompts updated for continuous operation

**Dependencies:** Phase 3

---

## Phase 5: Escalation Gates & Owner-User Loop

**Goal:** Fix the broken escalation path so Dev blockers reach the user through Owner, and user feedback flows back down to unblock Dev — complete the round-trip

**Requirements:** REQ-08, REQ-09

**Success Criteria:**
- Dev blocker escalates through Senior→Lead→Owner→User (verified end-to-end)
- Owner uses AskUserQuestion to present blocker options to user
- User feedback flows Owner→Lead→Senior→Dev with verification gates
- Escalation timeout triggers automatic Owner involvement
- Integration test covers full escalation round-trip

**Dependencies:** Phase 4

