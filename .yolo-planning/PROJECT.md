# Plugin Hardening & Release Pipeline

Harden the YOLO plugin's release pipeline, reduce LLM hops via CLI facade commands, unify version management to a single source of truth, fix agent output consistency bugs, and automate GitHub releases on archive.

**Core value:** Ship a robust, self-consistent plugin where versioning, packaging, QA, and release are fully automated with zero manual intervention.

## Requirements

### Validated

### Active
- REQ-01: Version must be single-source-of-truth (VERSION file) — bump_version must update ALL files including Cargo.toml
- REQ-02: Archive must create GitHub release with `gh release create` after tag+push
- REQ-03: CLI must provide facade commands that batch common sequential operations (qa-suite, release-suite)
- REQ-04: Agent SUMMARY naming must be enforced (pattern: {phase_num}-{plan_num}-SUMMARY.md)
- REQ-05: diff-against-plan must support per-plan commit-scoped verification (not HEAD-based)
- REQ-06: MCP server binary path must use `${CLAUDE_PLUGIN_ROOT}` or be on PATH consistently
- REQ-07: Duplicate marketplace.json (root + .claude-plugin/) must be consolidated to one
- REQ-08: Instructions must consistently reference `yolo` binary (not `$HOME/.cargo/bin/yolo`)

### Out of Scope
- Cross-platform binary distribution (cargo-dist) — future milestone
- New MCP tools beyond existing 5
- UI/visual format changes
- New agent types
- Cargo-release integration — overkill for current scale

## Constraints
- No breaking changes to existing config schema
- Tests must pass after each phase
- Backward-compatible CLI (existing commands keep their interface)
- Rust changes must pass `cargo clippy` clean
- Archive flow must remain idempotent

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| VERSION file stays as SSOT | Already used by 4/5 consumers, simplest to add Cargo.toml | Extend bump_version.rs |
| Facade over replacement | Keep atomic commands, add composite facades | Both available |
| No cargo-dist yet | Single-platform (macOS) for now, cross-platform later | Manual build in archive |
