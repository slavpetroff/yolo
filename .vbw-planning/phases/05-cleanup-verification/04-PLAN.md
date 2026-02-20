---
phase: 5
plan: 04
title: "Update documentation and configuration references"
wave: 2
depends_on: ["05-01", "05-02", "05-03"]
must_haves:
  - "CLAUDE.md updated to remove scripts/bump-version.sh references"
  - "hooks.json confirmed pointing to Rust binary only (no .sh fallback)"
  - "conventions.json updated to remove hook-wrapper.sh reference"
  - ".vbw-planning/codebase/ARCHITECTURE.md updated if it references scripts/"
  - "No documentation file references scripts/*.sh as current infrastructure"
---

## Task 1: Update CLAUDE.md to remove bash script references

**Files:** `CLAUDE.md`

**Acceptance:** Both YOLO Rules and VBW Rules sections: `scripts/bump-version.sh` changed to `yolo bump-version` (2 occurrences). The rule about not bumping version still applies but references the CLI command instead. No other .sh references exist in CLAUDE.md. File validates as proper Markdown.

## Task 2: Update hooks.json and conventions.json

**Files:** `hooks/hooks.json`, `.vbw-planning/conventions.json`

**Acceptance:** hooks.json: Verify all hook commands point to `$HOME/.cargo/bin/yolo hook <Event>` — no .sh fallback paths. If any .sh references remain, remove them. conventions.json: Rule about `hook-wrapper.sh` updated to reference the Rust hook dispatcher. `jq '.' hooks/hooks.json` validates. `jq '.' .vbw-planning/conventions.json` validates.

## Task 3: Update ARCHITECTURE.md and any reference docs

**Files:** `.vbw-planning/codebase/ARCHITECTURE.md`

**Acceptance:** Any references to `scripts/` directory as containing active infrastructure updated to note that all scripts have been migrated to the `yolo` Rust CLI binary. The architecture now describes: hooks → `yolo hook <Event>`, commands → `yolo <command>`, no bash script dependencies. If ARCHITECTURE.md doesn't reference scripts/, no changes needed (verify and skip).

## Task 4: Clean up any remaining .sh references in config and metadata files

**Files:** `.vbw-planning/.execution-state.json` (read-only verify), `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

**Acceptance:** .execution-state.json: Historical references to .sh scripts in completed task titles are acceptable (they are historical records). plugin.json: No .sh references in current configuration. marketplace.json: No .sh references. `grep -r '\.sh' .claude-plugin/ --include='*.json'` returns empty.

## Task 5: Final documentation audit and commit

**Files:** All documentation files (audit)

**Acceptance:** `grep -rl 'scripts/.*\.sh' CLAUDE.md hooks/ .claude-plugin/` returns empty. `grep -rl 'hook-wrapper\.sh' .` returns only historical/archived files (if any). All JSON files validate with `jq`. Single atomic commit: `docs: update documentation and config to reflect Rust-only infrastructure`.
