# UX Overlay Parity Verification

Generated: 2026-02-19
Method: `bash scripts/generate-agent.sh --role {role} --dept uiux --dry-run` for all 9 roles, diff against `agents/yolo-ux-{role}.md`

## Placeholder Coverage

All 9 roles: **0 unreplaced `{{PLACEHOLDER}}` tokens** in generated output.

## Diff Line Counts (Post Back-port)

| Role | Diff Lines | Category |
|------|-----------|----------|
| dev | 230 | Template extras (mode-gated sections, expanded TDD steps) |
| senior | 152 | Template extras (review cycles, escalation receipt) |
| tester | 93 | Template extras (effort table, output schema, communication) |
| lead | 137 | Template extras (escalation routing, display lines, stages) |
| architect | 91 | Template extras (architecture.toon format, decision logging, critique consumption) |
| qa | 102 | Template extras (goal-backward methodology, continuous QA gates) |
| qa-code | 151 | Template extras (detailed phases, continuous QA gate results) |
| security | 44 | Frontmatter (tools, maxTurns) + template wording |
| documenter | 36 | Frontmatter (tools) + template wording |

## Semantic Content Analysis

All overlay-addressable UX-specific content has been back-ported:

### Back-ported in T2 (dev, senior, tester)
- Dev: archetype, vocabulary, communication, decision framework, dept guidelines, escalation, context
- Senior: archetype, vocabulary, communication, decision framework, spec enrichment items, ownership suffix, context
- Tester: archetype, vocabulary (4 domains), communication (4 standards), decision framework, framework detection, test writing, conventions

### Back-ported in T3 (lead, architect)
- Lead: archetype, vocabulary, communication, decision framework, decompose rules, cross-dept communication, ownership suffix, context
- Architect: intro, archetype, vocabulary (5 domains), communication (4 standards), decision framework, design items, context

### Back-ported in T4 (qa, qa-code, security, documenter)
- QA: archetype, vocabulary (4 domains), communication, decision framework, context receives
- QA-Code: archetype, vocabulary (4 domains), communication, decision framework
- Security: 5-category audit (added Design Token Security as Cat 4, expanded Form Security to Cat 5), data exposure wording, finding example, category list, context receives
- Documenter: intro, communication, decision framework, entry examples (added a11y-summary), doc types (5 types), scope items (5 items), context receives/never

## Remaining Differences (Not Overlay-Fixable)

These differences require template system changes (future work):

1. **Frontmatter tool overrides**: Security and documenter hand-authored files exclude Bash; template always includes it. Requires per-dept frontmatter override support in generate-agent.sh.
2. **Frontmatter maxTurns**: Security hand-authored uses 20; template defaults to 25.
3. **Template verbosity**: Generated files include expanded mode-gated sections (Escalation Receipt/Routing, Continuous QA Gates, Review Cycles, Architecture.toon Format, Decision Logging, Effort-Based Behavior tables, Output Schema sections, Communication sections). Hand-authored files condensed these. This is expected -- templates are the canonical full-featured versions.
4. **Structural ordering**: Hierarchy section position (before vs after Persona). Both valid.
5. **Department label**: Template uses `{{DEPT_LABEL}}` = "UX" in hierarchy line. Hand-authored uses "UI/UX" in some places.

## Verdict

**PASS** -- Zero semantic overlay content gaps remain. All UX-specific vocabulary, archetypes, communication standards, decision frameworks, and domain-specific content are captured in `agents/overlays/uiux.json`. Remaining diffs are structural template differences (expanded vs condensed) and frontmatter limitations documented for future work.
