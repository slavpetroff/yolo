---
phase: "03"
plan: "03"
title: "Regex OnceLock caching — command modules batch 2"
wave: 1
depends_on: []
must_haves:
  - "REQ-08: hard_gate.rs commit format regex compiled once via OnceLock"
  - "REQ-09: diff_against_plan.rs stat regex compiled once via OnceLock"
  - "REQ-10: phase_detect.rs digit prefix regex compiled once via OnceLock"
---

## Goal

Replace remaining `Regex::new()` calls in command modules with `std::sync::OnceLock<Regex>` statics. This completes the regex caching effort for files not touched by Plan 02.

## Task 1: Cache commit format regex in hard_gate.rs

**Files:** `yolo-mcp-server/src/commands/hard_gate.rs`

Line 290: `let re = Regex::new(r"^(feat|fix|test|refactor|perf|docs|style|chore)\(.+\): .+").unwrap();` inside the `"commit_format"` match arm of `execute()`.

Create an OnceLock static:
```rust
fn commit_format_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"^(feat|fix|test|refactor|perf|docs|style|chore)\(.+\): .+").unwrap()
    })
}
```

Replace line 290 with: `let re = commit_format_re();`

Add `use std::sync::OnceLock;` to imports.

## Task 2: Cache stat regex in diff_against_plan.rs

**Files:** `yolo-mcp-server/src/commands/diff_against_plan.rs`

Line 180: `let stat_re = Regex::new(r"^ ([^ ].+?)\s+\|").unwrap();` inside `get_git_files()`, called once per `execute()`.

Create an OnceLock static:
```rust
fn git_stat_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^ ([^ ].+?)\s+\|").unwrap())
}
```

Replace line 180 with: `let stat_re = git_stat_re();`

Add `use std::sync::OnceLock;` to imports.

## Task 3: Cache digit prefix regex in phase_detect.rs

**Files:** `yolo-mcp-server/src/commands/phase_detect.rs`

Line 147: `let re = regex::Regex::new(r"^(\d+).*").unwrap();` inside a loop that iterates over phase directories. This is the most critical hot-path regex since it recompiles on every loop iteration.

Create an OnceLock static:
```rust
fn digit_prefix_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^(\d+).*").unwrap())
}
```

Move the `let re = ...` line outside the loop or replace inline with `digit_prefix_re()`.

Add `use std::sync::OnceLock;` and `use regex::Regex;` to imports (currently uses `regex::Regex::new` inline).
