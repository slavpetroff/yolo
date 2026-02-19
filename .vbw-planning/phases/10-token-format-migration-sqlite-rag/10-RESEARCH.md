# Phase 10 Research: SQLite-Backed Artifact Store & Context Engine

## Findings

### Measured Token Waste (Current File-Based System)

| Waste Source | Per-Phase Tokens | Across 6 Phases | Root Cause |
|-------------|-----------------|-----------------|------------|
| Redundant file reads (ROADMAP 3x, REQUIREMENTS 3x, plan.jsonl 4x) | 11,434 | 68,600 | No cross-agent caching, stateless compilation |
| Unused artifact fields (Dev reads 10 fields, uses 5) | 1,770 total | 1,770 | Full-file reads, no field-level extraction |
| Budget overflow truncation (Architect loses 30-50% context) | ~2,000 lost | 12,000 | Lossy truncation with no recovery |
| compile-context.sh re-invocations (11+ per phase) | ~5,000 | 30,000 | Each agent spawn triggers fresh file scan |
| **Total measured waste** | **~20,000** | **~112,000** | **File-based stateless architecture** |

### Key Evidence

**Example: ROADMAP.md Triplication**
- Critic reads 15.75KB (3,937 tokens) → Architect reads same → Lead reads same
- Total: 11,811 tokens for 3,937 tokens of unique content (3x multiplier)
- With SQLite: parse once, query 3x = 400 tokens each = 1,200 total (9.8x improvement)

**Example: Dev Plan Reads**
- compile-context.sh reads plan.jsonl: 1,064 tokens
- Dev re-reads from disk: 1,064 tokens (same file, again)
- Dev actually uses: ~400 tokens (spec fields only)
- Per-plan waste: 1,664 tokens. Phase with 7 plans: 11,648 tokens wasted

**Example: Architect Immediate Overflow**
- ROADMAP.md alone = 3,937 tokens (79% of 5,000 budget)
- After adding REQUIREMENTS + project context: over budget by 620 tokens
- Triggers 3-level lossy truncation: architect sees headers but loses goals, details
- No recovery — silently degraded context leads to lower-quality architecture decisions

### Current Architecture Limitations

1. **Stateless file-based artifacts** — no session cache, no deduplication across agent spawns
2. **Per-agent context compilation** — each of 11+ workflow steps triggers fresh file I/O
3. **Full-file reads** — Architect/Critic/Lead receive unfiltered markdown, parse mentally
4. **Lossy truncation** — budget overflow degrades context irreversibly with no fallback
5. **No cross-agent batching** — 15 parallel agents each independently read same files

### Proposed Architecture: SQLite-Backed Context Engine

**Core shift:** File reads that cost thousands of tokens → bash script calls that return targeted results in tens of tokens.

| Operation | Current (file-based) | Proposed (SQLite) | Savings |
|-----------|---------------------|-------------------|---------|
| Dev gets task T3 spec | Read entire plan.jsonl (1,064 tokens) | `get-task.sh 09-02 T3` (75 tokens) | 93% |
| Architect gets phase goals | Read full ROADMAP.md (3,937 tokens) | `get-phase.sh 09 --goals` (200 tokens) | 95% |
| QA gets summaries to verify | Read all summary files (2,000+ tokens) | `get-summaries.sh 09 --status complete` (300 tokens) | 85% |
| Orchestrator tracks completion | Glob + Read each summary file | `check-phase-status.sh 09` (50 tokens) | 97% |
| Cross-phase research lookup | Read research-archive.jsonl (variable) | `search-research.sh "auth pattern"` (100 tokens) | 80-95% |

**Task queue semantics:**
- Lead writes tasks: `insert-task.sh --plan 09-02 --id T3 --spec "..." --deps T1,T2`
- Dev picks up work: `next-task.sh --dept backend --status pending` → returns exactly 1 task
- Dev completes: `complete-task.sh T3 --files "a.sh,b.sh" --summary "..."`
- QA polls: `next-review.sh --plan 09-02` → returns completed tasks needing review
- All atomic, transactional, no file coordination needed

**SQLite specifics:**
- WAL mode for concurrent read/write (readers never block writers)
- FTS5 for full-text search on research findings, decisions, gaps
- JSON columns for structured artifact data
- ON CONFLICT REPLACE for idempotent upserts
- Single .db file per milestone in .vbw-planning/

## Relevant Patterns

- sqlite3 is pre-installed on macOS/Linux (zero-dep compatible with jq)
- JSONL abbreviated keys map directly to SQL columns
- compile-context.sh's 1,225 lines of file scanning → ~200 lines of SQL queries
- context-manifest.json field filters → SQL SELECT column lists
- Existing bash script pattern (scripts/*.sh) naturally extends to DB query scripts

## Risks

1. **Migration complexity:** 40+ artifact types need schema + import scripts
2. **Agent prompt changes:** All agents currently told "Read plan.jsonl" — must learn "call get-task.sh"
3. **Parallel write contention:** WAL mode handles most cases, but 15 simultaneous INSERTs needs testing
4. **Debugging visibility:** `cat plan.jsonl` no longer works — need `sqlite3 db "SELECT ..."`
5. **Schema evolution:** Adding new artifact fields requires ALTER TABLE vs just appending to JSONL

## Recommendations

1. Start with SQLite schema design covering all 40+ artifact types
2. Build query scripts (get-task, get-context, get-phase, search-research, etc.)
3. Modify compile-context.sh to populate DB instead of generating .toon files
4. Update agent prompts to call scripts instead of Read for artifacts
5. Add task queue semantics (insert-task, next-task, complete-task)
6. Wire into go.md and execute-protocol.md
7. Add monitoring: token-before vs token-after per agent per phase
