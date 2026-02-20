---
phase: 2
plan: 03
title: "Migrate validation hooks to native Rust (validate-summary, validate-frontmatter, validate-contract, validate-message, validate-schema)"
wave: 1
depends_on: []
must_haves:
  - "All 5 validation hooks implemented as native Rust functions"
  - "validate-summary checks YAML frontmatter, `## What Was Built`, `## Files Modified`"
  - "validate-frontmatter checks single-line description in YAML frontmatter"
  - "validate-contract checks task range, hash integrity, scope paths"
  - "validate-message validates envelope, type, payload, role authorization, file references"
  - "validate-schema validates frontmatter fields for plan/summary/contract types"
---

## Task 1: Implement validate_summary hook handler

**Files:** `yolo-mcp-server/src/hooks/validate_summary.rs` (new)

**Acceptance:** PostToolUse handler that checks SUMMARY.md files in `.yolo-planning/`. Extracts `file_path` from hook JSON input. Checks: file starts with `---` (YAML frontmatter), contains `## What Was Built`, contains `## Files Modified`. Returns hookSpecificOutput JSON with missing sections listed. Always exit 0 (non-blocking). Pure Rust file reading with `std::fs::read_to_string`, string matching with `str::contains`.

## Task 2: Implement validate_frontmatter hook handler

**Files:** `yolo-mcp-server/src/hooks/validate_frontmatter.rs` (new)

**Acceptance:** PostToolUse handler that validates YAML frontmatter `description:` field in .md files. Must:
1. Extract file_path from hook input JSON
2. Skip non-.md files
3. Read first line, verify it's `---`
4. Parse frontmatter block between `---` delimiters
5. Find `description:` field
6. Check for block scalar indicators (`|` or `>`) -- warn multi-line
7. Check for empty description -- warn empty
8. Check for indented continuation lines -- warn multi-line
9. Return hookSpecificOutput JSON with warning. Always exit 0.

Use `str::lines()` iterator, no awk/sed.

## Task 3: Implement validate_contract module

**Files:** `yolo-mcp-server/src/hooks/validate_contract.rs` (new)

**Acceptance:** Implements full contract validation matching validate-contract.sh behavior. Two modes:
- `start`: verify task in range (1..task_count), verify SHA-256 hash integrity (v2_hard_contracts)
- `end`: check modified files against allowed_paths and forbidden_paths

Read config.json for `v3_contract_lite` and `v2_hard_contracts` flags. Use `sha2` crate for hashing (already in dependencies). Exit 0 when advisory (v3_contract_lite), exit 2 when hard stop (v2_hard_contracts). Emit violations via collect_metrics.

## Task 4: Implement validate_message module

**Files:** `yolo-mcp-server/src/hooks/validate_message.rs` (new)

**Acceptance:** Validates inter-agent messages against V2 typed protocol schemas. Must:
1. Check `v2_typed_protocol` flag
2. Verify envelope completeness (read required fields from `config/schemas/message-schemas.json`)
3. Verify known message type
4. Check payload required fields per type
5. Check role authorization (author_role against allowed_roles)
6. Check receive-direction (target_role against can_receive)
7. Check file references against active contract
8. Return `{valid: bool, errors: [...]}` JSON
9. Exit 0 when valid, exit 2 when invalid

Read schemas from `config/schemas/message-schemas.json` via serde. Call `log_event::log()` on rejection.

## Task 5: Implement validate_schema module and add tests for all validators

**Files:** `yolo-mcp-server/src/hooks/validate_schema.rs` (new), `yolo-mcp-server/src/hooks/validate_summary.rs` (append tests), `yolo-mcp-server/src/hooks/validate_frontmatter.rs` (append tests)

**Acceptance:** validate_schema validates YAML frontmatter fields for plan (phase, plan, title, wave, depends_on, must_haves), summary (phase, plan, title, status, tasks_completed, tasks_total), and contract (JSON: phase, plan, task_count, allowed_paths). Gated by `v3_schema_validation` flag. Fail-open (always exit 0).

Tests cover: valid/invalid SUMMARY.md structure, multiline description detection, contract hash verification, message envelope validation, schema field checking. `cargo test` passes.
