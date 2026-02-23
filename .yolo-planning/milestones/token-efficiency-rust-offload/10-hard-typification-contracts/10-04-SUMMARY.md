---
phase: 10
plan: 4
title: Domain Newtypes and Typed Hook Inputs
status: complete
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 3c9ebeb
  - 1e82f7b
  - 4efdb68
  - 65d239c
commits:
  - "feat(10-04): add domain newtypes for TaskId, Phase, Wave, ResourceId"
  - "feat(10-04): add typed hook input structs for SecurityFilter and ContractValidation"
  - "feat(10-04): migrate security_filter.rs to typed SecurityFilterInput"
  - "feat(10-04): migrate validate_contract and lease_lock to typed inputs"
---

## What Was Built

- **Domain newtypes**: `TaskId`, `Phase`, `Wave`, `ResourceId` in `commands/domain_types.rs` replacing raw `String`/`u64` in critical paths. Each newtype wraps its primitive and exposes typed accessors (`as_str()`, `as_u32()`, `as_number()`).
- **Typed hook input structs**: `SecurityFilterInput` and `ContractValidationInput` in `hooks/types.rs` with `from_hook_input()` / `from_value()` constructors that deserialize from raw JSON with graceful fallback to None fields.
- **security_filter.rs migration**: Refactored `handle()` to parse `SecurityFilterInput` first, using typed field access (`typed.tool_name.as_deref()`) with fallback to the existing `extract_file_path()` for backward compat.
- **validate_contract.rs migration**: Refactored `validate_contract_hook()` to use `ContractValidationInput::from_value()` instead of raw `.get()` chains.
- **lease_lock.rs migration**: Changed `acquire()`, `renew()`, `release()` signatures from `resource: &str` to `resource: &ResourceId`. Updated `execute()` CLI entry point to construct `ResourceId::new(...)` from parsed args.
- **8 new tests**: 4 for domain newtypes (TaskId parsing, Display, Phase, ResourceId), 4 for typed inputs (SecurityFilterInput parse + fallback, ContractValidationInput parse + fallback).

## Files Modified

- `yolo-mcp-server/src/commands/mod.rs` — added `pub mod domain_types;`
- `yolo-mcp-server/src/commands/domain_types.rs` — NEW: 4 newtypes + 4 tests
- `yolo-mcp-server/src/hooks/types.rs` — added SecurityFilterInput, SecurityToolInput, ContractValidationInput structs + 4 tests
- `yolo-mcp-server/src/hooks/security_filter.rs` — refactored handle() to use SecurityFilterInput
- `yolo-mcp-server/src/hooks/validate_contract.rs` — refactored validate_contract_hook() to use ContractValidationInput
- `yolo-mcp-server/src/commands/lease_lock.rs` — changed acquire/renew/release to accept ResourceId, updated tests

## Deviations

- Tests for Task 5 were written inline with Tasks 1 and 2 (domain_types.rs and hooks/types.rs) rather than in a separate commit, since the plan's test locations matched the implementation files.
- Plan 10-02 modified validate_contract.rs and lease_lock.rs in parallel (feature flag migration). Changes were compatible — 10-02 changed flag reading, 10-04 changed hook input parsing and function signatures. No merge conflicts.
