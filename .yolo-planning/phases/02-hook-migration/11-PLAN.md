---
phase: 2
plan: 11
title: "Migrate contract scripts to native Rust (generate-contract, contract-revision)"
wave: 2
depends_on: [1, 2]
must_haves:
  - "generate_contract produces V3 lite (5 fields) and V2 full (11 fields + SHA-256 hash) contracts from PLAN.md"
  - "contract_revision detects scope changes, archives old contract, generates new contract"
  - "SHA-256 via sha2 crate — no shasum shell-out"
  - "YAML frontmatter parsing via str::lines() iterator — no awk, no sed"
---

## Task 1: Implement generate_contract module

**Files:** `yolo-mcp-server/src/commands/generate_contract.rs` (new)

**Acceptance:** `generate_contract::execute(plan_path, planning_dir) -> Result<(String, i32), String>`. Parse PLAN.md YAML frontmatter for: phase, plan, title, must_haves (list), depends_on (list/inline array), verification_checks (list), forbidden_paths (list). Extract allowed_paths from `**Files:**` lines in task sections (strip backticks, `(new)`, `(if exists)`, deduplicate). Count tasks from `## Task N:` headings. V3 lite (`v3_contract_lite`): 5 fields (phase, plan, task_count, must_haves, allowed_paths). V2 full (`v2_hard_contracts`): 11 fields + contract_hash (SHA-256 via `sha2` crate of serialized contract body). Write to `.yolo-planning/.contracts/{phase}-{plan}.json`. Output contract path. Also expose CLI entry point.

## Task 2: Implement contract_revision module

**Files:** `yolo-mcp-server/src/commands/contract_revision.rs` (new)

**Acceptance:** `contract_revision::execute(old_contract_path, plan_path, planning_dir) -> Result<(String, i32), String>`. Gated by `v2_hard_contracts`. Read old contract hash. Call `generate_contract::execute()` to produce new contract. Compare hashes: if equal -> "no_change". If different: archive old contract as `{base}.rev{N}.json` (find next revision number), log `contract_revision` event via `log_event::log()`, log to `collect_metrics::collect()`. Output `revised:{archive_path}` or `no_change`. Also expose CLI entry point.

## Task 3: Register CLI commands and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/generate_contract.rs` (append tests), `yolo-mcp-server/src/commands/contract_revision.rs` (append tests)

**Acceptance:** Register `yolo generate-contract` and `yolo contract-revision` in router. Tests cover: V3 lite contract generation with correct 5 fields, V2 full contract with SHA-256 hash, frontmatter parsing for must_haves/depends_on (both list and inline array), allowed_paths extraction from **Files:** lines, contract revision detection (different hashes), no-change detection (same hashes), revision archive naming (rev1, rev2). `cargo test` passes.
