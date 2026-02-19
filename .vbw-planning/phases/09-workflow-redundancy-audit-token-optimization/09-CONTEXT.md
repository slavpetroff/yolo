# Phase 9: Workflow Redundancy Audit & Token Optimization — Context

Gathered: 2026-02-19
Calibration: architect

## Phase Boundary
Comprehensive audit and optimization of the YOLO engine for token efficiency, workflow redundancy elimination, architecture clarity, and documentation. Produces Mermaid architecture diagrams, strict agent non-overlap matrix, consolidated scripts, and effort-aware step skipping.

## Decisions

### Agent Consolidation Strategy
- Critic is essential and must remain separate — receives Architect output to challenge decisions ("Architect decided X, find critiques")
- Merge QA + QA-Code into single QA agent with two modes (plan-level vs code-level)
- Move secret scanning exclusively to Security agent — remove from QA-Code entirely
- Define strict non-overlap matrix for all agent pairs
- Sharpen boundaries for Critic vs Scout: Critic challenges architectural decisions, Scout researches external patterns/libraries

### Script Consolidation Depth
- Full consolidation approach: shared lib/yolo-common.sh library + parameterized scripts
- Merge groups: validate.sh --type (replaces 7 scripts), dept-state.sh --action (replaces 4), route.sh --path (replaces 3), qa-gate.sh --tier (replaces 4)
- Extract common functions: JSON parsing, state reading, exit code conventions into library

### Effort Cascading Design
- Step-skip approach (NOT per-agent degradation)
- When an agent runs, it always runs at full quality regardless of effort level
- turbo: skip Critic + Scout + Documenter + Security + second review round
- fast: skip Documenter + second review round
- balanced: full 11-step workflow
- thorough: full workflow + extra validation rounds
- Effort level controls which steps execute, not how they execute

### Mermaid Diagram Scope
- Multiple focused diagrams in docs/ARCHITECTURE.md (not single monolithic diagram)
- Diagram 1: Agent hierarchy + department org chart
- Diagram 2: Workflow steps + data flow (11-step with artifacts)
- Diagram 3: Complexity routing decision tree (trivial/medium/high paths)
- Diagram 4: Hook system + script interactions
- Purpose: enable ongoing audit of workflow gaps, redundant agents, missing connections

### Open (Claude's discretion)
- Context budget enforcement strategy (compile-context.sh --measure integration)
- Cross-phase research persistence format (research-archive.jsonl)
- Escalation state persistence for resumability
- Config consolidation approach (defaults.json + mode-profiles.json merge)

## Deferred Ideas
None.
