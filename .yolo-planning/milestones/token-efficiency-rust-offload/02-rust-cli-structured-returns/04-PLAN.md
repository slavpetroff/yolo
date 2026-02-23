---
phase: 2
plan: 4
title: "Suggest-next, bump-version, session-start, planning-git structured returns"
wave: 1
depends_on: []
must_haves:
  - "suggest-next returns JSON with suggestions array and reasoning context"
  - "bump-version returns JSON with old_version, new_version, files_updated list, remote_version"
  - "session-start returns JSON with steps completed, warnings, next_action"
  - "planning-git commit-boundary returns JSON with commit_hash or skipped reason"
  - "All existing tests in all 4 files still pass"
  - "New tests verify JSON output for each command"
---

# Plan 4: Suggest-next, Bump-version, Session-start, Planning-git Structured Returns

## Overview

Retrofit the remaining 4 commands: `suggest-next` (returns suggestion with no reasoning), `bump-version` (returns version string only), `session-start` (no step-level reporting), and `planning-git commit-boundary` (silent on no-op). These commands span different areas but share the pattern of returning minimal text that forces the LLM to make follow-up calls.

**NOTE:** Uses inline JSON envelope pattern (same shape as StructuredResponse from Plan 1) to avoid cross-plan file dependencies.

## Task 1: suggest-next structured return

**Files:**
- `yolo-mcp-server/src/commands/suggest_next.rs`

**Acceptance:**
- Returns JSON: `{"ok": true, "cmd": "suggest-next", "delta": {"context_cmd": "vibe", "suggestions": [{"command": "/yolo:fix", "reason": "Fix plan auth (failed verification)"}], "phase_num": "1", "phase_name": "setup", "all_done": false, "deviation_count": 0, "effort": "balanced"}, "elapsed_ms": N}`
- Each suggestion is an object with `command` and `reason` fields, parsed from the current `"  /yolo:cmd -- reason"` format
- The `Context` struct data is exposed in the delta for transparency
- All existing tests pass

**Implementation Details:**

The current implementation builds a plain text string with `suggest(|s| out.push_str(...))`. Refactor:

1. Instead of appending to a string, collect suggestions into a `Vec<Value>`:
```rust
let mut suggestions: Vec<Value> = Vec::new();
let mut add_suggestion = |cmd: &str, reason: &str| {
    suggestions.push(json!({"command": cmd, "reason": reason}));
};
```

2. Replace each `suggest("/yolo:fix -- Fix plan ...")` call with `add_suggestion("/yolo:fix", "Fix plan ...")` -- split on ` -- ` to separate command from reason

3. Build the JSON response at the end:
```rust
let response = json!({
    "ok": true,
    "cmd": "suggest-next",
    "delta": {
        "context_cmd": cmd,
        "suggestions": suggestions,
        "phase_num": ctx.active_phase_num,
        "phase_name": ctx.active_phase_name,
        "all_done": ctx.all_done,
        "deviation_count": ctx.deviation_count,
        "effort": ctx.effort,
        "has_project": ctx.has_project,
        "map_staleness": ctx.map_staleness
    },
    "elapsed_ms": start.elapsed().as_millis() as u64
});
```

4. Keep the existing text output format as a `"text"` field in delta for backward compatibility, in case any caller parses it.

## Task 2: bump-version structured return

**Files:**
- `yolo-mcp-server/src/commands/bump_version.rs`

**Acceptance:**
- Bump mode returns JSON: `{"ok": true, "cmd": "bump-version", "changed": ["VERSION", ".claude-plugin/plugin.json", ...], "delta": {"old_version": "1.2.3", "new_version": "1.2.4", "remote_version": "1.2.3", "files_updated": [{"path": "VERSION", "old": "1.2.3", "new": "1.2.4"}, ...]}, "elapsed_ms": N}`
- Verify mode returns JSON: `{"ok": true/false, "cmd": "bump-version", "delta": {"mode": "verify", "versions": [{"file": "VERSION", "version": "1.2.3", "status": "OK"}, ...], "all_match": true/false}, "elapsed_ms": N}`
- Exit code 1 for verify mismatch (already correct)
- All existing tests pass

**Implementation Details:**

For `bump_version()`:
1. Collect each file update as a `{"path", "old", "new"}` object into a `Vec<Value>`
2. Track `changed` files list separately
3. Build envelope with delta containing `old_version`, `new_version`, `remote_version`, `files_updated`

For `verify_versions()`:
1. Collect version info as `{"file", "version", "status"}` objects
2. Track `all_match` boolean
3. Return exit code 0 if all match, 1 if mismatch (already correct)

## Task 3: planning-git commit-boundary structured return

**Files:**
- `yolo-mcp-server/src/commands/planning_git.rs`

