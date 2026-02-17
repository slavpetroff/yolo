# YOLO Artifact Formats

JSONL schemas, key abbreviations, token budgets, and phase directory structure.

## Format Strategy

| Category | Format | Parser | Committed |
|----------|--------|--------|-----------|
| User-facing (ROADMAP, PROJECT, CLAUDE) | Markdown | Human | Yes |
| Agent-facing artifacts | JSONL (abbreviated keys) | jq | Yes |
| Compiled context | TOON | Agent reads directly | No (regenerated) |
| Runtime state | JSON | jq | Yes (on transitions) |
| Append-only logs | JSONL | jq | Yes |

## JSONL Key Dictionary

### Plan Header (line 1 of {NN-MM}.plan.jsonl)

| Key | Full Name | Type | Example |
|-----|-----------|------|---------|
| `p` | phase | string | "01" |
| `n` | plan number | string | "01" |
| `t` | title | string | "Auth middleware" |
| `w` | wave | number | 1 |
| `d` | depends_on | string[] | ["01-01"] |
| `xd` | cross_phase_deps | object[] | [{"p":"02","n":"01","a":"types.ts","r":"needs API types"}] |
| `mh` | must_haves | object | {"tr":["..."],"ar":[{"p":"...","pv":"...","c":"..."}],"kl":[{"fr":"...","to":"...","vi":"..."}]} |
| `obj` | objective | string | "Implement JWT auth" |
| `eff` | effort_override | string | "balanced" |
| `sk` | skills_used | string[] | ["commit"] |
| `fm` | files_modified | string[] | ["src/auth.ts"] |
| `auto` | autonomous | boolean | true |

### Plan Task (lines 2+ of {NN-MM}.plan.jsonl)

| Key | Full Name | Type | Example |
|-----|-----------|------|---------|
| `id` | task ID | string | "T1" |
| `tp` | type | string | "auto" or "checkpoint:review" |
| `a` | action | string | "Create auth middleware" |
| `f` | files | string[] | ["src/middleware/auth.ts"] |
| `v` | verify | string | "Tests pass, 401 on bad token" |
| `done` | done criteria | string | "Middleware exports, tests pass" |
| `spec` | specification | string | "Express middleware at src/middleware/auth.ts: import jsonwebtoken..." |
| `ts` | test_spec | string | "tests/auth.test.ts: 4 cases — valid RS256 token (200+user), expired token (401), missing header (401), malformed Bearer (401). Use describe/it, mock jwt.verify." |
| `td` | task_depends | string[] | ["T1", "T3"] |

The `spec` field is written by Senior during Design Review (Step 4). Lead leaves it empty.
The `ts` field is written by Senior during Design Review (Step 4). Lead leaves it empty. Tester reads it to write RED phase tests.

The `td` field is optional. When present, it lists task IDs within the same plan that must complete before this task can begin (intra-plan ordering). Maps to TaskCreate blockedBy parameter in teammate mode. When absent, the task has no intra-plan dependencies. Cross-plan dependencies use the plan header `d` field. See `references/teammate-api-patterns.md` ## Task-Level Blocking.

### Summary ({NN-MM}.summary.jsonl, single line)

| Key | Full Name | Type |
|-----|-----------|------|
| `p` | phase | string |
| `n` | plan number | string |
| `t` | title | string |
| `s` | status | "complete"\|"partial"\|"failed" |
| `dt` | date completed | "YYYY-MM-DD" |
| `tc` | tasks completed | number |
| `tt` | tasks total | number |
| `ch` | commit hashes | string[] |
| `fm` | files modified | string[] |
| `dv` | deviations | string[] |
| `built` | what was built | string[] |
| `tst` | test_status | "red_green"\|"green_only"\|"no_tests" |

### Verification ({phase}.verification.jsonl)

Line 1 (summary):

| Key | Full Name | Type |
|-----|-----------|------|
| `tier` | tier | "quick"\|"standard"\|"deep" |
| `r` | result | "PASS"\|"FAIL"\|"PARTIAL" |
| `ps` | passed | number |
| `fl` | failed | number |
| `tt` | total | number |
| `dt` | date | "YYYY-MM-DD" |

Lines 2+ (checks):

