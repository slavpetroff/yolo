# VBW Artifact Formats

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

The `spec` field is written by Senior during Design Review (Step 3). Lead leaves it empty.

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

### State (state.json, replaces STATE.md for machines)

| Key | Full Name | Type |
|-----|-----------|------|
| `ms` | milestone | string |
| `ph` | current phase | number |
| `tt` | total phases | number |
| `st` | status | "planning"\|"executing"\|"verifying"\|"complete" |
| `step` | workflow step | "architecture"\|"planning"\|"design_review"\|"implementation"\|"code_review"\|"qa"\|"security"\|"signoff" |
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

### Decisions (decisions.jsonl, append-only)

| Key | Full Name | Type |
|-----|-----------|------|
| `ts` | timestamp | ISO 8601 |
| `agent` | agent name | string |
| `task` | task reference | string |
| `dec` | decision | string |
| `reason` | rationale | string |
| `alts` | alternatives | string[] |

## Token Budgets (compile-context.sh)

| Role | Budget | Rationale |
|------|--------|-----------|
| architect | 5000 | Needs full picture: reqs, codebase, research |
| lead | 3000 | Phase scope + architecture summary |
| senior | 4000 | Plan + architecture + codebase patterns |
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
.vbw-planning/phases/{NN}-{slug}/
  ├── architecture.toon        # Architect output (committed)
  ├── {NN-MM}.plan.jsonl       # Lead + Senior output (committed)
  ├── {NN-MM}.summary.jsonl    # Dev output (committed)
  ├── research.jsonl           # Scout output (committed)
  ├── verification.jsonl       # QA Lead output (committed)
  ├── qa-code.jsonl            # QA Code output (committed)
  ├── code-review.jsonl        # Senior output (committed)
  ├── gaps.jsonl               # QA gap tracking (committed)
  ├── decisions.jsonl          # All agents append (committed)
  ├── security-audit.jsonl     # Security output (committed, if enabled)
  ├── .ctx-architect.toon      # Compiled (NOT committed, regenerated)
  ├── .ctx-lead.toon           # Compiled (NOT committed)
  ├── .ctx-senior.toon         # Compiled (NOT committed)
  ├── .ctx-dev.toon            # Compiled (NOT committed)
  ├── .ctx-qa.toon             # Compiled (NOT committed)
  ├── .ctx-qa-code.toon        # Compiled (NOT committed)
  ├── .ctx-security.toon       # Compiled (NOT committed)
  └── .execution-state.json    # Runtime (committed on transitions)
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