**Acceptance:**
- commit-boundary returns JSON: `{"ok": true, "cmd": "planning-git", "delta": {"subcommand": "commit-boundary", "action": "plan phase 1", "committed": true, "commit_hash": "abc1234", "pushed": false}, "elapsed_ms": N}`
- When no staged changes (no-op), returns: `{"ok": true, "cmd": "planning-git", "delta": {"subcommand": "commit-boundary", "committed": false, "reason": "no staged changes"}, "elapsed_ms": N}` with exit code 3 (SKIPPED)
- When tracking mode is not "commit", returns: `{"ok": true, "cmd": "planning-git", "delta": {"subcommand": "commit-boundary", "committed": false, "reason": "tracking mode is not commit"}, "elapsed_ms": N}` with exit code 3
- sync-ignore and push-after-phase also return structured JSON with appropriate delta
- All existing tests pass

**Implementation Details:**

For `handle_commit_boundary()`:
1. After successful `git commit`, capture the commit hash:
```rust
let hash_output = Command::new("git")
    .args(["rev-parse", "--short", "HEAD"])
    .current_dir(cwd)
    .output();
let commit_hash = hash_output.ok()
    .and_then(|o| String::from_utf8(o.stdout).ok())
    .map(|s| s.trim().to_string());
```
2. Track whether push happened
3. Build JSON envelope

For `handle_sync_ignore()`:
- Delta: `{"subcommand": "sync-ignore", "tracking_mode": "commit", "transient_ignore_written": true}`

For `handle_push_after_phase()`:
- Delta: `{"subcommand": "push-after-phase", "pushed": true/false, "reason": "..."}`

## Task 4: session-start structured return

**Files:**
- `yolo-mcp-server/src/commands/session_start.rs`

**Acceptance:**
- session-start still returns the `hookSpecificOutput` JSON structure (required by Claude hooks)
- ADDS a `"structuredResult"` field at the top level of the returned JSON containing the standard envelope
- The `structuredResult` includes: `steps_completed` (list of step names that ran), `warnings` (list), `next_action`, `milestone`, `phase_info`, `config_summary`
- All existing tests pass

**Implementation Details:**

session-start is special because it returns a `hookSpecificOutput` JSON for the Claude hooks system. The structured result is embedded alongside:

1. Track each step as it completes:
```rust
let mut steps = Vec::new();
steps.push("dependency_check");
steps.push("compaction_check");
// ... etc for each numbered step
```

2. Capture warnings from `flag_warnings` and `update_msg`

3. At the end, build the structured result:
```rust
let structured = json!({
    "ok": true,
    "cmd": "session-start",
    "delta": {
        "steps_completed": steps,
        "warnings": warnings_list,
        "next_action": next_action_str,
        "milestone": milestone_slug,
        "phase": phase_pos,
        "phase_total": phase_total,
        "config": {
            "effort": config_effort,
            "autonomy": config_autonomy,
            "auto_push": config_auto_push
        }
    },
    "elapsed_ms": start.elapsed().as_millis() as u64
});
```

4. Embed in the existing return:
```rust
let out = json!({
    "hookSpecificOutput": { /* existing */ },
    "structuredResult": structured
});
```

This preserves backward compatibility with the hooks system while adding the structured data.

## Task 5: Update tests for all 4 commands

**Files:**
- `yolo-mcp-server/src/commands/suggest_next.rs` (test module)
- `yolo-mcp-server/src/commands/bump_version.rs` (test module)
- `yolo-mcp-server/src/commands/planning_git.rs` (test module)
- `yolo-mcp-server/src/commands/session_start.rs` (test module)

**Acceptance:**
- All existing test assertions hold
- suggest-next tests parse JSON and validate suggestions array
- bump-version tests validate old/new version in JSON delta
- planning-git tests validate committed/skipped status
- session-start tests validate structuredResult exists alongside hookSpecificOutput

**Implementation Details:**

For suggest-next, update test assertions:
```rust
let (out, code) = run_suggest(&["init"], dir.path()).unwrap();
assert_eq!(code, 0);
let json: Value = serde_json::from_str(&out).unwrap();
assert_eq!(json["ok"], true);
assert_eq!(json["cmd"], "suggest-next");
let suggestions = json["delta"]["suggestions"].as_array().unwrap();
assert!(suggestions.iter().any(|s| s["command"].as_str().unwrap().contains("/yolo:vibe")));
```

For planning-git commit-boundary, verify commit hash is captured:
```rust
let json: Value = serde_json::from_str(&output).unwrap();
assert_eq!(json["delta"]["committed"], true);
assert!(json["delta"]["commit_hash"].as_str().unwrap().len() >= 7);
```

For session-start, verify both fields exist:
```rust
let json: Value = serde_json::from_str(&output).unwrap();
assert!(json["hookSpecificOutput"].is_object());
assert!(json["structuredResult"]["ok"] == true);
```
