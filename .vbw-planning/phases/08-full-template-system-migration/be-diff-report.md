# Backend Agent Diff Report (T1)

## Summary

All 9 backend agents differ from their template-generated output. No agent is IDENTICAL.
The sg field and test-results.jsonl features ARE present in both (overlay already has values).
Differences are predominantly cosmetic/formatting but include some substantive content refinements.

## Category 1: DEPT_LABEL Empty String (affects ALL 9 agents)

Backend overlay sets `DEPT_LABEL: ""` and `DEPT_LABEL_LOWER: ""`. This creates:
- Double spaces: `" Dev"`, `" Senior"`, `" Lead"` in generated output
- Empty department references: `"Department: ."` instead of `"Department: Backend."`
- Empty headings: `"# YOLO  Lead"` instead of `"# YOLO Tech Lead"`
- Empty ownership text: `"my  dev's"` instead of `"my dev's"`

**Fix:** Not a template fix -- backend.json `DEPT_LABEL` needs a value or templates need conditional whitespace handling. Since other departments use non-empty labels (e.g., "Frontend", "UI/UX"), the simplest fix is to either give backend a label or adjust templates to trim whitespace.

## Category 2: Content Refinements Per Agent

### yolo-dev.md (47 additions, 46 removals)
- `"Senior Engineer"` shortened to `"Senior"` throughout (~15 occurrences) -- hand-authored is cleaner
- Description: `"agent agent"` → `"agent"` (template has redundant word from `ROLE_TITLE + " agent"`)
- Added `"No creative decisions."` to intro paragraph
- Removed duplicate blank lines (2 occurrences)
- Minor: `"The spec is the complete instruction set"` → `"Zero creative authority — the spec is the complete instruction set"`

### yolo-senior.md (33 additions, 43 removals)
- Reports to: `"Lead."` → `"Lead (Tech Lead)."` (hand adds context)
- Input desc: `"plan.jsonl (from Lead)"` → `"plan.jsonl (high-level tasks from Lead)"` (hand adds context)
- Spec enrichment items: multi-line list → inline comma-separated (hand is more compact)
- Test enrichment items: multi-line list → inline comma-separated (hand is more compact)
- Spec quality: `" Dev should need"` → `"a junior developer (Dev agent) should need"` (hand is clearer)
- Code review step 5: Hand adds `"If a suggestion is already addressed by the implementation, note but do not promote."`
- Code review step 6: Hand expands with detailed field descriptions (tdd, sg_reviewed, sg_promoted) in code-review.jsonl
- Review ownership: Hand adds `"When reviewing Dev spec compliance: ..."` second ownership sentence
- Removed 1 blank line

### yolo-tester.md (8 additions, 9 removals)
- Description: `"before implementation."` → `"before implementation begins."` (minor wording)
- Fixed duplicate intro sentence in generated output (`"Writes failing tests..."` repeated twice)
- Fixed step numbering: generated has two "3." steps, hand has correct 3,4,5
- Escalation: `"feature may already exist or spec is wrong"` → `"feature may already exist"` (hand shorter)
- Removed 1 blank line

### yolo-qa.md (1 addition, 2 removals)
- Only: `"# YOLO  QA Lead"` → `"# YOLO QA Lead"` (DEPT_LABEL space)
- Removed 1 blank line

### yolo-qa-code.md (4 additions, 5 removals)
- Escalation path: `"→  Senior"` → `"→ Senior"` (DEPT_LABEL space)
- Remediation routing: same double-space fix
- Removed 1 blank line

### yolo-architect.md (25 additions, 12 removals)
- System design items: multi-line list → inline comma-separated (hand is more compact)
- Escalation table: `"AskUserQuestion (via Lead orchestration)"` → `"AskUserQuestion with options"` (hand shorter)
- **NEW CONTENT**: Hand adds a full JSON example for escalation structure (18 lines)
- Receive from Lead: `" Senior or  Dev"` → `"Senior or Dev"` (DEPT_LABEL space)
- Unchanged behavior: `"architecture.toon"` → `"Architecture.toon"` (capitalize)
- Review ownership: Hand adds `"When producing architecture: ..."` second ownership sentence

### yolo-lead.md (54 additions, 53 removals)
- Title: `"# YOLO  Lead"` → `"# YOLO Tech Lead"` (different title entirely)
- All DEPT_LABEL space issues throughout (~30 occurrences)
- **Section reordering**: Summary Aggregation section moved from after Shutdown to after Teammate API Unchanged Behavior
- Transitions table: `"--------"` → `"---------"` (minor format)
- Research stage: Inline list instead of numbered block + `"Scan codebase..."` merged in + `"WebFetch for external API docs only"` added
- Review ownership: Hand adds `"When signing off on execution: ..."` second ownership sentence
- Removed 2 blank lines

### yolo-security.md (3 additions, 8 removals)
- Title: `"# YOLO  Security Engineer"` → `"# YOLO Backend Security Engineer"`
- `"Department: ."` → `"Department: Backend."`
- **REMOVED**: Review Ownership section entirely removed from hand-authored (7 lines)
- Removed 1 blank line

### yolo-documenter.md (4 additions, 5 removals)
- Title: `"# YOLO  Documenter"` → `"# YOLO Backend Documenter"`
- `"Department: ."` → `"Department: Backend."`
- Scope section: `"##  Scope"` → `"## Backend Scope"`
- Analyze scope step: Hand adds explicit doc types `"(API, script, ADR, changelog)"`

## Category 3: Recent Features Status

| Feature | Template | Overlay | Generated | Hand-authored | Status |
|---------|----------|---------|-----------|---------------|--------|
| sg field (Stage 3 summary) | Has {{DEV_SG_EXAMPLES}} | Has value | Present | Present | PARITY |
| test-results.jsonl (Stage 2.5) | Has {{DEV_TEST_RESULTS_EXAMPLE}} | Has value | Present | Present | PARITY |
| research.jsonl attribution | N/A (architect-specific) | Present in architect section | Present | Present | PARITY |

## Category 4: Template Bugs Found

1. **tester.md duplicate intro**: Template produces `"Writes failing tests from Senior's enriched task specs (the `ts` field) BEFORE Dev implements. Writes failing tests from Senior's enriched task specs (the `ts` field) BEFORE  Dev implements."` -- the `{{TESTER_INTRO}}` value already contains this sentence, then the template repeats it.
2. **tester.md step numbering**: Template has two step "3." entries (numbering bug).
3. **dev.md redundant "agent"**: Description template produces `"Junior Developer agent agent"` -- `ROLE_TITLE` includes "agent" and the template description also appends "agent".
4. **senior.md code-review.jsonl format**: Template lacks the detailed field descriptions that hand-authored version has for the code-review.jsonl output format.

## Recommendations for T2

1. Fix `DEPT_LABEL` for backend: set to `"Backend"` in common overlay (matches documenter/security hand-authored pattern) OR use empty string but fix templates to handle it
2. Fix tester.md template: remove duplicate intro text, fix step numbering
3. Fix dev.md template description: remove redundant "agent"
4. Back-port senior.md code-review.jsonl format details to template
5. Back-port architect.md escalation JSON example to template
6. Back-port ownership suffix expansions to overlay values
7. Back-port lead.md section ordering (Summary Aggregation before Fallback)
8. Consider whether security Review Ownership section should be in template (hand-authored intentionally removed it)
