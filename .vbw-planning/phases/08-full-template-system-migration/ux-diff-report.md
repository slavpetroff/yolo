# UX Overlay Parity Diff Report

Generated: 2026-02-19
Method: `bash scripts/generate-agent.sh --role {role} --dept uiux --dry-run` vs `agents/yolo-ux-{role}.md`

## Summary

| Role | Hand Lines | Gen Lines | Diff Lines | Gaps Category |
|------|-----------|-----------|------------|---------------|
| dev | 215 | 316 | 228 | Overlay wording, description, intro |
| senior | 187 | 240 | 145 | Overlay wording, description |
| tester | 151 | 167 | 143 | Overlay wording, vocabulary, conventions |
| lead | 174 | 241 | 186 | Overlay wording, description, decomp rules |
| architect | 123 | 142 | 128 | Overlay wording, vocabulary, intro |
| qa | 133 | 162 | 133 | Overlay wording, description, checks |
| qa-code | 143 | 206 | 182 | Overlay wording, description, vocabulary |
| security | 196 | 182 | 152 | Overlay categories, tools, finding example |
| documenter | 104 | 102 | 94 | Overlay wording, doc types, scope |

Generated files are LONGER because templates include mode-gated sections (Research Request, Escalation Resolution, Change Management, Continuous QA, Gate Results, etc.) that hand-authored files condensed or omitted. This is expected -- templates are the canonical full-featured versions.

## Per-Role Gap Analysis

### dev

**Overlay gaps (hand-authored has better UX wording):**
- `description` frontmatter: "implements design tokens, component specs, wireframes, and user flow documentation" vs generic "implements exactly what specified"
- Title: "(Designer/Developer)" vs "(Junior Developer)"
- Intro: "Produces design tokens, component specs, wireframes, and user flow documentation. No creative decisions." vs generic
- Stage 1: "design implementation instructions" vs "implementation instructions"
- Stage 2 step 3: "Implement design artifact" vs "Implement action"
- Constraints: "No bonus features, no creative additions" vs "No bonus features, no refactoring beyond spec, no improvements"
- Escalation row: "Spec unclear, domain question, or blocked" vs "Spec unclear, blocked, or critical deviation"

**Template extras (generated has more, hand-authored condensed):**
- Compaction marker check, gap remediation steps (expanded), checkpoint handling
- TDD RED/GREEN steps more detailed in template
- Summary JSONL example inline
- Research Request Output section, Escalation Resolution section, Change Management section
- Communication section
- Full Shutdown Response protocol (hand-authored references yolo-dev.md instead)

**Structural:** Hand-authored puts Hierarchy before Persona. Generated puts Hierarchy after frontmatter, before Persona. Both valid.

### senior

**Overlay gaps:**
- `description`: removes "agent" word
- Title: "YOLO UX Senior" vs "YOLO UX Senior Engineer"
- Hierarchy: "UX Dev" vs "UX Dev (Junior)"
- Mode 2 Code Review: hand-authored omits test-plan.jsonl from input
- Mode 2 steps: hand-authored adds "same schema as backend" note
- Escalation: "Design system conflict" vs "Design conflict discovered during review"
- Constraints: "Read + Write enriched plan. No design artifact changes" vs "Read codebase + Write enriched plan. No source code changes"

**Template extras:**
- critique.jsonl step in Mode 1, review cycles detail, Phase 4 metric hooks
- Resolution Routing section, Decision Logging section
- Cross-phase dependency escalation row

### tester

**Overlay gaps:**
- `description`: UX-specific "usability test specs, accessibility checklists, design compliance criteria"
- Archetype: "Design System Test Engineer / TDD Practitioner. Writes failing design validation tests before implementation exists. Speaks in test scenarios, design assertions, and RED/GREEN phase discipline."
- Vocabulary: richer categories (Token testing, Accessibility testing, Component spec validation, User flow validation)
- Communication standards: richer (4 items vs 3)
- Decision framework: richer with "Missing states = validation failure" rule
- Step 1: expanded validation approach detection
- Step 2: different naming (Token validation, Accessibility checklists, Component spec validation)
- Test plan example: different path and counts
- Conventions: expanded with Consistency tests and Coverage tests

**Template extras:**
- Effort-Based Behavior table, Test Quality Standards section
- Output Schema section, Communication section
- Additional escalation rows (Cannot detect test framework, Missing dependencies)

### lead

**Overlay gaps:**
- `description`: "decomposes design phases" with "component specs, design tokens, and user flow breakdown"
- Archetype: "Senior Design Lead / Design Engineering Manager. Owns design deliverable decomposition and handoff quality. Speaks in delivery milestones and design system readiness, not visual aesthetics."
- Vocabulary: richer language (delivery milestones, handoff readiness, design system governance)
- Communication: richer (3 items with handoff focus)
- Decision framework: richer (tokens before components, delivery-first, scope-bounded authority)
- Research: includes research.jsonl, different codebase reference
- Decompose rules: "Design-deliverable decomposition", "Handoff-aware"
- Cross-dept: "Produces design-handoff.jsonl for Frontend Lead + Backend Lead (via Frontend relay)"
- Review Ownership: "token values, interaction specs, and responsive rules" vs "design system decomposition and artifact planning"