| Key | Full Name | Type |
|-----|-----------|------|
| `c` | check name | string |
| `r` | result | "pass"\|"fail"\|"warn" |
| `ev` | evidence | string |
| `cat` | category | "must_have"\|"artifact"\|"key_link"\|"anti_pattern"\|"convention" |

### QA Code (qa-code.jsonl)

Line 1 (summary):

| Key | Full Name | Type |
|-----|-----------|------|
| `r` | result | "PASS"\|"FAIL"\|"PARTIAL" |
| `tests` | test results | {"ps":N,"fl":N,"sk":N} |
| `lint` | lint results | {"err":N,"warn":N} |
| `dt` | date | "YYYY-MM-DD" |

Lines 2+ (findings):

| Key | Full Name | Type |
|-----|-----------|------|
| `f` | file | string |
| `ln` | line | number |
| `sev` | severity | "critical"\|"major"\|"minor" |
| `issue` | issue | string |
| `sug` | suggestion | string |

### Code Review (code-review.jsonl)

Line 1 (verdict):

| Key | Full Name | Type |
|-----|-----------|------|
| `plan` | plan ID | string |
| `r` | result | "approve"\|"changes_requested" |
| `cycle` | review cycle | number (1-3) |
| `dt` | date | "YYYY-MM-DD" |

Lines 2+ (comments):

| Key | Full Name | Type |
|-----|-----------|------|
| `f` | file | string |
| `ln` | line | number |
| `sev` | severity | "critical"\|"major"\|"minor"\|"nit" |
| `issue` | issue | string |
| `sug` | suggestion | string |

### Security Audit (security-audit.jsonl)

Line 1 (summary):

| Key | Full Name | Type |
|-----|-----------|------|
| `r` | result | "PASS"\|"FAIL"\|"WARN" |
| `findings` | count | number |
| `critical` | critical count | number |
| `dt` | date | "YYYY-MM-DD" |

Lines 2+ (findings):

| Key | Full Name | Type |
|-----|-----------|------|
| `cat` | category | "owasp"\|"secrets"\|"deps"\|"config" |
| `sev` | severity | "critical"\|"high"\|"medium"\|"low" |
| `f` | file | string |
| `issue` | issue | string |
| `fix` | remediation | string |

### Critique (critique.jsonl, one line per finding)

| Key | Full Name | Type |
|-----|-----------|------|
| `id` | critique ID | string (C1, C2...) |
| `cat` | category | "gap"\|"risk"\|"improvement"\|"question"\|"alternative" |
| `sev` | severity | "critical"\|"major"\|"minor" |
| `q` | question/finding | string |
| `ctx` | context/evidence | string |
| `sug` | suggestion | string |
| `st` | status | "open"\|"addressed"\|"deferred"\|"rejected" |

Written by Critic agent (Step 1). Architect reads and addresses `st: "open"` findings during architecture (Step 3).

### Test Plan (test-plan.jsonl, one line per task)

