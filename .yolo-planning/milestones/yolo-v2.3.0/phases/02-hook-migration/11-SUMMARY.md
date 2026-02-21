---
plan: 11
title: "Migrate contract scripts to native Rust"
status: complete
commits: 2
tests_added: 20
tests_total: 606
---

## What Was Built

Native Rust replacements for `generate-contract.sh` and `contract-revision.sh`:

- **generate_contract.rs** -- Parse PLAN.md YAML frontmatter (phase, plan, title, must_haves, depends_on, verification_checks, forbidden_paths). Extract allowed_paths from `**Files:**` lines. Count tasks from `## Task N` / `### Task N` headings. V3 lite: 5 fields (phase, plan, task_count, must_haves, allowed_paths). V2 full: 11 fields + SHA-256 contract_hash via `sha2` crate. Writes to `.yolo-planning/.contracts/{phase}-{plan}.json`. CLI: `yolo generate-contract <plan-path>`.
- **contract_revision.rs** -- Read old contract hash, generate new contract via `generate_contract::generate()`, compare hashes. If different: archive old as `.revN.json` (auto-incrementing revision number), log `contract_revision` event via `log_event::log()`, collect metrics via `collect_metrics::collect()`. CLI: `yolo contract-revision <old-contract-path> <plan-path>`.
- **CLI registration** -- Both commands registered in `router.rs` match block and `mod.rs`.

## Files Modified

- `yolo-mcp-server/src/commands/generate_contract.rs` (new)
- `yolo-mcp-server/src/commands/contract_revision.rs` (new)
- `yolo-mcp-server/src/commands/mod.rs` (modified -- added 2 module declarations)
- `yolo-mcp-server/src/cli/router.rs` (modified -- added 2 CLI routes + imports)

## Test Results

20 tests across 2 modules:
- generate_contract: 12 tests (frontmatter parsing, scalar/list extraction, allowed_paths from Files lines, task counting, V3 lite output, V2 full output with SHA-256 hash, hash determinism, missing plan/flags, CLI execute)
- contract_revision: 8 tests (no_change on same plan, revision detected on change, multiple revisions, skip when disabled, skip missing contract, skip empty hash, CLI execute, missing args)

Full suite: 606 passed, 1 failed (pre-existing failure in clean_stale_teams from another teammate).

## Commits

1. `6127c1e` feat(commands): implement generate_contract module in native Rust
2. `ca963dd` feat(commands): implement contract_revision module in native Rust

## Deviations

None. All must-haves met. No Command::new("bash") -- all logic is native Rust with sha2 crate for SHA-256.
