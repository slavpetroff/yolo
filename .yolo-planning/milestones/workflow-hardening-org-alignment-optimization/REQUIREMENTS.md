# Requirements

Defined: 2026-02-17

## Problem Statement

YOLO's workflow has accumulated several gaps after 3 milestones of feature development: bootstrap scripts silently override CLAUDE.md, artifact naming inconsistencies waste LLM tokens on error recovery, no R&D/research phase exists before architecture, agents receive full context instead of filtered fields, QA runs only at phase-end instead of continuously, escalation paths from Dev→Owner→User are broken (Owner never surfaces blockers to user), and review handoffs lack ownership language ("this is my dev's work, review thoroughly").

## Requirements

### REQ-01: Fix CLAUDE.md bootstrap override bug
**Must-have**
bootstrap-claude.sh must preserve existing CLAUDE.md sections. Investigate root cause of silent overrides. Add section-preservation logic and guard against full-file replacement.

### REQ-02: Standardize artifact naming conventions
**Must-have**
Eliminate naming inconsistencies across plans, summaries, contexts, and handoff files that cause extra LLM calls for error recovery. Create naming validation script. Document canonical naming patterns.

### REQ-03: Add R&D/research phase to workflow
**Must-have**
Insert research step before architecture. Critic findings feed into Scout research. Scout produces research brief for Architect. Research also available pre-Critic for best-practices discovery. Integrate into 10-step workflow.

### REQ-04: Per-agent context filtering scripts
**Must-have**
Create scripts that extract only the fields each agent needs from plans/artifacts. Each agent receives a filtered context file instead of full artifacts. Map agent→required fields. Reduce token overhead.

### REQ-05: Company org alignment — missing protocols
**Must-have**
Audit current agent hierarchy against real company processes. Add missing protocols: R&D→Architect handoff, continuous QA loops, change management within teams, Senior→Dev review ownership language, cross-team status reporting.

### REQ-06: Review ownership language patterns
**Must-have**
Incorporate review instruction patterns: Senior reviewing Dev says "This is my dev's implementation, revise and review thoroughly." Owner reviewing Architect says "This is my architect's overview, revise and review thoroughly." Builds accountability and thoroughness.

### REQ-07: Continuous QA system
**Must-have**
QA must run after each Senior-approved task batch, not only at phase end. Add QA gates at: post-task (unit tests), post-plan (integration), post-phase (system). Map to real company QA process.

### REQ-08: Owner escalation gates — blocker→user path
**Must-have**
When Dev blocker escalates through Senior→Lead→Owner, Owner MUST surface it to the user via AskUserQuestion. Present options, discuss, gather feedback, incorporate. Currently this path is never executed despite existing in protocol.

### REQ-09: Escalation loop completion
**Must-have**
After Owner gets user feedback on a blocker, the resolution must flow back down: Owner→Lead→Senior→Dev with the user's decision. Verify the full round-trip works. Add verification gates.

## Out of Scope

- Cross-project learning (deferred)
- New department types (only fixing existing 4)
- Teammate API changes (already shipped in previous milestone)
- Model profile changes
