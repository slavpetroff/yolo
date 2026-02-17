# Naming Conventions

Canonical naming patterns for all YOLO artifacts. This document is the single source of truth, referenced by validate-naming.sh. Normative key definitions are in artifact-formats.md.

## 1. File Naming Patterns

| Pattern | Example | Location |
|---------|---------|----------|
| `{NN-MM}.plan.jsonl` | `01-03.plan.jsonl` | Phase directory |
| `{NN-MM}.summary.jsonl` | `01-03.summary.jsonl` | Phase directory |
| `{NN}-{slug}/` | `01-bootstrap-naming-fixes/` | Phases directory |
| `test-plan.jsonl` | (no prefix) | Phase directory |
| `critique.jsonl` | (no prefix) | Phase directory |
| `architecture.toon` | (no prefix) | Phase directory |
| `code-review.jsonl` | (no prefix) | Phase directory |
| `decisions.jsonl` | (append-only) | Phase directory |
| `qa-code.jsonl` | (no prefix) | Phase directory |
| `security-audit.jsonl` | (no prefix) | Phase directory |
| `verification.jsonl` | (no prefix) | Phase directory |
| `gaps.jsonl` | (no prefix) | Phase directory |
| `manual-qa.jsonl` | (no prefix) | Phase directory |
| `research.jsonl` | (no prefix) | Phase directory |
| `reqs.jsonl` | (project-level) | `.yolo-planning/reqs.jsonl` |

NN = zero-padded phase number. MM = zero-padded plan number. slug = lowercase-hyphenated-name.

## 2. Plan Header Key Conventions

Canonical keys per artifact-formats.md lines 17-33:

| Key | Type | Format | Example | Anti-pattern |
|-----|------|--------|---------|-------------|
| `p` | string | Phase number only, zero-padded | `"01"` | `"01-01"` (compound), `"1"` (no padding) |
| `n` | string | Plan number only, zero-padded | `"03"` | `"Create auth"` (title string) |
| `t` | string | Plan title, human-readable | `"Auth middleware"` | Number (task count) |
| `w` | number | Wave number (1-based) | `1` | `"1"` (string), `0` (zero-based) |
| `d` | string[] | Plan IDs this depends on | `["01-01"]` | `"01-01"` (not array) |
| `mh` | object | Must-haves with tr, ar, kl | `{...}` | `null`, `[]` (wrong type) |
| `obj` | string | Objective statement | `"Implement JWT auth"` | (none) |

Optional keys: `xd` (cross-phase deps), `eff` (effort override), `sk` (skills), `fm` (files modified), `auto` (autonomous).

## 3. Plan Task Key Conventions

Canonical keys per artifact-formats.md lines 34-51:

| Key | Required | Type | Example | Anti-pattern |
|-----|----------|------|---------|-------------|
| `id` | yes | string | `"T1"` | `"01-01-01"` (compound), `1` (number) |
| `tp` | yes | string | `"auto"` | (missing entirely in legacy plans) |
| `a` | yes | string | `"Create middleware"` | key named `n` or `d` instead |
| `f` | yes | string[] | `["src/auth.ts"]` | `"src/auth.ts"` (not array) |
| `v` | yes | string | `"Tests pass"` | key named `ac` instead |
| `done` | yes | string | `"Middleware exports"` | (missing in legacy plans) |
| `spec` | enriched | string | `"..."` | (empty until Senior enriches) |
| `ts` | enriched | string | `"..."` | (empty until Senior enriches) |
| `td` | optional | string[] | `["T1"]` | (task-level dependencies) |

Legacy key mapping (DO NOT USE in new plans):
- `n` (legacy) -> `a` (action) -- renamed for clarity
- `d` (legacy) -> no equivalent (was description, redundant with `a`)
- `ac` (legacy) -> `v` (verify) + `done` (done criteria) -- split into two fields

## 4. Summary Key Conventions

Canonical keys per artifact-formats.md lines 53-69:

