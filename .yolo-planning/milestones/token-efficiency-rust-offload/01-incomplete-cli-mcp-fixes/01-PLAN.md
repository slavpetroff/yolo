---
phase: 1
plan: 01
title: "Fix infer command: add manifest-based tech stack detection and purpose extraction"
wave: 1
depends_on: []
must_haves:
  - "yolo infer detects tech stack from pyproject.toml, Cargo.toml, package.json, go.mod, etc. when STACK.md is absent or lacks expected headers"
  - "yolo infer extracts project purpose from README.md and PROJECT.md as fallbacks when CONCERNS.md is absent"
  - "End-to-end: yolo infer on a project with pyproject.toml containing fastapi returns Python, FastAPI in tech_stack"
---

## Task 1: Add manifest-based tech stack detection as fallback in infer_project_context.rs
**Files:** `yolo-mcp-server/src/commands/infer_project_context.rs`
**Acceptance:** When STACK.md is absent or its `## Languages` / `## Key Technologies` sections yield no results, the command reads manifest files (pyproject.toml, Cargo.toml, package.json, go.mod, requirements.txt, Gemfile, composer.json, mix.exs, pom.xml, build.gradle) from `repo_root` and extracts language/framework names. The `tech_stack` field is populated with detected items and `source` is set to the manifest filename(s).

### Implementation Details

The current STACK.md parser (lines 91-148) only matches two exact headings: `## Languages` (table format with `|` rows) and `## Key Technologies` (bullet list). Real-world STACK.md files use different headings like `## Primary Languages`, `## Frameworks & Libraries` (as in this project's own STACK.md).

Two fixes needed:
1. **Broaden STACK.md heading matching** — match `## Primary Languages` and `## Frameworks` variants in addition to exact matches.
2. **Add manifest fallback** — when STACK.md parsing yields empty results, scan repo_root for manifest files and extract:
   - `Cargo.toml` → "Rust"
   - `pyproject.toml` / `requirements.txt` → "Python" + scan for framework deps (fastapi, django, flask)
   - `package.json` → "JavaScript/TypeScript" + scan for framework deps (react, vue, next, express)
   - `go.mod` → "Go"
   - `Gemfile` → "Ruby"
   - `mix.exs` → "Elixir"
   - `composer.json` → "PHP"
   - `pom.xml` / `build.gradle` → "Java"

Source attribution: set `source` to `"manifest:<filename>"` to distinguish from STACK.md.

## Task 2: Add README.md and PROJECT.md fallback for purpose extraction
**Files:** `yolo-mcp-server/src/commands/infer_project_context.rs`
**Acceptance:** When CONCERNS.md is absent or yields no purpose, the command reads README.md from `repo_root` and extracts the first non-empty paragraph after the `# Title` as purpose. PROJECT.md is tried as second fallback using its `## Description` or first paragraph. The `purpose` field is populated with `source` set to `"README.md"` or `"PROJECT.md"`.

### Implementation Details

Current code (lines 186-215) only reads `CONCERNS.md` from `codebase_dir`. Add two sequential fallbacks after CONCERNS.md:

1. **README.md** (at `repo_root`): Read the file, extract the `# <title>` line as project name context, then take the first non-heading, non-empty paragraph (up to 200 chars) as purpose text.
2. **PROJECT.md** (at `repo_root`): Look for `## Description` section and extract its content, or fall back to first paragraph.

## Task 3: Broaden STACK.md heading recognition
**Files:** `yolo-mcp-server/src/commands/infer_project_context.rs`
**Acceptance:** STACK.md files using headings like `## Primary Languages`, `## Frameworks & Libraries`, or `## Build System` are parsed correctly. The heading matching is case-insensitive substring-based (e.g., a heading containing "language" triggers the language parser).

### Implementation Details

Replace exact string matches at lines 99/103 with substring checks:
- Any `##` heading containing "language" (case-insensitive) → enter language parsing mode
- Any `##` heading containing "framework" or "technolog" or "librar" → enter key-tech parsing mode
- Also support `**Name**` bold format in bullet items (already handled) AND `- Name (X files)` format common in auto-generated STACK.md files

## Task 4: Add unit tests for manifest fallback and README purpose extraction
**Files:** `yolo-mcp-server/src/commands/infer_project_context.rs`
**Acceptance:** At least 4 new unit tests covering: (a) manifest-based stack detection with pyproject.toml, (b) manifest-based detection with Cargo.toml, (c) README.md purpose extraction, (d) PROJECT.md purpose extraction. All tests pass.

### Implementation Details

Add tests in the existing `#[cfg(test)] mod tests` block:
- `test_infer_manifest_python`: Create tempdir with pyproject.toml containing `[project]\nname = "myapp"\ndependencies = ["fastapi"]`, no STACK.md. Verify tech_stack includes "Python" and "fastapi".
- `test_infer_manifest_rust`: Create tempdir with Cargo.toml. Verify tech_stack includes "Rust".
- `test_infer_readme_purpose`: Create tempdir with README.md containing `# My App\n\nA web service for managing notes.`. No CONCERNS.md. Verify purpose.value contains "web service".
- `test_infer_project_md_purpose`: Create tempdir with PROJECT.md containing `## Description\nTask management platform`. Verify purpose extracted.
