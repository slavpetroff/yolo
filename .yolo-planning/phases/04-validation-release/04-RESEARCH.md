# Phase 4 Research — Validation & Release

## Current Versions
- plugin.json: 2.9.4
- Cargo.toml: 2.7.0
- CHANGELOG latest: v2.9.1

## What Needs Validation
1. Full bats test suite (79 files, 700+ tests)
2. Full cargo test suite (1144+ tests)
3. Smoke test of execute protocol gates (review_gate=always, qa_gate=always already set)

## What Needs Updating
1. CHANGELOG.md — new entry for this milestone (Workflow Validation & Rust Quality Audit)
2. Version bump in plugin.json (2.9.4 → 2.9.5) and Cargo.toml (2.7.0 → 2.7.1)
3. CLAUDE.md — update Active Context with milestone completion

## Milestone Summary (Phases 1-3)
- Phase 1: QA & Reviewer gate enforcement (review_gate/qa_gate defaults to "always", qa_skip_agents, verdict fail-closed)
- Phase 2: HITL hardening (request_human_approval writes state, vision gate enforcement, execution-state-schema.json)
- Phase 3: Rust idiomatic hardening (7 mutex panics fixed, 13 regex OnceLock, frontmatter dedup, YoloConfig migration)