| Key | Required | Type | Anti-pattern |
|-----|----------|------|-------------|
| `p` | yes | string | Compound `"01-01"` |
| `n` | yes | string | Title string |
| `t` | yes | string | Number (task count) |
| `s` | yes | string enum | `"done"` instead of `"complete"` |
| `dt` | yes | date string | Missing entirely |
| `tc` | yes | number | Key named `tasks` |
| `tt` | yes | number | Missing entirely |
| `ch` | yes | string[] | Key named `commits` |
| `fm` | yes | string[] | Missing entirely |
| `dv` | yes | string[] | Key named `dev` |
| `built` | yes | string[] | Missing entirely |
| `tst` | yes | string enum | Missing entirely |

Valid `s` values: `"complete"`, `"partial"`, `"failed"`.
Valid `tst` values: `"red_green"`, `"green_only"`, `"no_tests"`.

Summary is a single JSONL line. Multi-line summaries with per-task entries are legacy.

Legacy key mapping:
- `commits` -> `ch` (commit hashes)
- `tasks` -> `tc` (tasks completed count, not an object)
- `dev` -> `dv` (deviations)
- `sum` -> not canonical (narrative summaries are not part of schema)

## 5. Requirements Key Conventions

Canonical keys per artifact-formats.md lines 193-201:

| Key | Required | Type | Anti-pattern |
|-----|----------|------|-------------|
| `id` | yes | string | (none) |
| `t` | yes | string | (none) |
| `pri` | yes | string enum | Key named `p` (conflicts with plan.p=phase) |
| `st` | yes | string enum | Missing entirely |
| `ac` | yes | string | Key named `d` (ambiguous) |

Valid `pri` values: `"must"`, `"should"`, `"nice"`.
Valid `st` values: `"open"`, `"done"`.

Legacy key mapping:
- `p` (legacy) -> `pri` (priority) -- `p` conflicts with plan header phase field
- `d` (legacy) -> closest is `ac` but semantics differ (d=description, ac=acceptance criteria)

## 6. Other Artifact Key Conventions

For each type, reference artifact-formats.md for full schema.

### Critique (critique.jsonl)

Required: `{id, cat, sev, q, ctx, sug, st}`.
Valid `cat`: `"gap"`, `"risk"`, `"improvement"`, `"question"`, `"alternative"`.
Valid `sev`: `"critical"`, `"major"`, `"minor"`.
Valid `st`: `"open"`, `"addressed"`, `"deferred"`, `"rejected"`.

### Decisions (decisions.jsonl)

Required: `{ts, agent, dec, reason}`. Optional: `{alts, task}`.
`ts` must be ISO 8601 format.

### Code Review (code-review.jsonl)

Line 1 (verdict): `{plan, r, cycle, dt}`. Optional: `{tdd}`.
Lines 2+ (findings): `{f, ln, sev, issue, sug}`.

### QA Code (qa-code.jsonl)

Line 1: `{r, tests, lint, dt}`.
Lines 2+: `{f, ln, sev, issue, sug}`.

### Security Audit (security-audit.jsonl)

Line 1: `{r, findings, critical, dt}`.
Lines 2+: `{cat, sev, f, issue, fix}`.

### Verification (verification.jsonl)

Line 1: `{tier, r, ps, fl, tt, dt}`.
Lines 2+: `{c, r, ev, cat}`.

### Test Plan (test-plan.jsonl)

Per task: `{id, tf, tc, red, desc}`.

### Research (research.jsonl)

`{q, src, finding, conf, dt, rel}`.

### Gaps (gaps.jsonl)

`{id, sev, desc, exp, act, st, res}`.

### Manual QA (manual-qa.jsonl)

Line 1: `{r, tests, dt}`.

## 7. Cross-Department Artifact Naming

Multi-department artifacts (when frontend or uiux departments are active):

