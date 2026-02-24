---
phase: "03"
plan: "04"
title: "Frontmatter dedup and YoloConfig migration"
wave: 2
depends_on: [2, 3]
must_haves:
  - "REQ-11: Single extract_frontmatter() in commands/utils.rs used by all callers"
  - "REQ-12: phase_detect.rs config parsing migrated to YoloConfig struct"
  - "REQ-13: generate_contract.rs and verify_plan_completion.rs Regex calls use OnceLock"
  - "REQ-14: Duplicate frontmatter implementations removed from callers"
---

## Goal

1. Consolidate three duplicate frontmatter parsing implementations into `commands/utils.rs`.
2. Migrate `phase_detect.rs` from manual JSON parsing to the existing `YoloConfig` struct.
3. Apply OnceLock to remaining Regex::new() calls in files that overlap with the dedup work (generate_contract.rs, verify_plan_completion.rs).

## Background

Three separate frontmatter parsers exist:
- `hooks/validate_frontmatter.rs:74` — `extract_frontmatter()` returns raw YAML string
- `commands/parse_frontmatter.rs:53` — `parse_frontmatter_content()` returns JSON Map
- `commands/generate_contract.rs:10` — `split_frontmatter()` returns (frontmatter, body) tuple
- `commands/verify_plan_completion.rs:187` — `extract_frontmatter()` returns raw YAML string

The canonical functions should live in `commands/utils.rs`:
- `extract_frontmatter(content) -> Option<String>` (raw YAML between `---` delimiters)
- `split_frontmatter(content) -> (String, String)` (frontmatter text, body text)

## Task 1: Add canonical frontmatter functions to utils.rs

**Files:** `yolo-mcp-server/src/commands/utils.rs`

Add two public functions:

```rust
/// Extract raw frontmatter text between `---` delimiters.
/// Returns None if content doesn't start with `---` or has no closing delimiter.
pub fn extract_frontmatter(content: &str) -> Option<String> {
    let mut lines = content.lines();
    if lines.next()? != "---" {
        return None;
    }
    let mut fm_lines = Vec::new();
    for line in lines {
        if line == "---" {
            return if fm_lines.is_empty() { None } else { Some(fm_lines.join("\n")) };
        }
        fm_lines.push(line);
    }
    None // no closing ---
}

/// Split content into (frontmatter_text, body_text).
/// Returns empty frontmatter if no valid frontmatter block found.
pub fn split_frontmatter(content: &str) -> (String, String) {
    let mut lines = content.lines();
    let mut fm_lines = Vec::new();
    let mut body_lines = Vec::new();
    let mut dashes_seen = 0;

    for line in &mut lines {
        if line.trim() == "---" {
            dashes_seen += 1;
            if dashes_seen == 2 { break; }
            continue;
        }
        if dashes_seen == 1 {
            fm_lines.push(line);
        }
    }
    for line in lines {
        body_lines.push(line);
    }
    (fm_lines.join("\n"), body_lines.join("\n"))
}
```

## Task 2: Migrate callers to use utils.rs functions

**Files:** `yolo-mcp-server/src/hooks/validate_frontmatter.rs`, `yolo-mcp-server/src/commands/generate_contract.rs`, `yolo-mcp-server/src/commands/verify_plan_completion.rs`

For each file:
1. Remove the local `extract_frontmatter()` / `split_frontmatter()` implementation
2. Import from utils: `use crate::commands::utils::{extract_frontmatter, split_frontmatter};`
3. Adjust call sites if signatures differ slightly (e.g., `validate_frontmatter.rs` uses identical signature; `generate_contract.rs` `split_frontmatter` has identical signature; `verify_plan_completion.rs` has a slightly different implementation that strips leading `---` differently -- normalize to the utils version)

For `generate_contract.rs`, also apply OnceLock to the 2 Regex::new() calls at lines 98 and 123:
```rust
fn files_pattern_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\*\*Files:\*\*\s+(.+)").unwrap())
}
fn task_heading_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?m)^#{2,3}\s+Task\s+\d+").unwrap())
}
```

For `verify_plan_completion.rs`, also apply OnceLock to the 2 Regex::new() calls at lines 137 and 227:
```rust
fn hex_hash_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^[0-9a-fA-F]{7,}$").unwrap())
}
fn task_header_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?m)^### Task \d+").unwrap())
}
```

Note: `parse_frontmatter.rs` has its own `parse_frontmatter_content()` which returns a `Map<String, Value>` -- this is a higher-level parser that should continue to exist but can internally use `extract_frontmatter()` from utils for the delimiter splitting.

## Task 3: Migrate phase_detect.rs to YoloConfig

**Files:** `yolo-mcp-server/src/commands/phase_detect.rs`

Lines 207-234: Manual JSON parsing with `serde_json::from_str::<serde_json::Value>` and repeated `.get("key").and_then(|v| v.as_str())` calls.

Replace with:
```rust
use crate::commands::utils::load_config;

// In execute():
let config = load_config(&config_file);
cfg_effort = config.effort;
cfg_autonomy = config.autonomy;
cfg_auto_commit = config.auto_commit.to_string();
// ... etc for all fields
```

The `YoloConfig` struct already has all the fields with proper defaults, making 20+ lines of manual parsing into ~12 clean field accesses.

Note: `compaction_threshold` is not in `YoloConfig` currently. Either add it to the struct or keep a single manual parse for that one field.

## Task 4: Run cargo test

Verify all existing tests pass. Key test files to watch:
- `validate_frontmatter.rs` tests (extract_frontmatter behavior must be identical)
- `generate_contract.rs` tests (split_frontmatter + regex behavior must be identical)
- `verify_plan_completion.rs` tests
- `phase_detect.rs` tests (config parsing must produce identical output)
- `parse_frontmatter.rs` tests
