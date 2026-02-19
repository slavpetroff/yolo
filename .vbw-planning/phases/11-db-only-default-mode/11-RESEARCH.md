# Phase 11 Research: DB-Only Default Mode

## Findings

### Backward Compatibility Code to Remove

| File | Blocks | Type | Risk |
|------|--------|------|------|
| scripts/compile-context.sh | 20 | DB_AVAILABLE conditional + file fallbacks | HIGH |
| commands/go.md | 2 | Optional DB init + phase status fallback | MEDIUM |
| scripts/state-updater.sh | 3 | Dual-write guards | LOW |
| agents/templates/*.md (7 files) | ~12 | [sqlite]/[file] instruction blocks | LOW |
| agents/yolo-*.md (24 generated) | ~12 each | Inherited [sqlite]/[file] blocks | LOW (auto-regen) |

### Critical Mismatch Found
- compile-context.sh line 26: `PLANNING_DIR=".yolo-planning"` — checks `.yolo-planning/yolo.db`
- go.md line 476: `--planning-dir .vbw-planning` — creates `.vbw-planning/yolo.db`
- DB created in wrong dir relative to where compile-context.sh looks for it

### Patterns to Remove
1. `DB_AVAILABLE=false` + `if [ "$DB_AVAILABLE" = true ]` (20 blocks in compile-context.sh)
2. `[sqlite]` / `[file]` conditional instruction blocks in 7 agent templates
3. Dual-write guards in state-updater.sh (lines 345-372, 450-452)
4. Optional DB init in go.md (lines 474-507)

### VBW Init Integration Missing
- init-db.sh is called in go.md Execute mode only
- No mention in VBW bootstrap/init flow
- Need dedicated command or auto-init on project bootstrap

## Relevant Patterns
- 30 scripts in scripts/db/ already functional
- All DB read/write paths tested (428 tests)
- Template system regenerates 24 agents from 7 templates + 3 overlays

## Risks
- compile-context.sh is 1,225 lines — removing 20 conditional blocks is significant
- Tests may assert file fallback behavior that no longer exists
- Old projects without yolo.db will break (need migration path)

## Recommendations
1. Fix planning dir mismatch first (critical blocker)
2. Make DB init mandatory in go.md (fail fast if unavailable)
3. Remove [sqlite]/[file] from templates, regenerate agents
4. Remove DB_AVAILABLE + file fallbacks from compile-context.sh
5. Simplify state-updater.sh dual-write to unconditional DB writes
6. Add DB init to VBW bootstrap flow
7. Validate with full test suite