| Artifact | Source | Format |
|----------|--------|--------|
| `fe-architecture.toon` | Frontend Architect | TOON |
| `ux-architecture.toon` | UX Architect | TOON |
| `design-tokens.jsonl` | UX Dev | JSONL |
| `component-specs.jsonl` | UX Dev | JSONL |
| `user-flows.jsonl` | UX Dev | JSONL |
| `design-handoff.jsonl` | UX Lead | JSONL |
| `api-contracts.jsonl` | FE/BE negotiation | JSONL |

Compiled context files:
- `.ctx-{role}.toon` for backend agents (e.g., `.ctx-lead.toon`, `.ctx-dev.toon`)
- `.ctx-fe-{role}.toon` for frontend agents (e.g., `.ctx-fe-lead.toon`)
- `.ctx-ux-{role}.toon` for UX agents (e.g., `.ctx-ux-dev.toon`)
- `.ctx-owner.toon` for Owner agent

Department context files:
- `{phase}-CONTEXT-backend.md`, `{phase}-CONTEXT-frontend.md`, `{phase}-CONTEXT-uiux.md`

## 8. State Artifact Naming

| Artifact | Location | Description |
|----------|----------|-------------|
| `state.json` | `{phase-dir}/state.json` or `.yolo-planning/state.json` | Machine-readable state |
| `.execution-state.json` | `{phase-dir}/.execution-state.json` | Runtime execution state (dot-prefix = runtime artifact) |
| `STATE.md` | `.yolo-planning/STATE.md` | Human-readable state (legacy, being phased out) |

`.execution-state.json` is committed on workflow step transitions. The dot-prefix indicates it is a runtime artifact, not a primary deliverable.

## 9. Anti-Patterns (Real Examples)

Documented from naming audit across 3 prior milestones.

### Plan Headers

- WRONG: `"p":"01-01"` (compound phase-plan in p field) -- Found in: dynamic-departments phases 01-02
- RIGHT: `"p":"01"` (phase only), `"n":"01"` (plan only)

- WRONG: `"n":"Project Type Config & Classification"` (title in n field) -- Found in: dynamic-departments phases 01-02
- RIGHT: `"n":"01"` (plan number only), `"t":"Project Type Config & Classification"` (title in t field)

- WRONG: `"t":3` (task count in t field) -- Found in: dynamic-departments phases 01-02
- RIGHT: `"t":"Auth middleware"` (human-readable title string)

### Plan Tasks

- WRONG: `{"id":"T1","n":"Create config","f":[...],"d":[],"ac":[...]}` -- Found in: dynamic-departments phases 01-02
- RIGHT: `{"id":"T1","tp":"auto","a":"Create config","f":[...],"v":"...","done":"..."}` -- Used since: dynamic-departments phase 03

### Summaries

- WRONG: `{"p":"01-01","s":"complete","tasks":3,"commits":[...],"dev":[...]}` -- Found in: dynamic-departments 01-01
- RIGHT: `{"p":"01","n":"01","s":"complete","tc":3,"ch":[...],"dv":[...],"tst":"red_green"}` -- Used since: teammate-api milestone

- WRONG: Multi-line summary with per-task entries as separate JSONL lines -- Found in: performance-opt milestone
- RIGHT: Single-line summary JSONL

- WRONG: `"tst":"manual"` (non-canonical enum value) -- Found in: teammate-api 04-01
- RIGHT: `"tst":"red_green"`, `"green_only"`, or `"no_tests"`

### Requirements

- WRONG: `{"id":"REQ-01","t":"...","p":"must","d":"..."}` -- Found in: current .yolo-planning/reqs.jsonl
- RIGHT: `{"id":"REQ-01","t":"...","pri":"must","st":"open","ac":"..."}` -- Per artifact-formats.md

### Critique

- WRONG: `{"id":"C1","category":"gap","finding":"...","severity":"major","recommendation":"...","st":"open"}` -- Found in: dynamic-departments (long-form keys)
- RIGHT: `{"id":"C1","cat":"gap","q":"...","sev":"major","ctx":"...","sug":"...","st":"open"}` -- Per artifact-formats.md (abbreviated keys)
