# Phase 1: Version Unification & Build Consistency — Context

Gathered: 2026-02-24
Calibration: architect

## Phase Boundary

Single source of truth for version across all files. Cargo.toml synced with VERSION. Duplicate marketplace.json consolidated. bump_version.rs extended with TOML support and --major/--minor flags. Archive skill simplified to delegate all version logic to CLI.

## Decisions

### Cargo.toml Sync Strategy

- Use `toml_edit` crate for proper TOML parsing/writing (preserves formatting + comments)
- Cargo.toml version ALWAYS matches plugin VERSION file — one product, one version
- Add `toml_edit` to Cargo.toml dependencies

### marketplace.json Consolidation

- Delete `.claude-plugin/marketplace.json` (redundant)
- Keep root `marketplace.json` as canonical (marketplace discovery reads repo root)
- Keep `.claude-plugin/plugin.json` (required by plugin spec for manifest + MCP config)
- bump_version.rs updates 4 files: VERSION, .claude-plugin/plugin.json, marketplace.json, yolo-mcp-server/Cargo.toml

### Archive vs bump_version Duplication

- Extend `yolo bump-version` CLI with `--major` and `--minor` flags
- Archive skill (archive.md) removes all bash version math, delegates entirely to `yolo bump-version [--major|--minor]`
- Single codepath for all version bumps — Rust-native

### Initial Version Sync

- Force Cargo.toml from 2.7.1 to match current VERSION (2.9.5) immediately
- bump_version.rs must handle sync regardless of starting state (read VERSION as SSOT, write to all targets)

### Open (Claude's discretion)

- `toml_edit` vs `toml` crate: prefer `toml_edit` for format-preserving edits
- Test coverage: add Cargo.toml to setup_test_env() in bump_version.rs tests

## Deferred Ideas

- Cross-platform binary distribution via cargo-dist (future milestone)
- Cargo-release integration for automated release workflows
- CI job for Rust build/test (currently only lint + bats)

## Facade Commands (Phase 2 context, captured during discussion)

5 batch facades confirmed for Phase 2:
1. `yolo qa-suite` — 5 QA checks → 1 call (CRITICAL)
2. `yolo resolve-agent` — model + turns → 1 call (HIGH)
3. `yolo release-suite` — full release pipeline → 1 call (HIGH)
4. `yolo resolve-models-all` — 4 agent models → 1 call (MEDIUM)
5. `yolo bootstrap-all` — 5 bootstrap files → 1 call (MEDIUM)
