---
phase: 2
plan: 05
title: "Migrate security-filter and prompt-preflight hooks to native Rust"
wave: 1
depends_on: [1]
must_haves:
  - "security_filter blocks sensitive file patterns (.env, .pem, .key, credentials.json, etc.)"
  - "security_filter enforces GSD/YOLO plugin isolation with stale marker protection (24h)"
  - "prompt_preflight validates YOLO command invocation and sets .yolo-session marker"
  - "prompt_preflight warns on --execute without plans and --archive with incomplete phases"
  - "Both use std::fs for file I/O — no Command::new(bash), no jq, no awk"
---

## Task 1: Implement security_filter PreToolUse handler

**Files:** `yolo-mcp-server/src/hooks/security_filter.rs` (new)

**Acceptance:** PreToolUse handler. Extract `file_path` from `tool_input.file_path`, `tool_input.path`, or `tool_input.pattern` via serde. Fail-CLOSED: return exit 2 on any parse error. Block patterns via regex: `\.env$|\.env\.|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|credentials\.json$|secrets\.json$|service-account.*\.json$|node_modules/|\.git/|dist/|build/`. GSD isolation: if path contains `.planning/` but not `.yolo-planning/`, derive project root and check freshness of `.yolo-planning/.active-agent` and `.yolo-planning/.yolo-session` markers (fresh = mtime < 24h via `std::fs::metadata().modified()`). Block with exit 2 if markers are fresh. Return exit 0 to allow. Output `permissionDecision: "deny"` JSON on block.

## Task 2: Implement prompt_preflight UserPromptSubmit handler

**Files:** `yolo-mcp-server/src/hooks/prompt_preflight.rs` (new)

**Acceptance:** UserPromptSubmit handler. Extract `prompt`/`content` from input JSON. Skip if `.yolo-planning/` doesn't exist. GSD isolation marker management: if `.gsd-isolation` exists, detect `/yolo:` prefix or expanded YOLO prompt (YAML frontmatter with `name: yolo:`), create `.yolo-session` marker. Warning checks: (1) `--execute` without PLAN.md files in current phase dir -> warn, (2) `--archive` with incomplete phases in STATE.md -> warn. Return `hookSpecificOutput` JSON with warning as `additionalContext`. Always exit 0. YAML frontmatter detection: check if first non-empty line is `---`, then scan for `name: yolo:` pattern using `str::lines()` iterator.

## Task 3: Wire security and preflight hooks into dispatcher

**Files:** `yolo-mcp-server/src/hooks/dispatcher.rs`, `yolo-mcp-server/src/hooks/mod.rs`

**Acceptance:** Dispatcher routes `PreToolUse` to `security_filter::handle()` first. If security filter returns exit 2, pass through (block). Otherwise, check for skill-hook dispatch (Plan 07). Dispatcher routes `UserPromptSubmit` to `prompt_preflight::handle()`. Module declarations added to `mod.rs`.

## Task 4: Add tests for security_filter and prompt_preflight

**Files:** `yolo-mcp-server/src/hooks/security_filter.rs` (append tests), `yolo-mcp-server/src/hooks/prompt_preflight.rs` (append tests)

**Acceptance:** Tests cover: block .env files, block .pem files, allow normal paths, block .planning/ with fresh YOLO markers, allow .planning/ with no markers, allow .yolo-planning/ always, YAML frontmatter detection for expanded commands, GSD marker creation on `/yolo:` prefix, --execute warning without plans, --archive warning with incomplete phases. `cargo test` passes.
