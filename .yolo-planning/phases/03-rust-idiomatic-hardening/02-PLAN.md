---
phase: "03"
plan: "02"
title: "Regex OnceLock caching — hooks and context modules"
wave: 1
depends_on: []
must_haves:
  - "REQ-04: security_filter.rs SENSITIVE_PATTERN compiled once via OnceLock"
  - "REQ-05: tier_context.rs filter_completed_phases regexes compiled once via OnceLock"
  - "REQ-06: commit_lint.rs commit format regex compiled once via OnceLock"
  - "REQ-07: list_todos.rs date regexes compiled once via OnceLock"
---

## Goal

Replace `Regex::new()` calls that execute on every function invocation with `std::sync::OnceLock<Regex>` statics. These regexes use constant patterns and never change at runtime, so compiling them once is correct and eliminates repeated work on hot paths.

## Strategy

Use `std::sync::OnceLock` (stable since Rust 1.80, available in Edition 2024):

```rust
use std::sync::OnceLock;
use regex::Regex;

fn get_my_regex() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"pattern").unwrap())
}
```

The `.unwrap()` inside `get_or_init` is safe because these are compile-time-constant regex patterns that are guaranteed valid.

## Task 1: Cache SENSITIVE_PATTERN regex in security_filter.rs

**Files:** `yolo-mcp-server/src/hooks/security_filter.rs`

Line 48: `let re = Regex::new(SENSITIVE_PATTERN)` is called on every hook invocation.

Replace with:
```rust
fn sensitive_regex() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(SENSITIVE_PATTERN).unwrap())
}
```

Then at line 48: `let re = sensitive_regex();`

Remove the `.map_err()` since the OnceLock version will panic on invalid regex (which cannot happen with a constant pattern). Adjust the function to not propagate a regex error (the original `.map_err` was defensive but unnecessary since `SENSITIVE_PATTERN` is a const).

Add `use std::sync::OnceLock;` to imports.

## Task 2: Cache regexes in tier_context.rs filter_completed_phases

**Files:** `yolo-mcp-server/src/commands/tier_context.rs`

Lines 136 and 151: Two `Regex::new()` calls inside `filter_completed_phases()`, which is called from `build_tier2_uncached()` on every cache miss.

Create two OnceLock statics:
```rust
fn table_complete_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^\|\s*(\d+)\s*\|\s*Complete\s*\|").unwrap())
}

fn phase_header_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^## Phase (\d+):").unwrap())
}
```

Add `use std::sync::OnceLock;` to imports.

## Task 3: Cache commit format regex in commit_lint.rs

**Files:** `yolo-mcp-server/src/commands/commit_lint.rs`

Line 40: `Regex::new(r"^(feat|fix|...|chore)\([a-z0-9._-]+\): .+")` compiled on every `execute()` call.

Create an OnceLock static:
```rust
fn commit_format_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"^(feat|fix|test|refactor|perf|docs|style|chore)\([a-z0-9._-]+\): .+").unwrap()
    })
}
```

Add `use std::sync::OnceLock;` to imports.

## Task 4: Cache date regexes in list_todos.rs

**Files:** `yolo-mcp-server/src/commands/list_todos.rs`

Line 160: `regex::Regex::new(r"\(added ([0-9]{4}-[0-9]{2}-[0-9]{2})\)")` in `parse_todo_line()` -- called per todo item.
Line 242: `regex::Regex::new(r" *\(added [0-9]{4}-[0-9]{2}-[0-9]{2}\)$")` in `execute()` -- called per displayed todo.

Create two OnceLock statics:
```rust
fn added_date_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\(added ([0-9]{4}-[0-9]{2}-[0-9]{2})\)").unwrap())
}

fn date_suffix_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r" *\(added [0-9]{4}-[0-9]{2}-[0-9]{2}\)$").unwrap())
}
```

Add `use std::sync::OnceLock;` and `use regex::Regex;` to module-level imports (currently uses `regex::Regex::new` inline).
