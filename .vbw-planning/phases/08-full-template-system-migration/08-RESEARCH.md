# Phase 8 Research: Full Template System Migration

## Findings

### A. Old vs New Agent Files -- Complete Inventory

**Total files in agents/:** 36 agent .md files + 9 templates + 3 overlays.

**Hand-authored agents (9 files, NOT template-eligible):**
- yolo-owner.md, yolo-critic.md, yolo-scout.md, yolo-debugger.md, yolo-analyze.md
- yolo-po.md, yolo-questionary.md, yolo-roadmap.md, yolo-integration-gate.md

**Department agents that SHOULD be generated (27 = 9 roles x 3 depts):**
- Roles: architect, lead, senior, dev, tester, qa, qa-code, security, documenter
- Depts: backend (no prefix), frontend (fe-), uiux (ux-)

**Templates:** All 9 exist in agents/templates/ with {{PLACEHOLDER}} markers and mode markers.
**Overlays:** All 3 exist in agents/overlays/ (backend.json = 196 lines, fully populated).

### Critical Finding: Old Agent Files Are NOT Generated

1. No unreplaced {{PLACEHOLDER}} patterns found in agents/*.md -- files are hand-authored
2. Content differs between hand-written and template output (especially FE/UX agents with richer dept-specific content)
3. Backend agents closely match templates (templates were derived from backend); FE/UX agents diverge significantly
4. Recent commits (sg field, test-results.jsonl) were added to individual agent files, NOT to templates/overlays

### B. Generation Pipeline -- Functional But Disconnected

generate-agent.sh (189 lines) works mechanically:
- Argument parsing: --role, --dept, --mode, --dry-run, --output
- Template merging via jq gsub for {{KEY}} placeholders
- Unreplaced placeholder detection
- Mode filtering via AWK (<!-- mode:X,Y --> sections)
- Output path: agents/yolo-{prefix}{role}.md

**But NO caller exists:**
- Zero references to generate-agent.sh from any script, hook, or command
- No hook wiring in hooks.json
- go.md does not reference it
- No build script or Makefile orchestrating regeneration

### C. Flow Integration -- None

- go.md spawns agents by static name (agents/yolo-{name}.md)
- compile-context.sh has zero template/overlay awareness
- mode-profiles.json was created but is NOT referenced by any script other than generate-agent.sh
- No script passes --mode flag
- department-guard.sh, complexity-classify.sh -- no template references

### D. Script Updates -- None Made

Every core script checked: compile-context.sh, complexity-classify.sh, department-guard.sh, filter-agent-context.sh, resolve-agent-model.sh, agent-start.sh, agent-stop.sh, hook-wrapper.sh, critique-loop.sh, review-loop.sh -- zero template awareness in any of them.

### E. Missing Pieces

1. No build step before agent spawn (go.md -> generate-agent.sh)
2. No regenerate-all-agents.sh wrapper
3. No staleness detection (hash-based template change tracking)
4. No PreSubagentStart hook for on-demand generation
5. No migration guide or operator documentation
6. No .generated marker in generated files
7. No CI check verifying generated files match templates
8. FE/UX overlay parity with hand-authored agent content unverified
9. No rollback mechanism if generation produces broken agents

## Relevant Patterns

1. **Dead Infrastructure** -- Template system is complete but entirely disconnected from live system
2. **Backend-First Derivation** -- Templates derived from backend agents; FE/UX overlays may lack richness
3. **Dual Context Systems** -- compile-context.sh (artifact-level) and template system (definition-level) are uncoordinated
4. **Token-Optimization Intent** -- --mode feature designed for savings but entirely unused
5. **Hook-Driven Architecture** -- Any integration should follow existing hooks.json pattern

## Risks

### Critical
1. **Content Loss** -- FE/UX hand-authored agents have dept-specific vocabulary, decision frameworks, a11y rules not in overlays
2. **27 Agents Diverging** -- Recent changes (sg field, test-results) added file-by-file, not via templates
3. **Overlay Staleness** -- Recent features not back-ported to overlay JSON

### High
4. **Mode-Profiles Gap** -- --mode feature lacks integration design
5. **No Rollback Path** -- Generation overwrites same file paths as originals

### Medium
6. **Test Coverage Gap** -- No test verifying all 27 combinations produce valid output
7. **Operator Confusion** -- No .generated marker or documentation

## Recommendations

### Audit & Parity (before wiring)
1. Diff all 27 agents against template+overlay output, catalog every difference
2. Back-port missing FE/UX content to overlay JSON
3. Back-port recent features (sg, test-results.jsonl) to templates and overlays

### Build Pipeline
4. Create scripts/regenerate-agents.sh (all 27 combos + --check mode for CI)
5. Add staleness detection (.agent-generation-hash + SessionStart check)
6. Add BATS tests for all 27 combinations (no unreplaced placeholders, valid structure)

### Integration
7. Wire go.md or SubagentStart hook to use generate-agent.sh
8. Add <!-- GENERATED --> marker to generated files
9. Document template+overlay system in agents/templates/README.md

### Mode Optimization (deferred)
10. Design mode-profiles integration with go.md workflow stages
11. Measure token savings before implementing mode filtering
