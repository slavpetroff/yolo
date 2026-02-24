---
plan: "03-04"
phase: 3
title: "Frontmatter dedup and YoloConfig migration"
status: complete
agent: team-lead
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - "0f234df"
  - "2bd6d1b"
  - "3acebef"
---

## What Was Built

1. Added canonical `extract_frontmatter()` and `split_frontmatter()` to `commands/utils.rs` — single source of truth for frontmatter delimiter parsing.
2. Migrated 3 callers (`validate_frontmatter.rs`, `generate_contract.rs`, `verify_plan_completion.rs`) to use the shared functions, removing 47 lines of duplicate code.
3. Applied OnceLock caching to 4 remaining `Regex::new()` calls in `generate_contract.rs` (2) and `verify_plan_completion.rs` (2).
4. Migrated `phase_detect.rs` from 28 lines of manual `serde_json::Value` field extraction to typed `YoloConfig` struct deserialization. Added `compaction_threshold` field to `YoloConfig`.

## Files Modified

- yolo-mcp-server/src/commands/utils.rs
- yolo-mcp-server/src/hooks/validate_frontmatter.rs
- yolo-mcp-server/src/commands/generate_contract.rs
- yolo-mcp-server/src/commands/verify_plan_completion.rs
- yolo-mcp-server/src/commands/phase_detect.rs

## Deviations

- Skipped optional `parse_frontmatter.rs` internal migration — its inline parsing is deeply coupled to its key-value iteration loop, and restructuring would add complexity without clear benefit.
