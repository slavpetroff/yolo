---
phase: 3
plan: 1
title: "Schema enum and key corrections"
status: complete
completed: 2026-02-23
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 4772630
  - c2fe574
  - 4d0b863
  - 41fc11d
  - 4fbb783
deviations:
  - "Task 5: Fixed config-migration.bats test that used removed planning_tracking value 'auto' — changed to 'commit'"
---

## What Was Built

Fixed all 6 P0 enum mismatches and 1 missing key in `config/config.schema.json` so the schema accurately reflects the values used by Rust code, defaults.json, and runtime configs.

### Enum corrections
- **effort**: `["minimal", "balanced", "thorough"]` → `["thorough", "balanced", "fast", "turbo"]`
- **autonomy**: `["minimal", "standard", "full"]` → `["cautious", "standard", "confident", "pure-vibe"]`
- **planning_tracking**: `["manual", "auto"]` → `["commit", "manual", "ignore"]`
- **review_gate**: `["off", "on_request", "always"]` → `["never", "on_request", "always"]`
- **qa_gate**: `["off", "on_request", "always"]` → `["never", "on_request", "always"]`
- **model_profile**: `["quality", "balanced", "speed"]` → `["quality", "balanced", "budget"]`
- **prefer_teams**: `["never", "auto", "always"]` → `["never", "auto", "always", "when_parallel"]`

### Missing key
- **compaction_threshold**: Added as `{ "type": "integer", "minimum": 1 }` — required by `phase_detect.rs`

### Validation
- All 4 schema-validation.bats tests pass
- All config-migration.bats tests pass (1 test updated for new enum values)
- defaults.json validates against corrected schema

## Files Modified

- `config/config.schema.json` — 6 enum corrections + 1 new property
- `tests/config-migration.bats` — Updated test to use valid `planning_tracking` value

## Deviations

- **Task 5 test fix**: The config-migration test "migration preserves existing planning_tracking and auto_push values" used `"planning_tracking": "auto"` which is no longer valid. Updated to `"commit"` (a valid non-default value that still exercises the preservation logic).
