---
phase: "04"
plan: "01"
title: "extract-changelog CLI command"
wave: 1
depends_on: []
must_haves:
  - "yolo extract-changelog extracts the latest version block from CHANGELOG.md"
  - "Returns JSON with version, date, and body fields"
  - "Handles missing CHANGELOG.md gracefully (exit 0, empty body)"
  - "Handles missing version section gracefully"
  - "Tests cover: normal extraction, missing file, empty changelog"
---

# Plan 01: extract-changelog CLI command

Add a `yolo extract-changelog` command that extracts the latest version section from CHANGELOG.md and returns it as structured JSON.

## Task 1

**Files:** `yolo-mcp-server/src/commands/extract_changelog.rs`

**What to do:**

1. Create a new module `extract_changelog.rs` with:
   - `pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String>`
   - Usage: `yolo extract-changelog [changelog_path]` (default: `CHANGELOG.md` in cwd)
   - Read the changelog file. If it doesn't exist, return `{"ok":true,"cmd":"extract-changelog","delta":{"version":null,"date":null,"body":"","found":false}}`
   - Parse the file looking for the first `## v{VERSION}` or `## [{VERSION}]` header line.
   - Extract: version string, optional date (parenthesized after version), and all content until the next `## ` header or EOF.
   - Return JSON: `{"ok":true,"cmd":"extract-changelog","delta":{"version":"X.Y.Z","date":"YYYY-MM-DD","body":"...markdown...","found":true}}`

## Task 2

**Files:** `yolo-mcp-server/src/commands/extract_changelog.rs`

**What to do:**

1. Add tests:
   - `test_extract_normal` — CHANGELOG with two version sections, extracts only the first
   - `test_extract_missing_file` — no CHANGELOG.md, returns found=false
   - `test_extract_empty_changelog` — file exists but has no version sections, returns found=false
   - `test_extract_with_date` — version header with `(2026-02-24)` date, extracts date field

## Task 3

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`

**What to do:**

1. Add `pub mod extract_changelog;` to mod.rs.
2. Wire into router.rs: import, enum variant `ExtractChangelog`, from_str `"extract-changelog"`, as_str, dispatch arm, all_names entry.

## Task 4

**Files:** `yolo-mcp-server/src/commands/extract_changelog.rs`

**What to do:**

1. Run `cargo test -p yolo-mcp-server extract_changelog` and confirm all tests pass.
2. Run `cargo build --release -p yolo-mcp-server` and confirm it builds clean.
3. Fix any compilation or test failures.

**Commit:** `feat(04-01): add extract-changelog CLI command`
