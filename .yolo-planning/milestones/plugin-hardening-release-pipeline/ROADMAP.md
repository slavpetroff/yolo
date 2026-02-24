# Roadmap: Plugin Hardening & Release Pipeline

## Phase 1: Version Unification & Build Consistency
**Goal:** Single source of truth for version across all files. Cargo.toml synced via toml_edit. Duplicate marketplace.json consolidated. bump-version extended with --major/--minor. Archive skill delegates all version logic to CLI.
**Success Criteria:**
- `yolo bump-version` updates VERSION, plugin.json, marketplace.json, AND Cargo.toml (via toml_edit)
- `yolo bump-version --major` and `--minor` flags work (archive no longer does its own math)
- Root marketplace.json is canonical; .claude-plugin/marketplace.json deleted
- Cargo.toml synced to current VERSION (2.7.1 → 2.9.5)
- Archive skill simplified to call `yolo bump-version [--major|--minor]`
- `cargo clippy` clean, all tests pass
**Requirements:** REQ-01, REQ-07

## Phase 2: CLI Facade Commands & LLM Hop Reduction
**Goal:** 5 batch facade commands that reduce LLM round-trips by 50-65% for common workflows.
**Success Criteria:**
- `yolo qa-suite <summary> <plan> [--commit-range] [--phase-dir]` — runs all 5 QA checks, returns unified JSON report
- `yolo resolve-agent <agent> <config> <profiles> <effort>` — model + turns in one call
- `yolo release-suite [--major|--minor] [--dry-run] [--no-push]` — bump + changelog + commit + tag + push
- `yolo resolve-models-all <config> <profiles>` — all agent models in one JSON object
- `yolo bootstrap-all <output_dir> <discovery.json> <phases.json>` — all 5 bootstrap files atomically
- Instructions updated to reference facade commands (skills/, commands/, agents/)
- Each facade returns rich context so LLM needs zero follow-up hops
**Requirements:** REQ-03

## Phase 3: Agent Output Consistency & Race Condition Fixes
**Goal:** Fix SUMMARY naming enforcement, diff-against-plan commit scoping, and instruction inconsistencies.
**Success Criteria:**
- Agent template + instructions enforce `{NN}-{MM}-SUMMARY.md` naming pattern
- diff-against-plan accepts optional `--commits hash1,hash2` to scope verification to specific commits
- SUMMARY frontmatter `commit_hashes` field is validated (not just parsed)
- Binary path references unified to `yolo` (not `$HOME/.cargo/bin/yolo`) across all skill/command files
**Requirements:** REQ-04, REQ-05, REQ-06, REQ-08

## Phase 4: Archive Auto-Release & Pipeline Completion
**Goal:** Archive automatically creates GitHub release with notes. End-to-end pipeline: archive → version bump → tag → push → `gh release create`.
**Success Criteria:**
- Archive step 8b includes `gh release create v{VERSION} --title "v{VERSION}" --notes-file <changelog_section>`
- Changelog section extraction works (latest version block from CHANGELOG.md)
- Release includes milestone summary in body
- Gated by `auto_push` config (never = skip release, always/after_phase = auto-release)
- Archive skill instructions updated with release step
**Requirements:** REQ-02
