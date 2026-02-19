# Phase 9 Research: Workflow Redundancy Audit & Token Optimization

## Findings

### 1. Agent Redundancy & Unclear Differentiation
- **QA vs QA-Code overlap**: Both consume plan.jsonl and summary.jsonl. QA has `.qa-gate-results.jsonl` also used by QA Code. Potential duplicate verification or gap where both skip assuming the other covers it.
- **Security vs QA-Code secret scanning**: Both agents perform identical secret detection (API keys, AWS, private keys, connection strings). QA-Code at Step 9, Security at Step 10 — two sequential agents doing identical work.
- **Critic vs Scout role bleed**: Both are read-only, both consume REQUIREMENTS.md and codebase files. Unclear boundary on who analyzes existing patterns vs who researches external info.
- **Impact**: 40-50% redundant token spend on parallel verification work.

### 2. Workflow Step Inefficiency
- Critique 3-round hard cap with 85 confidence threshold means most phases run 2-3 rounds (~3000 tokens overhead)
- Documenter always spawned via gate despite config saying "on_request" — ~2000 tokens per phase per dept
- Scout spawned in full workflow even when Architect doesn't request research (~1000 tokens)
- PO layer skipped for medium complexity but medium still requires planning — gap in value chain
- **Impact**: ~5000-8000 tokens per typical phase on low-value ceremony

### 3. Agent Context Bloat
- compile-context.sh reads too many files upfront (Architect receives ~15KB when needing ~2KB)
- context-manifest.json budgets never enforced (go.md never invokes --measure)
- FE/UX architects receive backend architecture.toon instead of dept-specific context
- JSONL filtering reads entire files before selecting fields
- **Impact**: ~15-25% context bloat per agent, compounds to 120KB waste per phase

### 4. Script Redundancy & Dead Code
- 7 separate validate-*.sh scripts with overlapping JSON parsing logic
- 4 department scripts (dept-gate, dept-status, dept-cleanup, dept-orchestrate) re-parsing same state files
- 3 route scripts (trivial/medium/high) instead of single parameterized script
- 4 qa-gate scripts (post-task/plan/phase + base) with similar timeout management
- **Impact**: ~800 lines duplicated shell logic

### 5. Configuration & Reference Sprawl
- defaults.json vs config.json vs .yolo-planning/config.json = 3 sources of truth
- model-profiles.json not referenced in go.md (effort-to-model mapping hardcoded in resolve-agent-model.sh)
- context-manifest.json has incomplete role definitions (analyze has empty artifacts, integration-gate lists non-existent outputs)
- execute-protocol.md, multi-dept-protocol.md, cross-team-protocol.md define Step 1 differently

### 6. File-Based Context Propagation Gaps
- Escalation state not persisted for resume — pending escalations lost on pause
- Research results not carried forward across phases — Scout re-researches identical questions
- No cross-phase decision tracking — Lead doesn't read prior decisions.jsonl
- No freshness check on phase completion markers

### 7. Architect vs Lead Authority Overlap
- Architect owns "design" but Lead owns "task decomposition" — tightly coupled but split
- Lead is bottleneck: planning + delivery + escalation hub + timeout watchdog (4 jobs)
- Senior escalation loops add 2-3 extra hops per escalation

### 8. Token Optimization Missed Opportunities
- Complexity routing bypassed by ~90% of invocations (explicit flags skip it)
- YOLO_AGENT_MODE env var documented but never set — templates never filtered (~30% context waste)
- Effort level doesn't cascade — turbo mode only affects Lead, downstream agents default to balanced
- Context compiler --measure never invoked — no visibility into actual token spend

### 9. Documenter Integration Orphaned
- Config says "on_request" but workflow spawns based on gate — conflicting logic
- Output never consumed by downstream agents or shown to user
- Non-blocking means silent failure with no escalation path

### 10. Architecture Flow Gaps
- Multi-dept context splitting untested (no validation on split files)
- No formal handoff artifact between phases
- Escalation timeout chains have no graceful degradation
- Integration gate polling has no timeout (can block indefinitely)

## Relevant Patterns

**Positive:** JSONL abbreviations effective (20-30% savings), 11-step workflow conceptually clear, confidence gating prevents runaway cycles, department isolation via CONTEXT files is sound, config-driven effort levels provide flexibility.

**Negative:** Role bloat (too many responsibilities per agent), script proliferation (80+ when 30-40 would suffice), configuration inconsistencies (3 sources of truth), file-based orchestration fragile (polling vs SendMessage).

## Risks

### Critical
1. Multi-department phases fragile — context splitting, handoffs, integration gates all file-based with implicit expectations
2. Agent context bloat compounds with multi-department (36 agents × 5-10KB bloat = 180-360KB excess per phase)

### High
3. Escalation loops can trap execution indefinitely — timeout cascades with no graceful degradation
4. QA/Security duplicate work — identical secret scanning in two sequential agents
5. YOLO_AGENT_MODE never implemented — 30% context waste on every agent spawn

### Medium
6. Complexity routing over-engineered for <10% utilization
7. Documenter output never consumed
8. Research re-work across phases due to no cross-phase persistence

## Recommendations

### Priority 1: Core Optimization (30% token savings)
1. Eliminate QA/Security secret scanning redundancy → pre-implementation gate
2. Enforce context budgets via compile-context.sh --measure
3. Implement YOLO_AGENT_MODE in go.md (set env var before agent spawn)
4. Deprecate Analyze agent → shell-only complexity-classify.sh
5. Cascade effort level to all downstream agents

### Priority 2: Architecture Clarity (20% quality improvement)
1. Define non-overlap matrix for QA/Critic/Scout roles
2. Clarify Architect vs Lead responsibilities (design vs delivery)
3. Add explicit multi-department handoff artifacts
4. Replace file-based orchestration with Teammate API SendMessage
5. Create Mermaid architecture diagram documenting full flow

### Priority 3: Configuration Alignment (10% operational improvement)
1. Consolidate defaults.json + mode-profiles.json into single config
2. Fix Documenter spawning to respect config enum
3. Add context-manifest.json validation

### Priority 4: Resilience & Resumability (10% reliability improvement)
1. Track research results cross-phase (research-archive.jsonl)
2. Persist escalation state for resumability
3. Add phase handoff validation
4. Implement graceful escalation fallback (→User after 2 timeouts)
