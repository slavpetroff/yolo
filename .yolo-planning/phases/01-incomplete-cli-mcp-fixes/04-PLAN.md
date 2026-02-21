---
phase: 1
plan: 04
title: "Route unrouted CLI commands and fix detect-stack glob patterns"
wave: 1
depends_on: []
must_haves:
  - "All 6 unrouted modules (clean-stale-teams, tmux-watchdog, verify-init-todo, verify-vibe, verify-claude-bootstrap, pre-push) are routable via CLI"
  - "detect-stack handles glob patterns (*.csproj, *.sln) correctly"
---

## Task 1: Add missing CLI routes for 6 unrouted modules
**Files:** `yolo-mcp-server/src/cli/router.rs`
**Acceptance:** The following commands are routed in `run_cli()`: `clean-stale-teams`, `tmux-watchdog`, `verify-init-todo`, `verify-vibe`, `verify-claude-bootstrap`, `pre-push`. Each dispatches to the correct module function. `yolo <cmd>` no longer returns "Unknown command" for these.

### Implementation Details

These 6 modules exist in `mod.rs` and have compiled `execute` or equivalent public functions, but the router's `match args[1].as_str()` block has no arms for them.

Add the following match arms before the `_ => Err(...)` fallthrough:

```rust
"clean-stale-teams" => {
    let claude_dir = cwd.join(".claude");
    let log_file = cwd.join(".yolo-planning").join("clean-stale-teams.log");
    let (teams, tasks) = clean_stale_teams::clean_stale_teams(&claude_dir, &log_file);
    Ok((format!("Cleaned {} teams, {} task dirs", teams, tasks), 0))
}
"tmux-watchdog" => {
    // Expose get_tmux_session for debugging
    match tmux_watchdog::get_tmux_session() {
        Some(session) => Ok((format!("tmux session: {}", session), 0)),
        None => Ok(("Not running in tmux".to_string(), 0)),
    }
}
"verify-init-todo" => {
    verify_init_todo::execute(&args, &cwd)
}
"verify-vibe" => {
    verify_vibe::execute(&args, &cwd)
}
"verify-claude-bootstrap" => {
    verify_claude_bootstrap::execute(&args, &cwd)
}
"pre-push" => {
    pre_push_hook::execute(&args, &cwd)
}
```

Also add the missing imports to the `use crate::commands::{...}` line: `clean_stale_teams`, `tmux_watchdog`, `verify_init_todo`, `verify_vibe`, `verify_claude_bootstrap`, `pre_push_hook`.

## Task 2: Fix detect-stack glob pattern matching for wildcards
**Files:** `yolo-mcp-server/src/commands/detect_stack.rs`
**Acceptance:** Detection patterns like `*.csproj` and `*.sln` that use glob wildcards are matched correctly by scanning directory entries. The `dotnet` and `kotlin` stacks are detectable when `.csproj`, `.sln`, or `build.gradle.kts` files exist.

### Implementation Details

The `check_pattern` function (line 119-168) handles two pattern types:
1. Colon patterns (`file:dep`) — works correctly
2. File/directory patterns — uses `project_dir.join(pattern).exists()` which treats `*.csproj` as a literal filename

Fix: When the pattern contains `*`, use a directory scan to match:
```rust
if pattern.contains('*') {
    // Glob-style: check if any file in project_dir matches the glob
    if let Ok(entries) = fs::read_dir(project_dir) {
        for e in entries.filter_map(|x| x.ok()) {
            if let Some(name) = e.file_name().to_str() {
                if glob_matches(pattern, name) {
                    return true;
                }
            }
        }
    }
    return false;
}
```

Add a minimal `glob_matches(pattern, name)` helper that handles `*.ext` patterns (prefix `*` means "any characters" before the suffix).

## Task 3: Add unit tests for new routes and glob detection
**Files:** `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/detect_stack.rs`
**Acceptance:** (a) Router test verifying `verify-init-todo`, `verify-vibe`, `pre-push` don't return "Unknown command". (b) detect_stack test with `*.csproj` glob pattern matches a `.csproj` file. All tests pass.

### Implementation Details

Router test:
```rust
#[test]
fn test_routed_verify_commands() {
    let path = std::env::temp_dir().join(format!("yolo-test-route-{}.db", std::process::id()));
    // These should not return "Unknown command" errors
    for cmd in &["verify-init-todo", "verify-vibe", "pre-push"] {
        let result = run_cli(vec!["yolo".into(), cmd.to_string()], path.clone());
        // May fail for other reasons, but should NOT be "Unknown command"
        if let Err(e) = &result {
            assert!(!e.contains("Unknown command"), "Command {} should be routed", cmd);
        }
    }
    let _ = std::fs::remove_file(&path);
}
```

detect_stack test:
```rust
#[test]
fn test_detect_stack_glob_pattern() {
    let dir = tempdir().unwrap();
    let config_dir = dir.path().join("config");
    fs::create_dir_all(&config_dir).unwrap();
    fs::write(config_dir.join("stack-mappings.json"), r#"{
        "languages": {
            "dotnet": { "skills": ["dotnet-skill"], "detect": ["*.csproj"] }
        }
    }"#).unwrap();
    fs::write(dir.path().join("MyApp.csproj"), "<Project/>").unwrap();
    let (out, _) = execute(&["yolo".into(), "detect-stack".into(), dir.path().to_string_lossy().to_string()], dir.path()).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
    assert!(parsed["detected_stack"].as_array().unwrap().iter().any(|v| v == "dotnet"));
}
```
