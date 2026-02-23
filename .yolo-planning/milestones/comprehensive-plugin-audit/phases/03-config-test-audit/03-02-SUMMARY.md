---
phase: 3
plan: 2
title: "Config data file consistency fixes"
status: complete
completed: 2026-02-23
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - d062b7f
  - 3a7820e
  - 3415f27
  - cf15c50
deviations:
  - "Rust source at tier_context.rs:70 does reference 'senior' and 'security' in a hardcoded match arm, but this is independent of the JSON role_families field (no Rust code reads role_families from JSON). Removal from token-budgets.json is safe."
---

## What Was Built

Fixed three data inconsistencies in config JSON files and documented a naming discrepancy:

1. **Removed phantom roles** -- `senior` and `security` entries from `role_families.execution` in token-budgets.json. These roles do not exist in model-profiles.json or agent definitions. The Rust `role_family()` function has its own hardcoded mapping and does not read the JSON field.

2. **Flagged placeholder skill names** -- Added `_todo` top-level field and `_skill_status: "placeholder"` to each language entry in stack-mappings.json. All 11 language entries use generic names like `python-skill` rather than real marketplace IDs.

3. **Merged duplicate mobile key** -- stack-mappings.json had two `"mobile"` top-level keys. Merged into one with the expanded detection patterns (recursive xcodeproj/xcworkspace globs, ContentView.swift for SwiftUI) plus all 5 platforms (ios-swift, swiftui, android-kotlin, flutter, react-native).

4. **Documented naming decision** -- Created note explaining that `"budget"` is the canonical third-tier name in model-profiles.json, replacing the schema's incorrect `"speed"` label.

## Files Modified

- `config/token-budgets.json` -- removed `senior` and `security` from execution role family
- `config/stack-mappings.json` -- added `_todo` field, `_skill_status` markers, merged duplicate mobile key
- `.yolo-planning/phases/03-config-test-audit/03-02-model-profiles-NOTE.md` -- naming decision note (new file)

## Deviations

- The plan asked to grep Rust source for `"senior"` and `"security"` in role_families context and expected no hits. The Rust function `role_family()` at `tier_context.rs:70` does match these strings, but it is a hardcoded match arm unrelated to the JSON `role_families` field. No Rust code reads `role_families` from `token-budgets.json`. Removal from the JSON is safe and proceeded as planned.
