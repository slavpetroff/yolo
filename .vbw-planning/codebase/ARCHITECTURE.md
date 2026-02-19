# YOLO Architecture

## High-Level Pattern: Plugin + Agent Hierarchy + Template System + SQLite Store

1. **Plugin Core** (commands/ + hooks/) — Single entry point (`/yolo:go`)
2. **Company Hierarchy** (agents/ + references/) — 38 specialized agents in 4 departments + PO layer
3. **Template System** (agents/templates/ + agents/overlays/) — 9 role templates x 3 dept overlays, mode-filtered
4. **State Machine** (phase-detect.sh + phase dirs) — Workflow progression tracking
5. **Hook System** (hooks.json + scripts/) — Lazy execution + graceful degradation
6. **Complexity Router** (complexity-classify.sh) — Trivial/medium/high path selection
7. **SQLite Artifact Store** (yolo.db + 31 db/ scripts) — Sole artifact persistence + FTS5 search

## Component Interaction

**User -> go.md (Command)**
- Parses input: flags, natural language intent, or state-based auto-detect
- Routes to mode: Init, Bootstrap, Scope, Plan, Execute, Discuss, Archive
- Runs complexity classification first (complexity-classify.sh)
- Acts as Owner proxy (no subagent contacts user directly)

**Complexity Classification -> Path Selection**
- complexity-classify.sh: keyword + dept count + phase state -> trivial/medium/high
- Trivial: Direct fix, trivial-lint.sh verification, skip Architect/Lead ceremony
- Medium: Bounded scope, single-dept, skip Analyze agent when confidence >= threshold
- High: Full 11-step ceremony with all agents

**Mode -> Architect/Lead (via Task or Teammate API)**
- Single-department: go.md -> Lead
- Multi-department: go.md -> Owner -> parallel Leads (UX first, then FE+BE)
- Each agent receives scoped context via compile-context.sh

**Agent Escalation Chain (STRICT)**
- Dev -> Senior -> Lead -> Architect (single-dept)
- Dev -> Senior -> Lead -> Architect -> Owner (multi-dept)
- Each level can resolve or escalate; level-skipping forbidden

## Template System

```
agents/templates/{role}.md       9 role templates with {{PLACEHOLDER}} markers
      + mode markers:            <!-- mode:plan,implement --> ... <!-- /mode -->
agents/overlays/{dept}.json      3 dept overlays (common + per-role placeholder values)
scripts/generate-agent.sh        Merges template + overlay via jq substitution
config/mode-profiles.json        6 modes: plan, implement, review, qa, test, full
                                 |
agents/yolo-{prefix}{role}.md    Generated agent files
```

- Templates use `{{KEY}}` placeholders replaced by overlay JSON values
- Mode markers (`<!-- mode:X,Y -->`) enable section filtering per workflow step
- Overlay `common` section provides shared dept values; role sections override per-agent

## Data Flow (Single Phase Execution)

```
Complexity Classification (complexity-classify.sh)
    |
[if high] Critic (critique.jsonl)
    |
[if high] Scout (research.jsonl)
    |
Architect (architecture.toon)
    |
Lead ({NN-MM}.plan.jsonl files)
    |
Senior (enriches spec: ts field)
    |
Tester (test files + test-plan.jsonl)
    |
Dev (implements -> code + summary.jsonl + test-results.jsonl)
    |
Senior (code review -> code-review.jsonl)
    |
[if config] Documenter (docs.jsonl, Step 8.5)
    |
QA Lead + QA Code (verification.jsonl + qa-code.jsonl)
    |
Security (security-audit.jsonl, dept-specific checks)
    |
[if multi-dept] Integration Gate (pre-integration-check.sh -> full gate)
    |
Lead (sign-off: updates STATE.md, commits phase complete)
```

## Context Compilation (SQL-Only Design)

```
compile-context.sh
    |
    +-- yolo.db query                     Queries 20+ tables for role artifacts
    +-- config/context-manifest.json      (36 role entries, field filtering, token budgets)
    +-- references/packages/*.toon        (18 context packages: per-role reference bundles)
    +-- Rolling summaries                 (prior plan summaries only, caps context growth)
    +-- Error recovery context            (prior failure details on retry)
    +-- Department-scoped artifacts       (architecture.toon, plan.jsonl, etc.)
```

- **SQL path**: Fast queries on indexed tables, bounded results
- **Per-role field filtering**: Each role sees only relevant fields from artifacts
- **Token budgets**: Manifest defines per-role budget limits
- **Rolling summaries**: For plan NN-MM, includes summaries for plans < NN-MM only

## Artifact Store (SQLite)

- **Schema** (schema.sql): 500+ lines, 20+ tables for all artifact types
- **WAL mode**: Write-Ahead Logging; concurrent reads without blocking writes
- **FTS5**: Full-text search indexes on research, decisions, gaps, findings
- **Operations**: 31 db/ scripts for CRUD, search, import/export, migration, verification
- **State sync**: state-updater.sh writes STATE.md and DB on artifact writes
- **Migration**: migrate-milestone.sh for bulk phase import, verify-migration.sh for data integrity
- **Task queue**: Task claim/release/complete lifecycle via db/ scripts
- **Checkpointing**: Automated WAL checkpoint on phase transitions

## Design Patterns

1. **11-Step Workflow**: Critique -> Research -> Architecture -> Plan -> Design Review -> Test Authoring (RED) -> Implement -> Code Review -> Documentation (optional 8.5) -> QA -> Security -> Sign-off
2. **Company Hierarchy**: Architect (VP) -> Lead (Manager) -> Senior -> Dev
3. **Owner-First Proxy**: All user communication through go.md or Owner agent
4. **Context Isolation**: Strict file access boundaries per department
5. **Escalation Dedup**: Timeout tracking prevents duplicate escalations
6. **Graceful Degradation**: Hook wrapper catches errors, exits 0
7. **JSONL Abbreviated Keys**: 85-93% token savings vs Markdown
8. **Teammate API Fallback**: Circuit breaker for agent team reliability
9. **Template + Overlay Generation**: DRY agent definitions via parameterized templates
10. **Mode-Filtered Prompts**: Workflow-step-specific agent sections reduce token load
11. **Complexity Routing**: Trivial/medium/high paths skip unnecessary ceremony
12. **Rolling Summaries**: Prior-plan-only context prevents unbounded growth
13. **Pre-Integration Checks**: Sentinel-based readiness validation before full integration gate
14. **Confidence-Gated Classification**: Skip Analyze agent when keyword confidence is sufficient
15. **SQL Context**: DB queries for bounded, fast context compilation
16. **DB-Backed State**: DB persistence with STATE.md human-readable summary
