# YOLO Quality & Technical Concerns

Observed patterns, risks, and areas requiring attention.

## Technical Debt

### 1. Shell Script Complexity
**Status**: Manageable, actively mitigated
- Core scripts (80+) use proper safety (`set -euo pipefail`)
- Some scripts mix parsing logic with execution
- Mitigated by `hook-wrapper.sh` enforcing exit code conventions
- New scripts (trivial-lint.sh, pre-integration-check.sh) follow structured JSON output pattern

### 2. JSONL Schema Versioning
**Status**: Risk emerging as artifact count grows
- 14+ core artifact types with abbreviated keys, no schema versioning
- New artifact types added: test-results.jsonl (per-plan test metrics), classification output (with skip_analyze)
- Risk: Breaking changes require careful migration across phases
- Mitigated by `naming-conventions.md` anti-patterns, validation scripts, and static schema tests

### 3. Template System Indirection
**Status**: Manageable with discipline
- Agent `.md` files are generated from `agents/templates/` + `agents/overlays/` via `scripts/generate-agent.sh`
- 9 templates x 3 overlays = 27 generated agents (plus shared agents hand-authored)
- **Risk**: Stale generated files silently drift from templates
- **Risk**: Debugging agent behavior requires tracing through template + overlay + mode filtering pipeline
- Mitigated by: `--dry-run` flag, unreplaced placeholder warnings, hash-based staleness detection (`agents/.agent-generation-hash`), `regenerate-agents.sh --check` in CI

### 4. Mode Filtering Accuracy
**Status**: Requires correct section markers
- Mode filtering depends on `<!-- mode:X,Y,Z -->` / `<!-- /mode -->` HTML comment markers in templates
- **Risk**: Misplaced or mismatched markers silently include/exclude wrong content
- **Risk**: Unmarked sections always pass through -- easy to forget marking a section that should be mode-gated
- Mitigated by: `tests/unit/generate-agent-all-combos.bats`, backward compatibility checks (full = no mode)

### 5. Import-JSONL SQL Escaping
**Status**: Emerging concern
- `scripts/db/import-jsonl.sh` converts JSONL rows to SQL INSERT statements
- Edge cases: nested quotes in JSON strings, newlines in action/spec fields, NULL values
- ~30% failure rate on complex artifact types (escalation.jsonl with nested objects)
- Mitigated by: validation tests, SQL parameter binding where possible, schema uniqueness constraints

### 6. Database Concurrent Access
**Status**: WAL mode addresses but locking patterns need discipline
- SQLite WAL mode enabled for concurrent reads, 5s busy_timeout for writes
- **Risk**: Long-running transactions can block subsequent writes
- Mitigated by: checkpoint-db.sh for WAL cleanup, integration stress tests (concurrent-reads/writes/mixed.bats)

## Resolved Concerns

### Dual Classification System
**Status**: RESOLVED — Consolidated into single `scripts/complexity-classify.sh` with `skip_analyze` field

### Dead Feature Flags
**Status**: RESOLVED — Cleaned up; remaining flags are all config-gated and tested

### Manifest Completeness
**Status**: RESOLVED — enforced by `tests/static/manifest-completeness.bats`

### Error Recovery Context
**Status**: RESOLVED — `compile-context.sh` includes `error_recovery:` section when `gaps.jsonl` has open entries

### SQLite Migration Complexity
**Status**: RESOLVED -- DB is sole artifact store (Phase 11). Migration completed in Phase 10, DB-only enforced in Phase 11.

## Security Considerations

### 1. Secret File Protection
- Controlled via `file-guard.sh` PreToolUse hook
- Prevents writes to: `.env`, `.pem`, `.key`, credentials files

### 2. Department Isolation Enforcement
- Enforced via `department-guard.sh` hook
- Backend agents cannot write frontend/ or ux-design/ files
- Risk: Relies on PreToolUse hook; if hook fails open, no enforcement

### 3. Cross-Plugin Context Leakage
- GSD plugin context isolation enforced via CLAUDE.md rules + containment tests

## Known Limitations

1. **Department Workflow Order**: Hard-coded UI/UX -> Frontend + Backend -> QA -> Owner
2. **Synchronous Escalation Resolution**: Escalations wait for Owner response up to timeout
3. **Team Mode Auto-Detection**: Heuristic-based; may false-positive if Teammate API is partial
4. **Template-Generated Agents**: Changes to templates require explicit regeneration; no auto-rebuild hook
5. **Mode Marker Authoring**: No linter for mode marker correctness (balanced open/close, valid mode names)
6. **Database Path Resolution**: Walks filesystem searching for planning directory; may fail in unusual layouts

## Recommended Actions

| Priority | Item | Effort |
|----------|------|--------|
| High | Add SQL parameter binding to import-jsonl.sh for escaping | 4h |
| High | Add mode marker linter for template authoring | 4h |
| Medium | Benchmark concurrent-writes stress under load (100+ tasks) | 2h |
| Medium | Add auto-rebuild hook for template changes | 4h |
| Medium | Document WAL checkpoint tuning and autocheckpoint config | 2h |
| Low | Extract ADRs from CLAUDE.md to separate architecture docs | 1d |