**Template extras:**
- Escalation Receipt and Routing section, Escalation State Tracking, Timeout Monitoring, Resolution Forwarding
- Output Format schema details, Display lines, Self-Review/Commit stages expanded
- Decision Logging section

### architect

**Overlay gaps:**
- `description`: "information architecture, design system strategy, and user experience system design"
- Intro: "information architecture, design system strategy, user flow structure"
- Archetype: "Design Director / UX Systems Architect with deep design-systems-at-scale experience. Final UX technical authority. Speaks in design system architecture decisions, not implementation specifics."
- Vocabulary: 5 domains (adds Responsive strategy)
- Communication: 4 standards (adds simplify rule)
- Decision framework: 3 items (scannability, evidence-based, risk-weighted)
- Core protocol: simplified step numbering, different system design items

**Template extras:**
- Architecture.toon Format section, Decision Logging section
- Detailed critique consumption (3 modes), phase decomposition step

### qa

**Overlay gaps:**
- `description`: "design system compliance verification, consistency auditing, and accessibility assessment"
- Intro: "Plan-level verification for the UI/UX department"
- Archetype: "Senior Design QA Lead with system-level verification expertise"
- Vocabulary: 4 domains (design system compliance, accessibility assessment, consistency auditing, handoff readiness)
- Communication: richer with handoff readiness standard
- Decision framework: consistency scale rule
- Verification tiers: UX-specific checks (design tokens, component specs, accessibility)
- UX-Specific Checks section (replaces Goal-Backward Methodology)
- Hierarchy: "UX QA Code Engineer" named
- Escalation: UX-specific situations

**Template extras:**
- Goal-Backward Methodology section, Output Format schema
- Continuous QA (Gate-Aware Verification) section with gate result consumption

### qa-code

**Overlay gaps:**
- `description`: "design token validation, style consistency checks, and accessibility linting"
- Intro: "Code-level verification for the UI/UX department"
- Archetype: "Design Quality Automation Engineer"
- Vocabulary: token validation, style consistency, accessibility linting, schema validation
- Communication: schema violations cascade, token naming = design system drift
- Decision framework: test failures and schema violations
- Phase structure: condensed (Phase 0-1, Phase 2, Phase 3 with UX-specific content)
- Output format: references backend schema
- Review ownership: UX-specific wording

**Template extras:**
- Detailed Phase 0 TDD compliance with gate pre-check
- Detailed Phase 1 automated checks (test suite, linter, secret scan, import check)
- Detailed Phase 2/3 with numbered items
- Continuous QA gate result sections

### security

**Overlay gaps (SIGNIFICANT):**
- `tools`: Hand-authored has NO Bash tool; generated has Bash
- `maxTurns`: 20 vs 25
- Intro: "has no Bash tool -- pattern-based scanning only"
- Category 2: "Data Exposure in User Flows" (richer with flow diagrams, journey docs)
- Category 3: expanded with security implications subsection
- Category 4: "Design Token Security" (NEW -- hardcoded URLs, infrastructure details, environment values)
- Category 5: "Form Security Patterns" (expanded with credit card/SSN masking)
- Effort: "Full 5-category audit" vs "Full 4-category"
- `categories` list: adds "data_exposure", "token_security"
- Finding example: design-specific file reference
- Constraints: "No Bash tool" emphasis

### documenter

**Overlay gaps:**
- `tools`: Hand-authored has NO Bash tool; generated has Bash
- Title: "YOLO UI/UX Documenter" vs "YOLO UX Documenter"
- Hierarchy receives: design artifacts directly vs summary/code-review
- Communication: different standards (implementation specifics, usage examples, all states)
- Decision framework: different emphasis (design-intent, handoff clarity, consistency-first)
- Doc types: `token-catalog`, `interaction-spec`, `user-flow`, `handoff`, `a11y-summary` (adds a11y-summary)
- Scope: expanded (adds accessibility compliance summary)
- Effort balanced: "Token catalog + interaction specs" vs "Token catalog + component spec docs"
- Dir isolation: "source code" vs "design artifacts"
- Constraints: "No Bash execution" rule
- Context receives: design artifact files vs summary+code-review

## Critical Back-Port Items

1. **security tools**: Remove Bash from security overlay or add tool customization
2. **documenter tools**: Remove Bash from documenter overlay or add tool customization
3. **security categories**: Add Category 4 (Design Token Security), expand to 5 categories
4. **documenter doc types**: Add `a11y-summary` type
5. **All roles**: UX-specific description, archetype, vocabulary wording
6. **qa/qa-code**: UX-specific verification phases and checks
7. **tester**: UX-specific vocabulary domains and conventions
8. **lead**: UX-specific decomposition rules and cross-dept communication
9. **architect**: UX-specific vocabulary (5 domains), decision framework

## Tool/Frontmatter Differences (Cannot Fix via Overlay)

The template system currently does NOT support per-dept tool or frontmatter overrides. These differences require either:
1. Adding frontmatter override support to generate-agent.sh (future work)
2. Accepting the template defaults (Bash included for security/documenter)

Affected roles: security (tools, maxTurns), documenter (tools)
