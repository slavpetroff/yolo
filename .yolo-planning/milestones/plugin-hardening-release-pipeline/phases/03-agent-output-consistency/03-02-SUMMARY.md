---
phase: "03"
plan: "02"
title: "diff-against-plan --commits override flag"
status: "complete"
completed: "2026-02-24"
tasks_completed: 4
tasks_total: 4
commit_hashes: ["cfd13489"]
deviations: []
---

# Summary: diff-against-plan --commits override flag

## What Was Built

Added `--commits hash1,hash2` flag to diff-against-plan that fully overrides frontmatter `commit_hashes`. When provided with non-empty values, the flag's comma-separated hashes replace whatever is in the SUMMARY frontmatter. Empty `--commits ""` is treated as flag-not-passed. Usage string updated.

## Files Modified

- `yolo-mcp-server/src/commands/diff_against_plan.rs` — Added `parse_flag()` helper, `--commits` override logic between frontmatter extraction and `get_git_files()` call, updated usage string, added 2 new tests (override + empty flag)

## Deviations

None.
