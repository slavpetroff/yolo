---
phase: "04"
plan: "02"
title: "Version bump, CHANGELOG, and CLAUDE.md update"
wave: 1
depends_on: []
must_haves:
  - "REQ-21: CHANGELOG.md updated with milestone summary"
  - "REQ-22: Version bumped in plugin.json and Cargo.toml"
  - "REQ-23: CLAUDE.md updated with milestone completion"
---

## Goal

Finalize the milestone with documentation updates and version bump.

## Task 1: Update CHANGELOG.md

**Files:** `CHANGELOG.md`

Add a new entry at the top (after the header) for v2.9.5:

```markdown
## v2.9.5 (2026-02-24)

### Workflow Gates
- **review_gate/qa_gate defaults** — Changed from "on_request" to "always" in defaults.json
- **qa_skip_agents** — Docs plans skip QA gate enforcement in execute protocol
- **Verdict fail-closed** — Malformed review/QA output triggers STOP, not continue

### HITL Hardening
- **request_human_approval** — Rewritten from stub to production: writes execution state, returns structured pause signal
- **Vision Gate (Step 2c)** — Execute protocol enforces approval state check before proceeding
- **execution-state-schema.json** — New JSON Schema with `awaiting_approval` status

### Rust Quality
- **Mutex hardening** — 7 `.lock().unwrap()` calls replaced with proper error handling (map_err + poison recovery)
- **Regex OnceLock** — 13 `Regex::new()` calls cached via `std::sync::OnceLock` statics
- **Frontmatter dedup** — 3 duplicate implementations consolidated into `commands/utils.rs` (-47 lines)
- **YoloConfig migration** — `phase_detect.rs` migrated from manual JSON parsing to typed struct

### Tests
- 18 new bats tests (gate-defaults, qa-skip-agents, fixable-by, verdict-parse, hitl-vision-gate, workflow-integrity)
- 6 new Rust unit tests for request_human_approval and write_approval_state
```

## Task 2: Bump versions

**Files:** `.claude-plugin/plugin.json`, `yolo-mcp-server/Cargo.toml`

- plugin.json: `"version": "2.9.4"` → `"version": "2.9.5"`
- Cargo.toml: `version = "2.7.0"` → `version = "2.7.1"`

## Task 3: Update CLAUDE.md

**Files:** `CLAUDE.md`

Update the Active Context section:
- **Work:** None (idle)
- **Last shipped:** Workflow Validation & Rust Quality Audit (2026-02-24) — 4 phases, 12 plans, 15+ commits
- **Next action:** Run /yolo:vibe to start a new milestone