| Key | Full Name | Type |
|-----|-----------|------|
| `id` | task ID | string (matches plan task ID) |
| `tf` | test files | string[] (paths to written test files) |
| `tc` | test count | number (total test cases) |
| `red` | red confirmed | boolean (true = all tests fail as expected) |
| `desc` | description | string (summary of what's tested) |

Written by Tester agent (Step 5) after Senior enriches `ts` fields. Dev reads test files as RED targets during implementation (Step 6).

### State (state.json, replaces STATE.md for machines)

| Key | Full Name | Type |
|-----|-----------|------|
| `ms` | milestone | string |
| `ph` | current phase | number |
| `tt` | total phases | number |
| `st` | status | "planning"\|"executing"\|"verifying"\|"complete" |
| `step` | workflow step | "critique"\|"research"\|"architecture"\|"planning"\|"design_review"\|"test_authoring"\|"implementation"\|"code_review"\|"qa"\|"security"\|"signoff" |
| `pr` | progress | number (0-100) |
| `started` | start date | "YYYY-MM-DD" |

### Requirements (reqs.jsonl)

| Key | Full Name | Type |
|-----|-----------|------|
| `id` | requirement ID | string |
| `t` | title | string |
| `pri` | priority | "must"\|"should"\|"nice" |
| `st` | status | "open"\|"done" |
| `ac` | acceptance criteria | string |

### Research (research.jsonl)

| Key | Full Name | Type |
|-----|-----------|------|
| `q` | query | string |
| `src` | source | "web"\|"docs"\|"codebase" |
| `finding` | finding | string |
| `conf` | confidence | "high"\|"medium"\|"low" |
| `dt` | date | "YYYY-MM-DD" |
| `rel` | relevance | string |
| `brief_for` | critique ID link | string (optional, e.g. "C1") |
| `mode` | research mode | "pre-critic"\|"post-critic"\|"standalone" (optional, default "standalone") |
| `priority` | priority | "high"\|"medium"\|"low" (optional, default "medium") |

New fields (D4): `brief_for` links a research finding to the critique ID (from critique.jsonl) that prompted the research. `mode` indicates when research was performed: "pre-critic" (best-practices discovery before Critic runs), "post-critic" (solution research driven by Critic findings), or "standalone" (via /yolo:research command). `priority` is derived from the linked critique finding severity when `brief_for` is present: critical -> "high", major -> "medium", minor -> "low". All three fields are optional; omitted fields default to empty/"standalone"/"medium" respectively via jq // operator. Existing standalone research entries (without these fields) continue to parse correctly.

### Gaps (gaps.jsonl)

| Key | Full Name | Type |
|-----|-----------|------|
| `id` | gap ID | string |
| `sev` | severity | "critical"\|"major"\|"minor" |
| `desc` | description | string |
| `exp` | expected | string |
| `act` | actual | string |
| `st` | status | "open"\|"fixed"\|"accepted" |
| `res` | resolution | string |

### QA Gate Result: Post-Task (.qa-gate-results.jsonl, appended per gate invocation)

| Key | Full Name | Type | Example |
|-----|-----------|------|---------|
| `gl` | gate_level | string | "post-task" |
| `r` | result | string | "PASS"\|"FAIL"\|"WARN" |
| `plan` | plan_id | string | "04-03" |
| `task` | task_id | string | "T1" |
| `tst` | tests | object | {"ps":12,"fl":0} |
| `dur` | duration_ms | number | 2450 |
| `f` | files_tested | string[] | ["tests/unit/resolve-qa-config.bats"] |
| `dt` | datetime | string | "2026-02-17T14:30:00Z" |

The `tst` object uses `ps` (passed) and `fl` (failed) sub-keys matching the Verification schema pattern. `WARN` result indicates infrastructure missing (no bats, no matching tests). Appended to `{phase-dir}/.qa-gate-results.jsonl` by `format-gate-result.sh`.

### QA Gate Result: Post-Plan (.qa-gate-results.jsonl, appended per gate invocation)

| Key | Full Name | Type | Example |
|-----|-----------|------|---------|
| `gl` | gate_level | string | "post-plan" |
| `r` | result | string | "PASS"\|"FAIL"\|"WARN" |
| `plan` | plan_id | string | "04-03" |
| `tc` | tasks_completed | number | 5 |
| `tt` | tasks_total | number | 5 |
| `tst` | tests | object | {"ps":45,"fl":2} |
| `dur` | duration_ms | number | 28500 |
| `mh` | must_have_coverage | object | {"ps":3,"fl":0,"tt":3} |
| `dt` | datetime | string | "2026-02-17T14:35:00Z" |

Post-plan gate runs full test suite (not scoped). The `mh` field verifies must_have coverage from plan header: `ps`=passed, `fl`=failed, `tt`=total must_have checks. `tc`/`tt` fields match Summary schema pattern. Appended to same `.qa-gate-results.jsonl` file as post-task results.

### Manual QA (manual-qa.jsonl)

Written by Lead after user completes manual testing (Step 8, if `approval_gates.manual_qa` is true).

Line 1 (summary):

| Key | Full Name | Type |
|-----|-----------|------|
| `r` | result | "PASS"\|"FAIL"\|"PARTIAL" |
| `tests` | test results | [{id, desc, r, notes}] |
| `dt` | date | "YYYY-MM-DD" |

Each test entry:

| Key | Full Name | Type |
|-----|-----------|------|
| `id` | test ID | string (MQ-1, MQ-2...) |
| `desc` | description | string |
| `r` | result | "pass"\|"fail" |
| `notes` | user notes | string |

### Decisions (decisions.jsonl, append-only)

| Key | Full Name | Type |
|-----|-----------|------|
| `ts` | timestamp | ISO 8601 |
| `agent` | agent name | string |
| `task` | task reference | string |
| `dec` | decision | string |
| `reason` | rationale | string |
| `alts` | alternatives | string[] |

## Cross-Department Artifacts

Used when multiple departments are active. Stored in phase directory alongside standard artifacts.

For full schemas and examples, see `@references/handoff-schemas.md` (design_handoff, api_contract, department_result).

### Design Tokens (design-tokens.jsonl, from UI/UX)

| Key | Full Name | Type | Values |
|-----|-----------|------|--------|
| `cat` | category | string | "color"\|"typography"\|"spacing"\|"elevation"\|"motion" |
| `name` | token name | string | "color-primary-500" |
| `val` | value | string | CSS value |
| `sem` | semantic | string | Usage context |
| `dk` | dark mode value | string | Dark variant |

### Component Specs (component-specs.jsonl, from UI/UX)

| Key | Full Name | Type | Values |
|-----|-----------|------|--------|
| `name` | component name | string | Component identifier |
| `desc` | description | string | Purpose |
| `states` | states | string[] | Interaction states |
| `props` | props | object[] | Props with type/required flag |
| `tokens` | design tokens used | string[] | Token references |
| `a11y` | accessibility | object | ARIA role, keyboard nav |
| `status` | readiness | string | "ready"\|"draft"\|"deferred" |

### User Flows (user-flows.jsonl, from UI/UX)

| Key | Full Name | Type | Values |
|-----|-----------|------|--------|
| `id` | flow ID | string | "UF-NN" |
| `name` | flow name | string | Flow description |
| `steps` | steps | object[] | Step sequence |
| `err` | error paths | object[] | Error conditions |
| `entry` | entry point | string | Starting URL/state |
| `exit` | exit point | string | Success destination |

## Codebase Mapping (`.yolo-planning/codebase/`)

Generated by `/yolo:map`. Currently stores as Markdown files (INDEX.md, ARCHITECTURE.md, PATTERNS.md, CONCERNS.md, CONVENTIONS.md, DEPENDENCIES.md, STACK.md, STRUCTURE.md, TESTING.md, META.md). NOT committed (regenerated).

**Note:** Codebase mapping stays as Markdown — these files are regenerated on demand by `/yolo:map` and consumed via `@` references in compiled context.

## Token Budgets (compile-context.sh)

| Role | Budget | Rationale |
|------|--------|-----------|
| critic | 4000 | Needs full picture: reqs, codebase, research, project context |
| architect | 5000 | Needs full picture: reqs, codebase, research, critique |
| lead | 3000 | Phase scope + architecture summary |
| senior | 4000 | Plan + architecture + codebase patterns |
| tester | 3000 | Enriched plan (spec + ts) + codebase patterns |
| dev | 2000 | ONLY task specs (pre-chewed by Senior) |
| qa | 2000 | Must_haves + success criteria |
| qa-code | 3000 | Plan + summary + git diff reference |
| security | 3000 | Code diff + dependency list |
| scout | 1000 | Lightweight, focused query |
| debugger | 3000 | Issue context + relevant code |

If compiled context exceeds budget:

1. Truncate conventions to tag-only (drop rule text)
2. Truncate requirements to IDs-only (drop descriptions)
3. Summarize prose sections to headings-only
4. Drop prior-phase context (keep current phase only)

## Phase Directory Structure

```
.yolo-planning/phases/{NN}-{slug}/
  ├── critique.jsonl           # Critic output (committed)
  ├── architecture.toon        # Architect output (committed)
  ├── {NN-MM}.plan.jsonl       # Lead + Senior output (committed)
  ├── test-plan.jsonl          # Tester output (committed)
  ├── {NN-MM}.summary.jsonl    # Dev output (committed)
  ├── research.jsonl           # Scout output (committed)
  ├── verification.jsonl       # QA Lead output (committed)
  ├── qa-code.jsonl            # QA Code output (committed)
  ├── code-review.jsonl        # Senior output (committed)
  ├── manual-qa.jsonl          # Manual QA results (committed, if enabled)
  ├── gaps.jsonl               # QA gap tracking (committed)
  ├── decisions.jsonl          # All agents append (committed)
  ├── security-audit.jsonl     # Security output (committed, if enabled)
  ├── .ctx-critic.toon         # Compiled (NOT committed, regenerated)
  ├── .ctx-architect.toon      # Compiled (NOT committed, regenerated)
  ├── .ctx-lead.toon           # Compiled (NOT committed)
  ├── .ctx-senior.toon         # Compiled (NOT committed)
  ├── .ctx-tester.toon         # Compiled (NOT committed)
  ├── .ctx-dev.toon            # Compiled (NOT committed)
  ├── .ctx-qa.toon             # Compiled (NOT committed)
  ├── .ctx-qa-code.toon        # Compiled (NOT committed)
  ├── .ctx-security.toon       # Compiled (NOT committed)
  └── .execution-state.json    # Runtime (committed on transitions)

.yolo-planning/codebase/                # NOT committed (regenerated by /yolo:map)
  ├── INDEX.md                 # File index
  ├── ARCHITECTURE.md          # Component map
  ├── PATTERNS.md              # Code patterns
  └── CONCERNS.md              # Known concerns
```

### Multi-Department Phase Directory (when departments.frontend or departments.uiux = true)

```
.yolo-planning/phases/{NN}-{slug}/
  ├── (all standard artifacts above)
  ├── fe-architecture.toon     # Frontend Architect output (committed)
  ├── ux-architecture.toon     # UX Architect output (committed)
  ├── design-tokens.jsonl      # UX Dev output (committed)
  ├── component-specs.jsonl    # UX Dev output (committed)
  ├── user-flows.jsonl         # UX Dev output (committed)
  ├── design-handoff.jsonl     # UX Lead output (committed)
  ├── api-contracts.jsonl      # Frontend/Backend negotiation (committed)
  ├── .ctx-fe-architect.toon   # Compiled (NOT committed)
  ├── .ctx-fe-lead.toon        # Compiled (NOT committed)
  ├── .ctx-fe-senior.toon      # Compiled (NOT committed)
  ├── .ctx-fe-dev.toon         # Compiled (NOT committed)
  ├── .ctx-fe-tester.toon      # Compiled (NOT committed)
  ├── .ctx-fe-qa.toon          # Compiled (NOT committed)
  ├── .ctx-fe-qa-code.toon     # Compiled (NOT committed)
  ├── .ctx-ux-architect.toon   # Compiled (NOT committed)
  ├── .ctx-ux-lead.toon        # Compiled (NOT committed)
  ├── .ctx-ux-senior.toon      # Compiled (NOT committed)
  ├── .ctx-ux-dev.toon         # Compiled (NOT committed)
  ├── .ctx-ux-tester.toon      # Compiled (NOT committed)
  ├── .ctx-ux-qa.toon          # Compiled (NOT committed)
  ├── .ctx-ux-qa-code.toon     # Compiled (NOT committed)
  └── .ctx-owner.toon          # Compiled (NOT committed)
```

## Compiled Context TOON Format

Example `.ctx-dev.toon` (target: 2000 tokens):

```
phase: 01
goal: Implement auth middleware
tasks[2]{id,action,files,done,spec}:
  T1,Create auth middleware,src/middleware/auth.ts,401 on invalid,"Express middleware: verify JWT from Authorization header extract claims attach to req.user reject 401"
  T2,Write auth tests,tests/auth.test.ts,All pass 4 cases,"jest tests: valid token expired token missing token malformed token"
conventions[3]{tag,rule}:
  style,Stage files individually
  style,Commits follow type(scope): desc
  tooling,Use jq for JSON parsing
```

Example `.ctx-senior.toon` (target: 4000 tokens):

```
phase: 01
goal: Implement auth middleware
arch: JWT RS256 middleware pattern claims extraction
plan: 01-01
tasks[2]{id,action,files,done}:
  T1,Create auth middleware,src/middleware/auth.ts,401 on invalid
  T2,Write auth tests,tests/auth.test.ts,All pass 4 cases
patterns[2]{pattern,location}:
  Middleware exports named function,src/middleware/*.ts
  Tests use describe/it blocks,tests/*.test.ts
reqs[2]{id,title}:
  REQ-01,JWT validation
  REQ-03,Session management
```
